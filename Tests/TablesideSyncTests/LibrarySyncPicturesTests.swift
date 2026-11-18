import CloudKit
import Foundation
import SharedLibraries
import Testing
@testable import TablesideSync

/// When the pictures' upkeep runs, and what an app asks of the pictures (library sync design, "Pictures in iCloud").
@Suite struct LibrarySyncPicturesTests {
    let device = TestDevice()
    let store = FakePictureStore()
    let queue = RecordingQueue()

    /// Syncing with pictures, on an engine that records what it queues.
    func syncing() async throws -> (LibrarySync, SyncEngine) {
        let sync = try LibrarySync(folder: device.folder, app: .turnkeeper, changeDelay: .milliseconds(20),
                                   pictureStore: store)
        await sync.prepare()
        let engine = SyncEngine(handlers: [sync], store: sync)
        await sync.use(engine)
        await engine.use(queue)
        await engine.uploadEverything()
        return (sync, engine)
    }

    @Test func sendsNothingUntilThePicturesAreDrawnThenUploadsThem() async throws {
        let library = try device.library()
        try library.add(device.pawnBox(), keeping: false)
        let (sync, engine) = try await syncing()
        let source = try #require(try library.syncCandidates().saves.first)
        #expect(queue.added.isEmpty)
        #expect(await engine.record(for: LibraryRecordCoder.recordID(of: source)) == nil)

        await sync.drawPictures()
        #expect(queue.added == [.save(LibraryRecordCoder.recordID(of: source))])
        #expect(await store.uploads.first?.count == 2)
        #expect(await sync.status == .upToDate)
    }

    @Test func showsAFullICloudUntilARunOfPicturesGetsThrough() async throws {
        try device.library().add(device.pawnBox(), keeping: false)
        let (sync, _) = try await syncing()
        await store.fail(with: .quotaExceeded)
        await sync.drawPictures()
        #expect(await sync.status == .storageFull)

        await store.fail(with: .networkFailure)
        await sync.syncPictures()
        #expect(await sync.status == .storageFull)
        await store.fail(with: nil)
        await sync.syncPictures()
        #expect(await sync.status == .upToDate)
    }

    @Test func fetchesPicturesForAnAppAndKeepsItsCache() async throws {
        let (library, names) = try await device.thinLibrary(with: store)
        let (sync, _) = try await syncing()

        #expect(await sync.fetchPictures(named: names) == Set(names))
        #expect(try await sync.fetchedPicturesByteCount() > 0)
        await sync.markPicturesShown(names)
        try await sync.clearFetchedPictures()
        #expect(try await sync.fetchedPicturesByteCount() == 0)
        #expect(try library.missingPictureNames(limit: 100) == names)

        let plain = try LibrarySync(folder: device.folder, app: .fieldGuide)
        #expect(await plain.fetchPictures(named: names).isEmpty)
        await plain.drawPictures()
        await plain.syncPictures()
        #expect(await store.downloads.count == 1)
    }

    @Test func startsDownloadingEverythingWhenTheDeviceIsSetToKeepIt() async throws {
        let (library, _) = try await device.thinLibrary(with: store)
        let (sync, _) = try await syncing()
        await sync.drawPictures()
        #expect(try await sync.picturePolicy() == .onDemand(limit: nil))

        try await sync.setPicturePolicy(.everything)
        #expect(await eventually { await store.downloads.count == 1 })
        #expect(await eventually { await sync.status == .upToDate })
        #expect(try library.missingPictureNames(limit: 100).isEmpty)
        #expect(try await sync.picturePolicy() == .everything)
    }

    @Test func runsThePicturesAfterASendAndDeletesUnusedOnesOnceAFetchHasFinished() async throws {
        let library = try device.library()
        try library.add(device.pawnBox(), keeping: false)
        let (sync, engine) = try await syncing()
        await sync.drawPictures()
        let names = try #require(await store.uploads.first)
        try library.markPicturesDeleted(names)

        await engine.phaseChanged(.willSend)
        await engine.phaseChanged(.didSend)
        #expect(await eventually { await store.asked.count == 2 })
        #expect(await eventually { await sync.status == .upToDate })

        try library.remove(sourceID: try #require(try library.sources().first).id)
        await sync.syncPictures()
        #expect(await store.deletions.isEmpty)
        await engine.phaseChanged(.didFetch)
        #expect(await eventually { await store.deletions == [names] })
    }

    @Test func uploadsThePicturesAgainOnResumeAndClosesBothLibraries() async throws {
        try device.library().add(device.pawnBox(), keeping: false)
        let (sync, engine) = try await syncing()
        await sync.drawPictures()
        await engine.zonesDeleted([(LibraryRecordCoder.picturesZone, .purged)])
        try await store.delete(try #require(await store.uploads.first))
        await sync.syncPictures()
        #expect(await store.uploads.count == 1)

        await sync.close()
        await sync.resume()
        #expect(await eventually { await store.uploads.count == 2 })
        await sync.open()
    }
}
