import ArtExtraction
import ArtExtractionTestSupport
import Foundation
@testable import SharedLibraries
import Testing

/// Schema version 6 and the time of the user's last change (library sync design).
@Suite struct SyncSchemaTests {
    let folder = temporaryFolder().appending(path: "Tableside")
    let entry = UUID(uuidString: "00000000-0000-5000-8000-000000000001")!

    @Test func keepsTheRowsOfAVersionFiveLibraryAndGivesThemTimeZero() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        do {
            let database = try SQLiteDatabase(path: folder.appending(path: SharedLibrary.fileName).path)
            try database.execute(LibrarySchema.versions[0..<5].joined(separator: "\n") + "PRAGMA user_version = 5;")
            try database.run("INSERT INTO notes (entry, userName, tags, tagModel, suggestedName, corrected, changed) "
                             + "VALUES (?, 'Ogre Brute', '[]', '', '', 1, 3)", [.text(entry.uuidString)])
        }
        let library = try SharedLibrary(folder: folder, app: .pawnShop)

        #expect(try library.notes()[entry]?.userName == "Ogre Brute")
        #expect(try library.modifiedTime(ofNote: entry) == 0)
        #expect(try library.connection().rows("SELECT name FROM sqlite_master WHERE name = 'cloudRecords'").count == 1)
        #expect(library.canWrite)
    }

    @Test func stampsEachEditOfWhatTheUserMakes() throws {
        let library = try SharedLibrary(folder: folder, app: .turnkeeper)
        let before = Date()
        let gremlin = creature(named: "Gremlin")
        try library.save(gremlin)
        try library.setCreatureArt(.custom(UUID()), for: "bestiary.gremlin")
        try library.save(CustomArtRecord(id: UUID(), fileName: "a.png", sharedVersion: nil, record: Data()))
        try library.write { writer in try writer.upsert(ArtNote(tags: ["club"]), for: entry) }

        for (table, key) in [("customCreatures", "id"), ("creatureArt", "subject"), ("customArt", "id"),
                             ("notes", "entry")] {
            let rows = try library.connection().rows("SELECT modified FROM \(table)")
            #expect(rows.count == 1 && (rows[0].real("modified") ?? 0) >= before.timeIntervalSinceReferenceDate,
                    "\(table) by \(key)")
        }
    }

    @Test func writesTheTimeItIsGiven() throws {
        let library = try SharedLibrary(folder: folder, app: .turnkeeper)
        let long = Date(timeIntervalSinceReferenceDate: 1_000)
        try library.write { writer in try writer.upsert(ArtNote(tags: ["club"]), for: entry, modified: long) }
        #expect(try library.modifiedTime(ofNote: entry) == 1_000)
    }

    @Test func keepsANotesTimeWhenItMovesToOtherArt() throws {
        let library = try SharedLibrary(folder: folder, app: .turnkeeper)
        let other = UUID()
        let long = Date(timeIntervalSinceReferenceDate: 1_000)
        try library.write { writer in
            try writer.upsert(ArtNote(tags: ["club"]), for: entry, modified: long)
            try writer.moveNote(from: entry, to: other)
        }
        #expect(try library.modifiedTime(ofNote: other) == 1_000)
        #expect(try library.notes()[entry] == nil)
    }
}

extension SharedLibrary {
    /// A note's `modified`, for the tests.
    func modifiedTime(ofNote entry: UUID) throws -> Double? {
        try connection().rows("SELECT modified FROM notes WHERE entry = ?", [.text(entry.uuidString)]).first?
            .real("modified")
    }
}
