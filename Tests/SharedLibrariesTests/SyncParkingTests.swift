import ArtExtraction
import Foundation
@testable import SharedLibraries
import Testing

/// Records this version of the app can't read (library sync design, "Records kept aside").
@Suite struct SyncParkingTests {
    let devices: SyncedDevices

    init() throws {
        devices = try SyncedDevices()
    }

    var first: SharedLibrary { devices.firstLibrary }
    var second: SharedLibrary { devices.secondLibrary }

    /// The first device's pawn box as it sends it, and the same record naming a game this version doesn't know.
    func pawnBoxRecords() throws -> (readable: RemoteChange, unreadable: RemoteChange) {
        try first.add(devices.first.pawnBox(), keeping: false)
        let sent = try #require(try first.sendEverything().first)
        guard case .saved(var record, let fields) = sent else { throw CocoaError(.coderInvalidValue) }
        var payload = try #require(try JSONSerialization.jsonObject(with: record.payload) as? [String: Any])
        payload["game"] = "a game added since"
        record.payload = try JSONSerialization.data(withJSONObject: payload)
        return (sent, .saved(record, systemFields: fields))
    }

    func parkedNames(in library: SharedLibrary) throws -> [String] {
        try library.connection().rows("SELECT name FROM parkedRecords ORDER BY name").compactMap { $0.text("name") }
    }

    @Test func keepsAsideARecordItCantReadAndAppliesTheRest() throws {
        let source = try pawnBoxRecords().unreadable
        let creature = CustomCreatureRecord(id: UUID(), campaignID: nil, sharedVersion: nil, record: Data([1]))
        try first.save(creature)
        let rest = try first.sendEverything()

        let report = try second.applyRemote([source] + rest)
        #expect(report == RemoteApplyReport(applied: 1, parked: 1, unchanged: 0))
        #expect(try second.sources().isEmpty)
        #expect(try second.customCreatures().map(\.id) == [creature.id])
        #expect(try parkedNames(in: second) == [source.id.name])
    }

    @Test func doesntSendItsOwnCopyOverARecordItCantRead() throws {
        let source = try pawnBoxRecords().unreadable
        let copy = devices.second.root.appending(path: "copy.pdf")
        try FileManager.default.copyItem(at: devices.first.pawnBox(), to: copy)
        try second.add(copy, keeping: false)

        try second.applyRemote([source])
        #expect(try second.syncCandidates().isEmpty)
        #expect(try second.outgoingRecord(source.id) == nil)
        #expect(try second.artEntries().count == 2)
    }

    @Test func appliesARecordKeptAsideOnceItCanReadIt() throws {
        let source = try pawnBoxRecords().readable
        guard case .saved(let record, let fields) = source else { return }
        try second.parkUnreadable(record, fields: fields, in: second.connection())

        let report = try second.applyRemote([])
        #expect(report == RemoteApplyReport(applied: 1, parked: 0, unchanged: 0))
        #expect(try second.artEntries() == first.artEntries())
        #expect(try parkedNames(in: second).isEmpty && second.syncCandidates().isEmpty)
    }

    @Test func leavesARecordItStillCantReadWithoutATransaction() throws {
        try second.applyRemote([try pawnBoxRecords().unreadable])
        let counter = try second.changeCounter()

        #expect(try second.applyRemote([]) == RemoteApplyReport())
        #expect(try second.changeCounter() == counter)
        #expect(try parkedNames(in: second).count == 1)
    }

    @Test func dropsARecordKeptAsideWhenALaterCopyOrItsDeletionArrives() throws {
        let records = try pawnBoxRecords()
        try second.applyRemote([records.unreadable])
        try second.applyRemote([records.readable])
        #expect(try parkedNames(in: second).isEmpty)
        #expect(try second.artEntries().count == 2)

        try second.applyRemote([records.unreadable])
        try second.applyRemote([.deleted(records.unreadable.id)])
        #expect(try parkedNames(in: second).isEmpty && second.sources().isEmpty)
    }

    @Test func appliesTheLaterCopyOfANoteThatWasWaitingForItsArt() throws {
        try first.add(devices.first.pawnBox(), keeping: false)
        let art = try #require(try first.artIDs().first)
        let source = try first.sendEverything()
        try first.setNote(ArtNote(tags: ["early"]), forArt: art)
        try second.applyRemote(try first.sendEverything())
        #expect(try parkedNames(in: second).count == 1)

        try first.setNote(ArtNote(tags: ["late"]), forArt: art)
        try second.applyRemote(source + (try first.sendEverything(fields: Data([2]))))
        #expect(try second.notes()[art]?.tags == ["late"])
        #expect(try parkedNames(in: second).isEmpty)
    }
}
