import ArtExtraction
import Foundation
@testable import SharedLibraries
import Testing

/// Fetching again a record this device has already merged in, as a second app on the device does with its own
/// engine, or any app after its engine's state is lost (library sync design, "Skip what is known").
@Suite struct SyncRefetchTests {
    let devices: SyncedDevices
    let pawn = SyncFixture.pawnKey

    init() throws {
        devices = try SyncedDevices()
    }

    var first: SharedLibrary { devices.firstLibrary }

    @Test func keepsRowsDeletedHereWhenTheirSavedRecordsAreFetchedAgain() throws {
        let gremlin = creature(named: "Gremlin")
        let image = CustomArtRecord(id: UUID(), fileName: "a.png", sharedVersion: nil, record: Data())
        try first.write { writer in
            try SyncFixture.addSource("pawns", to: writer)
            try writer.merge(SyncFixture.entry([.init(.pawn, pawn, "pawns")]))
        }
        try first.save(gremlin)
        try first.save(image, image: Data([1]))
        try first.setNote(ArtNote(tags: ["club"]), forArt: pawn)
        try first.setCreatureArt(.custom(image.id), for: "gremlin")
        let rows = try first.sendEverything().filter { change in
            if case .saved(let record, _) = change { record.id.kind != .source } else { false }
        }

        try first.removeCustomCreature(id: gremlin.id)
        try first.removeCustomArt(id: image.id)
        try first.setNote(nil, forArt: pawn)
        try first.setCreatureArt(nil, for: "gremlin")
        let deletions = try first.syncCandidates().deletions
        #expect(deletions.count == 4)

        let report = try first.applyRemote(rows)
        #expect(report == RemoteApplyReport(applied: 0, parked: 0, unchanged: 4))
        #expect(try first.customCreatures().isEmpty && first.customArt().isEmpty && first.notes().isEmpty)
        #expect(try first.creatureArt().isEmpty)
        #expect(try first.syncCandidates().deletions == deletions)
    }

    @Test func keepsAPDFRemovedHereWhenItsSavedRecordIsFetchedAgain() throws {
        try first.add(devices.first.pawnBox(), keeping: true)
        let saved = try first.sendEverything()
        let source = try #require(try first.sources().first)
        try first.remove(sourceID: source.id)

        let report = try first.applyRemote(saved)
        #expect(report == RemoteApplyReport(applied: 0, parked: 0, unchanged: 1))
        #expect(try first.sources().isEmpty && first.artEntries().isEmpty)
        #expect(try first.syncCandidates().deletions.map(\.name) == ["source-\(source.id)"])
    }

    @Test func takesARecordDeletedAndSavedAgainInOneBatchOverARowDeletedHere() throws {
        let gremlin = creature(named: "Gremlin")
        try first.save(gremlin)
        let saved = try first.sendEverything()
        try first.removeCustomCreature(id: gremlin.id)

        try first.applyRemote(saved.map { .deleted($0.id) } + saved)
        #expect(try first.customCreatures().map(\.id) == [gremlin.id])
        #expect(try first.syncCandidates().isEmpty)
    }

    @Test func takesAnEditFromElsewhereOverARowDeletedHere() throws {
        let gremlin = creature(named: "Gremlin")
        try first.save(gremlin)
        try devices.exchange()
        try first.removeCustomCreature(id: gremlin.id)
        try devices.secondLibrary.save(CustomCreatureRecord(id: gremlin.id, campaignID: nil, sharedVersion: nil,
                                                            record: Data("edited".utf8)))
        let edited = try devices.secondLibrary.sendEverything(fields: Data([2]))

        let report = try first.applyRemote(edited)
        #expect(report.applied == 1)
        #expect(try first.customCreatures().first?.record == Data("edited".utf8))
    }
}
