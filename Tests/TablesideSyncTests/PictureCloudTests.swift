import CloudKit
import Foundation
import SharedLibraries
import Testing
@testable import TablesideSync

/// The library's pictures in iCloud (library sync design, "Pictures in iCloud").
@Suite struct PictureCloudTests {
    let device = TestDevice()
    let store = FakePictureStore()

    func cloud() throws -> PictureCloud {
        try PictureCloud(folder: device.folder, app: .turnkeeper, store: store)
    }

    /// The device's library after it read the pawn box, with the names of the pictures it drew.
    func readLibrary() throws -> (SharedLibrary, [String]) {
        let library = try device.library()
        try library.add(device.pawnBox(), keeping: false)
        return (library, try library.picturesToUpload(limit: 100))
    }

    @Test func uploadsOnlyThePicturesICloudLacks() async throws {
        let (library, names) = try readLibrary()
        #expect(names.count == 2)
        await store.hold(Data([1]), as: names[0])

        #expect(try await cloud().run() == .finished)
        #expect(await store.uploads == [[names[1]]])
        #expect(await store.held[names[1]] == (try Data(contentsOf: library.pictureFile(names[1]))))
        #expect(try library.picturesToUpload(limit: 100).isEmpty)

        #expect(try await cloud().run() == .finished)
        #expect(await store.asked.count == 1)
    }

    @Test func downloadsAPictureWhenItIsShownAndKeepsItInTheCache() async throws {
        let (library, names) = try await device.thinLibrary(with: store)
        let art = try #require(try library.artEntries().first)
        let missing = library.missingPictures(of: art)
        #expect(missing.count == 1 && names.contains(missing[0]))
        let cloud = try cloud()

        #expect(await cloud.fetchPictures(named: missing + ["never-uploaded.heic"]) == Set(missing))
        #expect(library.missingPictures(of: art).isEmpty)
        #expect(try library.fetchedPicturesByteCount() > 0)
        #expect(try library.picturesToUpload(limit: 100).isEmpty)
        #expect(await cloud.fetchPictures(named: missing).isEmpty)
        #expect(await store.downloads.count == 1)

        try library.clearFetchedPictures()
        #expect(try library.fetchedPicturesByteCount() == 0)
        #expect(library.missingPictures(of: art) == missing)
    }

    @Test func stopsWhenICloudIsFullOrARequestFailsAndCarriesOnLater() async throws {
        let (library, names) = try readLibrary()
        let cloud = try cloud()
        await store.fail(with: .quotaExceeded)
        #expect(await cloud.run() == .storageFull)
        await store.fail(with: .networkFailure)
        #expect(await cloud.run() == .stopped)
        #expect(try library.picturesToUpload(limit: 100) == names)
        #expect(await cloud.fetchPictures(named: ["missing.heic"]).isEmpty)

        await store.fail(with: nil)
        #expect(await cloud.run() == .finished)
        #expect(try library.picturesToUpload(limit: 100).isEmpty)
    }

    @Test func deletesThePicturesNothingUsesOnlyAfterAFetchHasFinished() async throws {
        let (library, names) = try readLibrary()
        let cloud = try cloud()
        #expect(await cloud.run() == .finished)
        try library.remove(sourceID: try #require(try library.sources().first).id)
        #expect(try library.picturesToDelete() == names)

        #expect(await cloud.run() == .finished)
        #expect(await store.deletions.isEmpty)
        await cloud.fetchFinished()
        #expect(await cloud.run() == .finished)
        #expect(await store.deletions == [names])
        #expect(await store.held.isEmpty)
        #expect(try library.picturesToDelete().isEmpty)
    }

    @Test func downloadsEveryPictureAheadOnlyForADeviceThatKeepsEverything() async throws {
        let (library, names) = try await device.thinLibrary(with: store)
        let cloud = try cloud()
        #expect(await cloud.run() == .finished)
        #expect(await store.downloads.isEmpty)

        try await store.delete([names[0]])
        try library.setPicturePolicy(.everything)
        #expect(await cloud.run() == .finished)
        #expect(try library.missingPictureNames(limit: 100) == [names[0]])
        #expect(await store.downloads == [names])

        #expect(await cloud.run() == .finished)
        #expect(await store.downloads.count == 1)
    }

    @Test func drawsThePicturesArtLacksFromThePDFsItCanReach() async throws {
        let (library, names) = try readLibrary()
        for name in names { try FileManager.default.removeItem(at: library.pictureFile(name)) }
        #expect(try library.picturesToUpload(limit: 100).isEmpty)

        try await cloud().drawMissingPictures()
        #expect(try library.picturesToUpload(limit: 100) == names)
    }

    @Test func leavesThePicturesAloneWhileSyncingIsPaused() async throws {
        let (library, _) = try readLibrary()
        try library.setSyncPaused(true)
        #expect(try await cloud().run() == .finished)
        #expect(await store.asked.isEmpty)
    }

    @Test func letsARunUnderWayCarryOnForALaterCall() async throws {
        _ = try readLibrary()
        let cloud = try cloud()
        await store.keepWaiting(true)
        async let first = cloud.run()
        #expect(await eventually { await store.asked.count == 1 })

        #expect(await cloud.run() == nil)
        await store.keepWaiting(false)
        #expect(await first == .finished)
        #expect(await store.uploads.count == 1)
    }

    @Test func keepsWorkingWithTheLibraryClosedInTheBackground() async throws {
        let (library, _) = try readLibrary()
        let cloud = try cloud()
        await cloud.close()
        #expect(await cloud.run() == .finished)
        await cloud.open()
        #expect(try library.picturesToUpload(limit: 100).isEmpty)
    }
}
