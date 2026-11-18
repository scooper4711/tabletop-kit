import CloudKit
import Foundation
import Testing
@testable import TablesideSync

/// A zone's owner that records what the engine tells it.
actor FakeHandler: SyncZoneHandler {
    let zoneIDs: [CKRecordZone.ID]
    let unfetched: [CKRecordZone.ID]
    var pending: [SyncChange] = []
    var records: [CKRecord.ID: CKRecord] = [:]
    var savesZonesAgain = false
    private(set) var received: [FetchedChanges] = []
    private(set) var saved: [CKRecord.ID] = []
    private(set) var deleted: [CKRecord.ID] = []
    private(set) var settled: [CKError.Code] = []
    private(set) var accounts: [String?] = []
    private(set) var deletedZones: [String] = []
    private(set) var phases: [SyncPhase] = []

    init(zone: String, unfetched: [String] = []) {
        zoneIDs = [CKRecordZone.ID(zoneName: zone)]
        self.unfetched = unfetched.map { CKRecordZone.ID(zoneName: $0) }
    }

    func setPending(_ changes: [SyncChange]) { pending = changes }
    func setRecord(_ record: CKRecord) { records[record.recordID] = record }
    func saveZonesAgain() { savesZonesAgain = true }

    func zones() -> [CKRecordZone.ID] { zoneIDs }
    func unfetchedZones() -> [CKRecordZone.ID] { unfetched }
    func pendingChanges() -> [SyncChange] { pending }
    func record(for recordID: CKRecord.ID) -> CKRecord? { records[recordID] }
    func received(_ changes: FetchedChanges) { received.append(changes) }

    func sent(saved: [CKRecord], deleted: [CKRecord.ID]) {
        self.saved += saved.map(\.recordID)
        self.deleted += deleted
    }

    func settle(_ failures: [FailedSave]) -> Bool {
        settled += failures.map(\.error.code)
        return savesZonesAgain
    }

    func accountChanged(to user: String?) { accounts.append(user) }

    func zoneDeleted(_ zoneID: CKRecordZone.ID, reason: CKDatabase.DatabaseChange.Deletion.Reason) -> Bool {
        deletedZones.append("\(zoneID.zoneName) \(reason)")
        return savesZonesAgain && zoneIDs.contains(zoneID)
    }

    func phaseChanged(_ phase: SyncPhase) { phases.append(phase) }
}

/// One engine for several zones' owners (library sync design, "The engine").
@Suite struct SyncEngineTests {
    let library = FakeHandler(zone: "Library", unfetched: ["Pictures"])
    let campaign = FakeHandler(zone: "Campaign")
    let queue = RecordingQueue()
    let store = MemoryStateStore()

    func recordID(_ name: String, in zone: String) -> CKRecord.ID {
        CKRecord.ID(recordName: name, zoneID: CKRecordZone.ID(zoneName: zone))
    }

    func record(_ name: String, in zone: String) -> CKRecord {
        CKRecord(recordType: "Thing", recordID: recordID(name, in: zone))
    }

    /// An engine over both handlers, started for the first time or again.
    func engine(isFirstStart: Bool = false) async -> SyncEngine {
        let engine = SyncEngine(handlers: [library, campaign], store: store)
        await engine.begin(with: queue, isFirstStart: isFirstStart)
        return engine
    }

    @Test func savesTheZonesAtTheFirstStartAndQueuesWhatIsPendingAtEachStart() async {
        await library.setPending([.save(recordID("a", in: "Library"))])
        await campaign.setPending([.delete(recordID("b", in: "Campaign"))])

        _ = await engine(isFirstStart: true)
        #expect(queue.zones.map(\.zoneName) == ["Library", "Campaign"])
        #expect(queue.added == [.save(recordID("a", in: "Library")), .delete(recordID("b", in: "Campaign"))])

        queue.clear()
        let later = await engine()
        #expect(queue.zones.isEmpty && queue.added.count == 2)
        queue.clear()
        await later.handlersChanged()
        #expect(queue.added.count == 2)
    }

    @Test func handsFetchedChangesToTheOwnerOfTheirZoneAndQueuesWhatThatLeaves() async {
        let engine = await engine()
        await library.setPending([.save(recordID("merged", in: "Library"))])
        let deletion = FetchedChanges.Deletion(recordID: recordID("gone", in: "Campaign"), recordType: "Thing")
        await engine.receive(FetchedChanges(modifications: [record("a", in: "Library")], deletions: [deletion]))

        #expect(await library.received.map { $0.modifications.map(\.recordID.recordName) } == [["a"]])
        #expect(await library.received.first?.deletions.isEmpty == true)
        #expect(await campaign.received.map { $0.deletions.map(\.recordID.recordName) } == [["gone"]])
        #expect(queue.added == [.save(recordID("merged", in: "Library"))])

        await engine.receive(FetchedChanges(modifications: [record("x", in: "Elsewhere")]))
        #expect(await library.received.count == 1)
        #expect(await campaign.received.count == 1)
    }

    @Test func asksTheOwnerForARecordAndForgetsASaveWithNoneToSend() async {
        let engine = await engine()
        await campaign.setRecord(record("a", in: "Campaign"))

        #expect(await engine.record(for: recordID("a", in: "Campaign"))?.recordID.recordName == "a")
        #expect(queue.removed.isEmpty)
        #expect(await engine.record(for: recordID("missing", in: "Campaign")) == nil)
        #expect(await engine.record(for: recordID("a", in: "Elsewhere")) == nil)
        #expect(queue.removed == [.save(recordID("missing", in: "Campaign")), .save(recordID("a", in: "Elsewhere"))])
    }

    @Test func leavesOutTheZonesItsHandlersFetchThemselves() async {
        #expect(await engine().unfetchedZones().map(\.zoneName) == ["Pictures"])
    }

    @Test func tellsTheOwnerWhatWasSentAndCountsAMissingRecordAsDeleted() async {
        let engine = await engine()
        let failedDeletes = [recordID("never", in: "Library"): CKError(.unknownItem),
                             recordID("busy", in: "Library"): CKError(.networkFailure)]
        await engine.sent(SentChanges(saved: [record("a", in: "Library"), record("b", in: "Campaign")],
                                      deleted: [recordID("old", in: "Library")], failedDeletes: failedDeletes))

        #expect(await library.saved.map(\.recordName) == ["a"])
        #expect(await library.deleted.map(\.recordName) == ["old", "never"])
        #expect(await campaign.saved.map(\.recordName) == ["b"])
        #expect(await campaign.settled.isEmpty)
        #expect(queue.added.isEmpty)
    }

    @Test func settlesRefusedSavesAndQueuesAgain() async {
        let engine = await engine()
        queue.clear()
        await library.setPending([.save(recordID("a", in: "Library"))])
        let refused: [FailedSave] = [(record("a", in: "Library"), CKError(.unknownItem))]
        await engine.sent(SentChanges(failedSaves: refused))
        #expect(await library.settled == [.unknownItem])
        #expect(await campaign.settled.isEmpty)
        #expect(queue.zones.isEmpty && queue.added == [.save(recordID("a", in: "Library"))])

        await library.saveZonesAgain()
        await engine.sent(SentChanges(failedSaves: [(record("a", in: "Library"), CKError(.zoneNotFound))]))
        #expect(queue.zones.map(\.zoneName) == ["Library"] && queue.added.count == 2)
    }

    @Test func tellsEveryHandlerWhoseICloudThisIsAndUploadsAfterASignIn() async {
        let engine = await engine()
        queue.clear()
        let user = CKRecord.ID(recordName: "_user")
        await engine.accountChanged(.signOut(previousUser: user))
        #expect(await library.accounts == [nil])
        #expect(queue.zones.isEmpty)

        await engine.accountChanged(.signIn(currentUser: user))
        await engine.accountChanged(.switchAccounts(previousUser: user,
                                                    currentUser: CKRecord.ID(recordName: "_other")))
        #expect(await campaign.accounts == [nil, "_user", "_other"])
        #expect(queue.zones.count == 4)
    }

    @Test func tellsEveryHandlerOfADeletedZoneAndUploadsForThoseThatAsk() async {
        let engine = await engine()
        queue.clear()
        await library.saveZonesAgain()
        await campaign.saveZonesAgain()
        await engine.zonesDeleted([(CKRecordZone.ID(zoneName: "Library"), .purged)])

        #expect(await library.deletedZones == ["Library purged"])
        #expect(await campaign.deletedZones == ["Library purged"])
        #expect(queue.zones.map(\.zoneName) == ["Library"])
    }

    @Test func passesOnThePhasesOfARoundAndKeepsTheEnginesState() async {
        let engine = await engine()
        await engine.phaseChanged(.willFetch)
        await engine.phaseChanged(.didFetch)
        #expect(await library.phases == [.willFetch, .didFetch])
        #expect(await campaign.phases.count == 2)

        #expect(await engine.savedState() == nil)
        await engine.saveState(Data([7]))
        #expect(await engine.savedState() == Data([7]))
    }
}
