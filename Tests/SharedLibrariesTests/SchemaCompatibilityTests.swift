import ArtExtractionTestSupport
import Foundation
@testable import SharedLibraries
import Testing

/// An app opening a library a newer version of another app has changed (`LibrarySchema`).
@Suite struct SchemaCompatibilityTests {
    let folder = temporaryFolder().appending(path: "Tableside")

    /// A library at a version ahead of this app's, as a newer app leaves it.
    func newerLibrary(oldestWriter: Int) throws -> CustomCreatureRecord {
        let gremlin = creature(named: "Gremlin")
        let library = try SharedLibrary(folder: folder, app: .fieldGuide)
        try library.save(gremlin)
        let database = try library.connection()
        try database.execute("""
            ALTER TABLE customCreatures ADD COLUMN extra TEXT NOT NULL DEFAULT '';
            UPDATE customCreatures SET extra = 'kept';
            UPDATE compatibility SET oldestWriter = \(oldestWriter);
            PRAGMA user_version = 99;
            """)
        return gremlin
    }

    @Test func writesALibraryANewerAppAddedToAndKeepsWhatItAdded() throws {
        var gremlin = try newerLibrary(oldestWriter: 1)
        let library = try SharedLibrary(folder: folder, app: .turnkeeper)
        #expect(library.canWrite)

        gremlin.record = Data("Gremlin, edited".utf8)
        try library.save(gremlin)
        let database = try library.connection()
        #expect(try database.rows("SELECT extra FROM customCreatures").first?.text("extra") == "kept")
        #expect(try database.rows("PRAGMA user_version").first?.integer("user_version") == 99)
        #expect(try library.customCreatures() == [gremlin])
    }

    @Test func onlyReadsALibraryANewerAppChangedBeyondIt() throws {
        let gremlin = try newerLibrary(oldestWriter: 99)
        let library = try SharedLibrary(folder: folder, app: .turnkeeper)
        #expect(!library.canWrite)
        #expect(try library.customCreatures() == [gremlin])
        #expect(throws: SharedLibraryError.self) { try library.save(creature(named: "Kobold")) }
        #expect(throws: SharedLibraryError.self) { try library.claim(sourceID: "abc") }
    }
}
