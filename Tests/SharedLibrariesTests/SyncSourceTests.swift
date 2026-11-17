import ArtExtraction
import Foundation
@testable import SharedLibraries
import Testing

/// Merging in a PDF's reading from another device (library sync design, "Merging in a record").
@Suite struct SyncSourceTests {
    let devices: SyncedDevices

    init() throws {
        devices = try SyncedDevices()
    }

    var first: SharedLibrary { devices.firstLibrary }
    var second: SharedLibrary { devices.secondLibrary }

    /// The same PDF's file in both devices' folders.
    func sharedPawnBox() throws -> (first: URL, second: URL) {
        let file = try devices.first.pawnBox()
        let copy = devices.second.root.appending(path: file.lastPathComponent)
        try FileManager.default.copyItem(at: file, to: copy)
        return (file, copy)
    }

    @Test func givesAnEmptyDeviceTheArtItsPrintsAndASourceItCantReach() throws {
        try first.add(devices.first.pawnBox(), keeping: true)
        try first.write { writer in
            try writer.addAlias(UUID(), app: .pawnShop, entry: try #require(try first.artEntries().first).id)
        }
        try devices.exchange()

        let entries = try second.artEntries()
        #expect(entries.map(\.name).sorted() == ["Goblin Warrior", "Ogre"])
        #expect(try entries == first.artEntries())
        let source = try #require(try second.sources().first)
        #expect(source.title == (try first.sources().first?.title) && !source.isKept && source.access.isEmpty)
        #expect(second.status(of: source) == .missing)
        #expect(try second.connection().rows("SELECT * FROM aliases").count == 1)
    }

    @Test func leavesAlonePDFsBothDevicesReadAndUploadsNothing() throws {
        let files = try sharedPawnBox()
        try first.add(files.first, keeping: false)
        try second.add(files.second, keeping: false)
        let counters = (try first.changeCounter(), try second.changeCounter())
        try devices.exchange()

        #expect(try first.changeCounter() == counters.0 && second.changeCounter() == counters.1)
        #expect(try second.artEntries().count == 2)
    }

    @Test func joinsABattleCardToAPawnOnTheOtherDeviceAndMovesWhatPointsAtIt() throws {
        let pawn = SyncFixture.pawnKey, figure = SyncFixture.figureKey
        try first.write { writer in
            try SyncFixture.addSource("pawns", to: writer)
            try SyncFixture.addSource("cards", to: writer)
            try writer.merge(SyncFixture.entry([.init(.pawn, pawn, "pawns")]))
            try writer.merge(SyncFixture.entry([.init(.figure, figure, "cards")]))
        }
        try second.write { writer in
            try SyncFixture.addSource("pawns", to: writer)
            try SyncFixture.addSource("cards", to: writer)
            try writer.merge(SyncFixture.entry([.init(.figure, figure, "cards")]))
            try writer.upsert(ArtNote(tags: ["club"]), for: figure)
            try writer.upsert(.library(figure), for: "ogre")
        }
        try second.sendEverything()
        try first.write { writer in
            try writer.merge(SyncFixture.entry([.init(.pawn, pawn, "pawns"), .init(.figure, figure, "cards")]))
        }
        try devices.exchange()

        #expect(try second.artEntries().map(\.id) == [pawn] && first.artEntries().map(\.id) == [pawn])
        #expect(try second.notes() == [pawn: ArtNote(tags: ["club"])])
        #expect(try second.creatureArt() == ["ogre": .library(pawn)])
    }

    @Test func replacesAnOlderReadingAndKeepsItsKeysAsAliases() throws {
        let files = try sharedPawnBox()
        try first.add(files.first, keeping: false)
        try second.add(files.second, keeping: false)
        let ogre = try #require(try second.artEntries().first { $0.name == "Ogre" })
        let oldKey = UUID()
        try second.connection().run("UPDATE prints SET key = ? WHERE key = ?",
                                    [.text(oldKey.uuidString), .text(ogre.id.uuidString)])
        try second.connection().run("UPDATE sources SET readerVersion = 0")
        try second.setCreatureArt(.library(ogre.id), for: "ogre")

        try devices.exchange()
        #expect(try second.sources().first?.readerVersion == PawnExtractor.version)
        #expect(try second.artEntries().count == 2 && second.artEntry(id: oldKey)?.id == ogre.id)
        #expect(try second.creatureArt() == ["ogre": .library(ogre.id)])
        #expect(try first.sources().first?.readerVersion == PawnExtractor.version)
    }

    @Test func ignoresAnOlderReadersRecordAndSendsItsOwnOverIt() throws {
        let files = try sharedPawnBox()
        try first.add(files.first, keeping: false)
        let older = try SyncedDevices()
        try older.firstLibrary.add(files.first, keeping: false)
        try older.firstLibrary.connection().run("UPDATE sources SET readerVersion = 0")
        let sent = try older.firstLibrary.sendEverything()

        try first.applyRemote(sent)
        #expect(try first.sources().first?.readerVersion == PawnExtractor.version)
        let candidates = try first.syncCandidates()
        #expect(candidates.saves.map(\.kind) == [.source])
        #expect(try first.outgoingRecord(candidates.saves[0]) != nil)
    }

    @Test func removesAPDFsArtPicturesAndKeptCopyOnTheOtherDevice() throws {
        try first.add(devices.first.pawnBox(), keeping: true)
        try devices.exchange()
        let source = try #require(try second.sources().first)
        let entries = try second.artEntries()
        try Data([1]).write(to: second.keptFile(sourceID: source.id))
        for name in entries.compactMap(\.picture) { try Data([1]).write(to: second.pictureFile(name)) }
        try second.setNote(ArtNote(tags: ["club"]), forArt: entries[0].id)
        try devices.exchange()

        try first.remove(sourceID: source.id)
        try devices.exchange()
        #expect(try second.sources().isEmpty && second.artEntries().isEmpty && second.notes().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: second.keptFile(sourceID: source.id).path))
        for name in entries.compactMap(\.picture) {
            #expect(!FileManager.default.fileExists(atPath: second.pictureFile(name).path))
        }
    }

    @Test func changesNothingWhenASecondAppOnTheDeviceAppliesTheSameRecords() throws {
        try first.add(devices.first.pawnBox(), keeping: false)
        try first.setNote(ArtNote(tags: ["club"]), forArt: try #require(try first.artIDs().first))
        let sent = try first.sendEverything()
        let otherApp = try devices.second.library(.pawnShop)

        try second.applyRemote(sent)
        let counter = try otherApp.changeCounter()
        let report = try otherApp.applyRemote(sent)
        #expect(report == RemoteApplyReport(applied: 0, parked: 0, unchanged: sent.count))
        #expect(try otherApp.changeCounter() == counter)
    }

    @Test func rollsBackWhenARecordCantBeRead() throws {
        let bad = SyncRecord(id: SyncRecordID(kind: .source, name: "source-x"), payload: Data("{".utf8), title: "x")
        #expect(throws: SharedLibraryError.self) { try second.applyRemote([.saved(bad, systemFields: Data([1]))]) }
        #expect(try second.sources().isEmpty)
    }

    @Test func settlesOnOneAppForAnAliasBothDevicesHold() throws {
        try first.add(devices.first.pawnBox(), keeping: false)
        try devices.exchange()
        let art = try #require(try first.artIDs().first)
        let oldID = UUID()
        try first.write { writer in try writer.addAlias(oldID, app: .turnkeeper, entry: art) }
        try second.write { writer in try writer.addAlias(oldID, app: .pawnShop, entry: art) }

        try devices.exchange()
        #expect(try first.aliasApps() == second.aliasApps())
        #expect(try first.aliasApps()[oldID.uuidString] == "Pawn Shop")
    }

    @Test func settlesTheAliasOfArtWhoseIDANewerReadingReplaces() throws {
        let oldKey = SyncFixture.figureKey, newKey = SyncFixture.pawnKey
        try first.write { writer in
            try SyncFixture.addSource("pawns", to: writer, readerVersion: 5)
            try writer.merge(SyncFixture.entry([.init(.pawn, newKey, "pawns")]))
            try writer.addAlias(oldKey, app: .pawnShop, entry: newKey)
        }
        try second.write { writer in
            try SyncFixture.addSource("pawns", to: writer)
            try writer.merge(SyncFixture.entry([.init(.pawn, oldKey, "pawns")]))
            try writer.upsert(ArtNote(tags: ["club"]), for: oldKey)
        }

        try devices.exchange()
        #expect(try second.artEntries().map(\.id) == [newKey] && second.artEntry(id: oldKey)?.id == newKey)
        #expect(try second.notes() == [newKey: ArtNote(tags: ["club"])])
        #expect(try first.aliasApps() == second.aliasApps())
    }

    @Test func leavesOutAnAliasThatIsAlsoAPrintsKey() throws {
        let pawn = SyncFixture.pawnKey, figure = SyncFixture.figureKey
        try first.write { writer in
            try SyncFixture.addSource("pawns", to: writer)
            try writer.merge(SyncFixture.entry([.init(.pawn, pawn, "pawns")]))
            try writer.addAlias(figure, app: .pawnShop, entry: pawn)
            try SyncFixture.addSource("cards", to: writer)
            try writer.merge(SyncFixture.entry([.init(.pawn, pawn, "pawns"), .init(.figure, figure, "cards")]))
        }
        try devices.exchange()
        #expect(try second.aliasApps().isEmpty && second.artEntry(id: figure)?.id == pawn)
    }

    @Test func keepsThePicturesOfArtAnotherPDFStillPrintsInTheSameBatch() throws {
        try first.add(devices.first.pawnBox(), keeping: false)
        try devices.exchange()
        let names = try second.artEntries().compactMap(\.picture)
        for name in names { try Data([1]).write(to: second.pictureFile(name)) }
        let sourceID = try #require(try first.sources().first).id
        let id = SyncRecordID(kind: .source, name: "source-\(sourceID)")
        try first.forgetSystemFields(of: id)
        let outgoing = try #require(try first.outgoingRecord(id))
        var reading = try JSONDecoder().decode(SourceReading.self, from: outgoing.record.payload)
        reading.id = "redownloaded"
        let again = SyncRecord(id: SyncRecordID(kind: .source, name: "source-redownloaded"),
                               payload: try SyncPayloads.encode(reading), title: reading.title)

        try second.applyRemote([.saved(again, systemFields: Data([1])), .deleted(id)])
        #expect(try second.artEntries().count == 2 && second.sources().map(\.id) == ["redownloaded"])
        #expect(names.count == 2)
        #expect(names.allSatisfy { FileManager.default.fileExists(atPath: second.pictureFile($0).path) })
    }

    @Test func forgetsTheCachedPicturesOfARemovedPDF() throws {
        try first.add(devices.first.pawnBox(), keeping: false)
        try devices.exchange()
        for name in try second.artEntries().compactMap(\.picture) {
            let file = devices.second.root.appending(path: "download-\(name)")
            try Data(count: 100).write(to: file)
            try second.storeFetchedPicture(named: name, from: file)
        }
        #expect(try second.fetchedPicturesByteCount() == 200)

        try first.remove(sourceID: try #require(try first.sources().first).id)
        try devices.exchange()
        #expect(try second.fetchedPicturesByteCount() == 0)
    }
}
