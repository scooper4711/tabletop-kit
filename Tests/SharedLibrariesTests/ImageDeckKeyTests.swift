import ArtExtraction
import ArtExtractionTestSupport
import Foundation
@testable import SharedLibraries
import Testing

/// Items cut from an image deck keep one key on every device (pawn-shop#61): the back file's digest, without the
/// name read off the front. A library holding older keys merges them when the deck is read again.
@Suite struct ImageDeckKeyTests {
    let folder = temporaryFolder()
    let items = ["DAGGER", "LONGSWORD", "FULL PLATE", "WHIP", "SPEAR"]
    var deckFolder: URL {
        folder.appending(path: "Pathfinder Weapons & Armor Deck/Pathfinder Weapons & Armor Deck (Download)")
    }

    func library() throws -> SharedLibrary {
        try SharedLibrary(folder: folder.appending(path: "Tableside"), app: .pawnShop)
    }

    @Test func keysAnItemByItsBackFileAlone() throws {
        try writeImageDeck(items, in: deckFolder)
        let found = try PawnExtractor.extract(from: deckFolder).pawns
        var misread = found
        misread[0].name = "Dagqer"
        func keys(_ pawns: [ExtractedPawn]) -> [UUID] {
            ArtKey.keys(for: pawns.map { pawn in
                ArtKeyInput(sourceID: "deck", name: StoreMerger.keyName(of: pawn), size: pawn.size,
                            fingerprint: pawn.fingerprint, face: pawn.front)
            })
        }
        #expect(keys(found) == keys(misread))
        #expect(found.allSatisfy { StoreMerger.keyName(of: $0).isEmpty })
    }

    @Test func mergesTheKeysOfTwoDevicesWhenTheDeckIsReadAgain() throws {
        try writeImageDeck(items, in: deckFolder)
        let library = try library()
        try library.add(deckFolder, keeping: false)
        let database = try library.connection()
        let current = try library.artEntries().sorted { $0.name < $1.name }
        var older = OldKeys(database: database)
        for entry in current { try older.add(copiesOf: entry) }
        try older.renameDeviceCopy(0, to: "Dagqer")
        try older.unplaceDeviceCopy(1)
        try library.setNote(ArtNote(tags: ["blade"]), forArt: older.deviceEntries[0])
        try library.setCreatureArt(.library(older.deviceEntries[2]), for: "bandit")
        try database.run("UPDATE sources SET readerVersion = ?", [.integer(Int64(PawnExtractor.version))])

        let report = try library.add(deckFolder, keeping: false)

        let entries = try library.artEntries()
        #expect(!report.wasImported && entries.count == items.count)
        #expect(try library.sources().first?.readerVersion == PawnExtractor.imageDeckVersion)
        for oldID in older.allIDs { #expect(try library.artEntry(id: oldID) != nil) }
        let newIDs = Set(entries.map(\.id))
        #expect(try older.allIDs.allSatisfy { newIDs.contains(try #require(try library.artEntry(id: $0)).id) })
        let tagged = try #require(try library.artEntry(id: older.deviceEntries[0]))
        #expect(try library.notes()[tagged.id]?.tags == ["blade"] && tagged.name == "Dagger")
        let chosen = try #require(try library.artEntry(id: older.deviceEntries[2]))
        #expect(try library.creatureArt() == ["bandit": .library(chosen.id)])
    }
}

/// Puts a library's art back the way two devices had it before version 7: each print under an old key of its
/// own, and a second copy of each piece of art, as another device keyed it.
private struct OldKeys {
    let database: SQLiteDatabase
    var macKeys: [UUID] = []
    var macEntries: [UUID] = []
    var deviceKeys: [UUID] = []
    var deviceEntries: [UUID] = []

    var allIDs: [UUID] { macKeys + macEntries + deviceKeys + deviceEntries }

    /// Gives `entry`'s print an old key, then adds a copy of the art under another.
    mutating func add(copiesOf entry: SharedArtEntry) throws {
        let macKey = UUID(), deviceKey = UUID(), deviceEntry = UUID()
        try database.run("UPDATE prints SET key = ? WHERE key = ?",
                         [.text(macKey.uuidString), .text(entry.prints[0].key.uuidString)])
        try copy(.art, id: "id", from: entry.id.uuidString, to: deviceEntry.uuidString)
        try copy(.prints, id: "key", from: macKey.uuidString, to: deviceKey.uuidString)
        try database.run("UPDATE prints SET entry = ? WHERE key = ?",
                         [.text(deviceEntry.uuidString), .text(deviceKey.uuidString)])
        macKeys.append(macKey)
        macEntries.append(entry.id)
        deviceKeys.append(deviceKey)
        deviceEntries.append(deviceEntry)
    }

    /// Names the other device's copy of art `index` as its text recognition read it.
    func renameDeviceCopy(_ index: Int, to name: String) throws {
        try database.run("UPDATE art SET name = ?, foldedName = ? WHERE id = ?",
                         [.text(name), .text(ArtKey.foldedName(name)), .text(deviceEntries[index].uuidString)])
    }

    /// Takes the place off the other device's print of art `index` (page 0), as a card moved in from an app's
    /// own library has.
    func unplaceDeviceCopy(_ index: Int) throws {
        let key = deviceKeys[index].uuidString
        let row = try #require(try database.rows("SELECT front FROM prints WHERE key = ?", [.text(key)]).first)
        var face = try JSONDecoder().decode(PawnFace.self, from: try #require(row.blob("front")))
        face.pageIndex = 0
        let front = try JSONEncoder().encode(face)
        try database.run("UPDATE prints SET front = ? WHERE key = ?", [.blob(front), .text(key)])
    }

    /// Copies a row of `table` under a new ID.
    private func copy(_ table: LibraryTable, id column: String, from oldID: String, to newID: String) throws {
        let columns = try database.rows("PRAGMA table_info(\(table.rawValue))").compactMap { $0.text("name") }
        let others = columns.filter { $0 != column }.joined(separator: ", ")
        try database.run("INSERT INTO \(table.rawValue) (\(column), \(others)) SELECT ?, \(others) "
                         + "FROM \(table.rawValue) WHERE \(column) = ?", [.text(newID), .text(oldID)])
    }
}
