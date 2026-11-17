import Foundation
import notify
@testable import SharedLibraries
import ArtExtractionTestSupport
import Testing

/// The store: where it lives, change tracking, two apps at once (shared libraries R1, R5).
@Suite struct SharedLibraryTests {
    let folder = temporaryFolder().appending(path: "Tableside")

    @Test func createsItsFoldersAndKeepsWhatIsSaved() throws {
        let library = try SharedLibrary(folder: folder, app: .turnkeeper)
        for name in ["Library.sqlite", "Sources", "Pictures", "Custom"] {
            #expect(FileManager.default.fileExists(atPath: folder.appending(path: name).path))
        }
        try library.save(creature(named: "Gremlin"))

        let reopened = try SharedLibrary(folder: folder, app: .fieldGuide)
        #expect(try reopened.customCreatures().count == 1)
        let version = try reopened.connection().rows("PRAGMA user_version").first?.integer("user_version")
        #expect(version == Int64(LibrarySchema.versions.count))
    }

    @Test func fallsBackToTheAppsFolderOutsideTheGroup() throws {
        let library = try SharedLibrary.standard(app: .pawnShop, fallback: folder)
        #expect(library.folder == folder)
    }

    @Test func reportsWhatChangedSinceACounter() throws {
        let library = try SharedLibrary(folder: folder, app: .turnkeeper)
        let start = try library.changeCounter()
        let gremlin = creature(named: "Gremlin")
        try library.save(gremlin)
        var changes = try library.changes(since: start)
        #expect(changes.changedTables == [.customCreatures] && changes.deletions.isEmpty)
        #expect(try library.changes(since: changes.counter).isEmpty)

        try library.removeCustomCreature(id: gremlin.id)
        changes = try library.changes(since: changes.counter)
        #expect(changes.changedTables.isEmpty)
        #expect(changes.deletions == [.customCreatures: [gremlin.id.uuidString]])

        try library.save(gremlin)
        changes = try library.changes(since: start)
        #expect(changes.deletions.isEmpty && changes.changedTables == [.customCreatures])
    }

    @Test func opensAgainAfterClosing() throws {
        let library = try SharedLibrary(folder: folder, app: .turnkeeper)
        library.close()
        try library.save(creature(named: "Gremlin"))
        #expect(try library.customCreatures().count == 1)
    }

    @Test func tellsOtherAppsAfterEachChange() throws {
        var token: Int32 = 0
        notify_register_check(SharedLibraryChange.notificationName, &token)
        defer { notify_cancel(token) }
        var posted: Int32 = 0
        notify_check(token, &posted)
        let library = try SharedLibrary(folder: folder, app: .turnkeeper)
        try library.save(creature(named: "Gremlin"))
        let deadline = Date().addingTimeInterval(2)
        // notifyd delivers posts asynchronously.
        while posted == 0, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.01)
            notify_check(token, &posted)
        }
        #expect(posted == 1)
        _ = SharedLibraryChange.observe {}
    }

    @Test func losesNoChangeWhenTwoAppsWriteAtOnce() async throws {
        _ = try SharedLibrary(folder: folder, app: .turnkeeper)
        let folder = folder
        await withThrowingTaskGroup(of: Void.self) { group in
            for app in [TablesideApp.turnkeeper, .fieldGuide] {
                group.addTask {
                    let library = try SharedLibrary(folder: folder, app: app)
                    for index in 0..<40 { try library.save(creature(named: "\(app.rawValue) \(index)")) }
                }
            }
        }
        let library = try SharedLibrary(folder: folder, app: .pawnShop)
        #expect(try library.customCreatures().count == 80)
        #expect(try library.changeCounter() == 80)
    }

    @Test func letsOneAppReadAPDFAtATime() throws {
        let turnkeeper = try SharedLibrary(folder: folder, app: .turnkeeper)
        let fieldGuide = try SharedLibrary(folder: folder, app: .fieldGuide)
        let now = Date()
        #expect(try turnkeeper.claim(sourceID: "abc", now: now))
        #expect(try turnkeeper.claim(sourceID: "abc", now: now))
        #expect(try !fieldGuide.claim(sourceID: "abc", now: now))
        #expect(try fieldGuide.claim(sourceID: "abc", now: now.addingTimeInterval(SharedLibrary.claimDuration + 1)))

        try fieldGuide.releaseClaim(sourceID: "abc")
        #expect(try turnkeeper.claim(sourceID: "abc", now: now))
    }

    @Test func reportsAFailedStatementWithItsOperation() throws {
        let library = try SharedLibrary(folder: folder, app: .turnkeeper)
        #expect(throws: SharedLibraryError.self) { try library.connection().run("SELECT * FROM nowhere") }
        #expect(throws: SharedLibraryError.self) { try library.connection().execute("NOT SQL") }
        let error = SharedLibraryError(operation: "Opening", detail: "denied")
        #expect(error.description == "Opening failed: denied")
    }

    @Test func refusesAFolderItCannotOpen() throws {
        let file = temporaryFolder().appending(path: "file")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: file)
        #expect(throws: (any Error).self) { try SharedLibrary(folder: file, app: .turnkeeper) }
        #expect(throws: SharedLibraryError.self) { try SQLiteDatabase(path: file.appending(path: "x/y").path) }
    }
}

func creature(named name: String, campaign: UUID? = nil) -> CustomCreatureRecord {
    CustomCreatureRecord(id: UUID(), campaignID: campaign, sharedVersion: nil, record: Data(name.utf8))
}
