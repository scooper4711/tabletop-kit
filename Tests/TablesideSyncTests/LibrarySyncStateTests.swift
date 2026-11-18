import CloudKit
import Foundation
import SharedLibraries
import Testing
@testable import TablesideSync

/// Pauses, accounts, failures and the status an app shows (library sync R2.5, R5).
@Suite struct LibrarySyncStateTests {
    let syncing: SyncingDevice

    init() async throws {
        syncing = try await SyncingDevice()
    }

    var device: TestDevice { syncing.device }
    var sync: LibrarySync { syncing.sync }
    var engine: SyncEngine { syncing.engine }
    var queue: RecordingQueue { syncing.queue }

    /// A device whose library is in step with the server.
    func syncedLibrary() async throws -> SharedLibrary {
        let library = try device.library()
        try device.fillWithEveryKind(library)
        await syncing.sendEverything()
        queue.clear()
        return library
    }

    @Test func pausesWhenTheUserDeletedTheICloudDataAndUploadsEverythingOnResume() async throws {
        let library = try await syncedLibrary()
        await engine.zonesDeleted([(LibraryRecordCoder.libraryZone, .purged)])

        #expect(await sync.status == .paused)
        #expect(try library.isSyncPaused)
        #expect(queue.zones.isEmpty && queue.added.isEmpty)
        try library.setSyncPaused(false)
        let unsent = try #require(try library.syncCandidates().saves.first)
        try library.setSyncPaused(true)
        #expect(await engine.record(for: LibraryRecordCoder.recordID(of: unsent)) == nil)

        await sync.resume()
        #expect(await sync.status == .upToDate)
        #expect(queue.zones.count == 2 && queue.added.count == SyncKind.allCases.count)
    }

    @Test func pausesWhenASaveFindsTheZoneDeletedByTheUser() async throws {
        _ = try await syncedLibrary()
        let record = CKRecord(recordType: "Note", recordID: .library("note-1"))
        await engine.sent(SentChanges(failedSaves: [(record, CKError(.userDeletedZone))]))
        #expect(await sync.status == .paused)
        #expect(queue.zones.isEmpty && queue.added.isEmpty)
    }

    @Test func showsAPauseThatIsStillOnWhenItStarts() async throws {
        try device.library().setSyncPaused(true)
        let later = try LibrarySync(folder: device.folder, app: .turnkeeper)
        await later.prepare()
        #expect(await later.status == .paused)
    }

    @Test func forgetsTheServerOnlyWhenAnotherAccountSignsIn() async throws {
        let library = try await syncedLibrary()
        let user = CKRecord.ID(recordName: "_user")
        await engine.accountChanged(.signIn(currentUser: user))
        #expect(queue.added.count == SyncKind.allCases.count)
        #expect(try library.syncAccount() == "_user")

        await syncing.sendEverything()
        queue.clear()
        await engine.accountChanged(.signOut(previousUser: user))
        #expect(await sync.status == .unavailable)
        await engine.accountChanged(.signIn(currentUser: user))
        #expect(await sync.status == .upToDate)
        #expect(queue.added.isEmpty)

        await engine.accountChanged(.switchAccounts(previousUser: user,
                                                    currentUser: CKRecord.ID(recordName: "_other")))
        #expect(queue.added.count == SyncKind.allCases.count)
    }

    @Test func stopsAndDropsTheEnginesStateWhenRecordsCannotBeMerged() async throws {
        let library = try await syncedLibrary()
        await engine.saveState(Data([1]))
        await engine.receive(FetchedChanges(modifications: [try device.unmergeableRecord()]))

        guard case .failed(let reason) = await sync.status else {
            Issue.record("syncing didn't stop")
            return
        }
        #expect(reason.contains("Saving"))
        #expect(try library.engineState() == nil)
        await engine.saveState(Data([2]))
        #expect(try library.engineState() == nil)
        _ = try library.setNote(ArtNote(tags: ["axe"]), forArt: try #require(try library.artEntries().first).id)
        #expect(await sync.pendingChanges().isEmpty)
        #expect(await engine.record(for: .library("note-1")) == nil)
        await engine.zonesDeleted([(LibraryRecordCoder.libraryZone, .purged)])
        #expect(await sync.status == .failed(reason))
    }

    @Test func tellsWhatSyncingIsDoingAndWhenICloudIsFull() async throws {
        let library = try await syncedLibrary()
        var updates = await sync.statusUpdates().makeAsyncIterator()
        #expect(await updates.next() == .upToDate)
        await engine.phaseChanged(.willFetch)
        await engine.phaseChanged(.willSend)
        #expect(await updates.next() == .syncing)
        await engine.phaseChanged(.didFetch)
        await engine.phaseChanged(.didSend)
        #expect(await updates.next() == .upToDate)

        _ = try library.setNote(ArtNote(tags: ["axe"]), forArt: try #require(try library.artEntries().first).id)
        let change = try #require(await sync.pendingChanges().first)
        let record = try #require(await engine.record(for: change.recordID))
        await engine.sent(SentChanges(failedSaves: [(record, CKError(.quotaExceeded))]))
        #expect(await updates.next() == .storageFull)
        #expect(queue.added.isEmpty)

        await sync.sendChanges()
        #expect(queue.added == [change])
        await engine.sent(SentChanges(saved: [record]))
        #expect(await updates.next() == .upToDate)
    }

    @Test func triesAFullICloudAgainOnResume() async throws {
        let library = try await syncedLibrary()
        _ = try library.setNote(ArtNote(tags: ["axe"]), forArt: try #require(try library.artEntries().first).id)
        let change = try #require(await sync.pendingChanges().first)
        let record = try #require(await engine.record(for: change.recordID))
        await engine.sent(SentChanges(failedSaves: [(record, CKError(.quotaExceeded))]))
        await engine.zonesDeleted([(LibraryRecordCoder.libraryZone, .purged)])
        #expect(queue.added.isEmpty)

        await sync.resume()
        #expect(queue.added.count == SyncKind.allCases.count)
    }

    @Test func tellsAnAppThatDoesNotSyncWhy() {
        #expect(SyncStatus.withoutSync(containerIdentifier: "") == .unsupported)
        #expect(SyncStatus.withoutSync(containerIdentifier: "iCloud.example") == .unavailable)
    }

    @Test func stopsTellingAFollowerThatWentAway() async {
        var tracker = SyncStatusTracker()
        _ = tracker.updates()
        var kept = tracker.updates().makeAsyncIterator()
        tracker.begin(.pictures)
        #expect(await kept.next() == .syncing)
        tracker.clear(.paused)
        tracker.end(.pictures)
        #expect(tracker.status == .upToDate)
    }

    @Test func keepsWorkingWithTheLibraryClosedInTheBackground() async throws {
        _ = try await syncedLibrary()
        await sync.close()
        #expect(await sync.pendingChanges().isEmpty)
        #expect(await sync.load() == nil)
        await sync.open()
        #expect(await sync.zones().count == 2)
    }
}
