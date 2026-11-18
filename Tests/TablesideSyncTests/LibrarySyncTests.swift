import CloudKit
import Foundation
import SharedLibraries
import Testing
@testable import TablesideSync

/// The library's zones on the engine (library sync design, "The library's handler").
@Suite struct LibrarySyncTests {
    let syncing: SyncingDevice

    init() async throws {
        syncing = try await SyncingDevice()
    }

    var device: TestDevice { syncing.device }
    var sync: LibrarySync { syncing.sync }
    var engine: SyncEngine { syncing.engine }
    var queue: RecordingQueue { syncing.queue }

    /// The names of the records queued to save, sorted.
    var queuedSaves: [String] {
        queue.added.compactMap { change in
            if case .save(let recordID) = change { recordID.recordName } else { nil }
        }.sorted()
    }

    @Test func savesBothZonesAtTheFirstStartAndFetchesOnlyTheLibrarys() async {
        #expect(queue.zones.map(\.zoneName) == ["Library", "Pictures"])
        #expect(await engine.unfetchedZones().map(\.zoneName) == ["Pictures"])
    }

    @Test func queuesLocalChangesOnceTheyStopComing() async throws {
        try device.fillWithEveryKind(try device.library(.fieldGuide))
        await sync.libraryChanged()
        await sync.libraryChanged()

        #expect(await eventually { !queue.added.isEmpty })
        try await Task.sleep(for: .milliseconds(60))
        #expect(queue.added.count == SyncKind.allCases.count)
    }

    @Test func sendsEachRecordOnceAndRemembersTheServerTookIt() async throws {
        try device.fillWithEveryKind(try device.library())
        let records = await syncing.sendEverything()
        #expect(records.count == SyncKind.allCases.count)
        #expect(await sync.pendingChanges().isEmpty)
        let uploads = device.folder.appending(path: "Sync/Outgoing/Turnkeeper")
        #expect(try FileManager.default.contentsOfDirectory(atPath: uploads.path).isEmpty)

        let sent = try #require(records.first).recordID
        #expect(await engine.record(for: sent) == nil)
        #expect(queue.removed == [.save(sent)])
        #expect(await engine.record(for: CKRecord.ID(recordName: "note-1", zoneID: .default)) == nil)
    }

    @Test func sendsTheDeletionOfARowThatIsGone() async throws {
        let library = try device.library()
        let art = try device.fillWithEveryKind(library)
        await syncing.sendEverything()
        _ = try library.setNote(nil, forArt: art)

        let deletion = SyncChange.delete(.library("note-\(art.uuidString)"))
        #expect(await sync.pendingChanges() == [deletion])
        await engine.sent(SentChanges(deleted: [deletion.recordID]))
        #expect(await sync.pendingChanges().isEmpty)
    }

    @Test func mergesWhatAnotherDeviceSentAndQueuesNothingBack() async throws {
        let other = try device.otherLibrary()
        let art = try device.fillWithEveryKind(other)
        queue.clear()
        await engine.receive(FetchedChanges(modifications: try device.serverRecords(of: other)))

        let library = try device.library()
        #expect(try library.notes() == [art: ArtNote(tags: ["club"])])
        #expect(try library.customArt().count == 1 && library.customCreatures().count == 1)
        #expect(queue.added.isEmpty)
        #expect(await sync.pendingChanges().isEmpty)

        _ = try other.setNote(nil, forArt: art)
        let deletion = FetchedChanges.Deletion(recordID: .library("note-\(art.uuidString)"), recordType: "Note")
        await engine.receive(FetchedChanges(deletions: [deletion]))
        #expect(try library.notes().isEmpty)
    }

    @Test func mergesARecordTheServerHoldsAndSendsOnlyWhatStillDiffers() async throws {
        let other = try device.otherLibrary()
        let art = try device.fillWithEveryKind(other)
        let server = try device.serverRecords(of: other)
        let library = try device.library()
        try library.add(device.pawnBox(), keeping: false)
        _ = try library.setNote(ArtNote(tags: ["axe"]), forArt: art)
        queue.clear()

        var refused: [FailedSave] = []
        for record in server where ["Source", "Note"].contains(record.recordType) {
            let mine = try #require(await engine.record(for: record.recordID))
            refused.append((mine, conflict(with: record)))
        }
        await engine.sent(SentChanges(failedSaves: refused))

        #expect(queuedSaves == ["note-\(art.uuidString)"])
        #expect(try library.notes() == [art: ArtNote(tags: ["axe"])])
        let again = try #require(await engine.record(for: .library("note-\(art.uuidString)")))
        #expect(again.recordID == .library("note-\(art.uuidString)"))
    }

    @Test func keepsAReadingRefusedWithoutItsAssetAsideUntilAFetchBringsIt() async throws {
        let other = try device.otherLibrary()
        try other.add(device.pawnBox(), keeping: false)
        let server = try #require(try device.serverRecords(of: other).first)
        let library = try device.library()
        try library.add(device.pawnBox(), keeping: false)
        let mine = try #require(await engine.record(for: server.recordID))
        queue.clear()

        // CloudKit hands over the server's record of a refused save without its asset files.
        let bare = CKRecord(recordType: server.recordType, recordID: server.recordID)
        await engine.sent(SentChanges(failedSaves: [(mine, conflict(with: bare))]))
        #expect(queue.added.isEmpty)
        #expect(await sync.pendingChanges().isEmpty)

        await engine.receive(FetchedChanges(modifications: [server]))
        #expect(queue.added.isEmpty)
        #expect(try library.syncCandidates().isEmpty)
        #expect(await sync.status == .upToDate)
    }

    @Test func sendsARecordTheServerLostAsANewOne() async throws {
        let library = try device.library()
        try library.add(device.pawnBox(), keeping: false)
        let record = try #require(await syncing.sendEverything().first)
        let id = try #require(LibraryRecordCoder.syncID(of: record.recordID))
        try library.add(device.pawnBox(), keeping: true)
        queue.clear()

        await engine.sent(SentChanges(failedSaves: [(record, CKError(.unknownItem)),
                                                    (record, CKError(.networkFailure))]))
        #expect(queuedSaves == [id.name])
        #expect(try #require(try library.outgoingRecord(id)).systemFields == nil)
    }

    @Test func savesItsZonesAndEveryRecordAgainWhenTheServerHasNoZone() async throws {
        let library = try device.library()
        try device.fillWithEveryKind(library)
        await syncing.sendEverything()
        _ = try library.setNote(ArtNote(tags: ["axe"]), forArt: try #require(try library.artEntries().first).id)
        let changed = try #require(await sync.pendingChanges().first.map(\.recordID))
        let mine = try #require(await engine.record(for: changed))
        queue.clear()

        await engine.sent(SentChanges(failedSaves: [(mine, CKError(.zoneNotFound))]))
        #expect(queue.zones.map(\.zoneName) == ["Library", "Pictures"])
        #expect(queuedSaves.count == SyncKind.allCases.count && queuedSaves.contains(changed.recordName))
    }

    @Test func uploadsAgainAfterAZoneWasDeletedButNotForAnothersZone() async throws {
        try device.library().add(device.pawnBox(), keeping: false)
        await syncing.sendEverything()
        queue.clear()

        await engine.zonesDeleted([(CKRecordZone.ID(zoneName: "Campaign"), .deleted)])
        #expect(queue.zones.isEmpty && queue.added.isEmpty)
        await engine.zonesDeleted([(LibraryRecordCoder.libraryZone, .deleted)])
        #expect(queue.zones.count == 2 && queue.added.count == 1)
        #expect(await sync.status == .upToDate)
    }
}
