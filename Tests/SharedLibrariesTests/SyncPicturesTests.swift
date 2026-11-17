import ArtExtraction
import Foundation
@testable import SharedLibraries
import Testing

/// What a device does about its pictures (library sync design, "Pictures").
@Suite struct SyncPicturesTests {
    let device = SyncDevice()

    func importedLibrary() throws -> (library: SharedLibrary, names: [String]) {
        let library = try device.library()
        try library.add(device.pawnBox(), keeping: true)
        return (library, try library.artEntries().compactMap(\.picture).sorted())
    }

    /// A downloaded picture of `bytes` bytes, as the cloud would hand it over.
    func download(_ bytes: Int, as name: String) throws -> URL {
        let file = device.root.appending(path: "download-\(name)")
        try Data(count: bytes).write(to: file)
        return file
    }

    func backdate(_ library: SharedLibrary, _ name: String, seconds: Double) throws {
        let shown = Date().addingTimeInterval(-seconds).timeIntervalSinceReferenceDate
        try library.connection().run("UPDATE fetchedPictures SET shown = ? WHERE name = ?",
                                     [.real(shown), .text(name)])
    }

    func exists(_ library: SharedLibrary, _ name: String) -> Bool {
        FileManager.default.fileExists(atPath: library.pictureFile(name).path)
    }

    // MARK: Uploading and deleting

    @Test func offersEachPictureOnceUntilItIsMarkedUploaded() throws {
        let (library, names) = try importedLibrary()
        #expect(names.count == 2)
        #expect(try library.picturesToUpload(limit: 10) == names)
        #expect(try library.picturesToUpload(limit: 1) == [names[0]])

        try library.markPicturesUploaded([names[0]])
        #expect(try library.picturesToUpload(limit: 10) == [names[1]])
        try FileManager.default.removeItem(at: library.pictureFile(names[1]))
        #expect(try library.picturesToUpload(limit: 10).isEmpty)
    }

    @Test func offersAPictureForDeletionOnceNothingNamesIt() throws {
        let (library, names) = try importedLibrary()
        try library.markPicturesUploaded(names)
        #expect(try library.picturesToDelete().isEmpty)

        try library.remove(sourceID: try #require(try library.sources().first).id)
        #expect(try library.picturesToDelete() == names)
        try library.markPicturesDeleted(names)
        #expect(try library.picturesToDelete().isEmpty && library.picturesToUpload(limit: 10).isEmpty)
    }

    @Test func offersEveryPictureAgainAfterForgettingTheServer() throws {
        let (library, names) = try importedLibrary()
        try library.markPicturesUploaded(names)
        try library.forgetServer()
        #expect(try library.picturesToUpload(limit: 10) == names)
    }

    // MARK: Downloading

    @Test func namesThePicturesAnArtLacksHere() throws {
        let (library, names) = try importedLibrary()
        let entry = try #require(try library.artEntries().first { $0.picture == names[0] })
        #expect(library.missingPictures(of: entry).isEmpty)
        try FileManager.default.removeItem(at: library.pictureFile(names[0]))
        #expect(library.missingPictures(of: entry) == [names[0]])
        #expect(try library.missingPictureNames(limit: 10) == [names[0]])
        #expect(try library.missingPictureNames(limit: 0).isEmpty)
    }

    @Test func storesADownloadedPictureInTheCacheWithoutUploadingItBack() throws {
        let (library, names) = try importedLibrary()
        try FileManager.default.removeItem(at: library.pictureFile(names[0]))
        let file = try download(300, as: names[0])

        try library.storeFetchedPicture(named: names[0], from: file)
        #expect(exists(library, names[0]) && !FileManager.default.fileExists(atPath: file.path))
        #expect(try library.fetchedPicturesByteCount() == 300)
        #expect(try library.picturesToUpload(limit: 10) == [names[1]])
    }

    @Test func keepsAPictureTheDeviceHasWhenTheSameOneDownloads() throws {
        let (library, names) = try importedLibrary()
        let file = try download(300, as: names[0])
        try library.storeFetchedPicture(named: names[0], from: file)
        #expect(try library.fetchedPicturesByteCount() == 0 && !FileManager.default.fileExists(atPath: file.path))
        #expect(try library.picturesToUpload(limit: 10) == [names[1]])
    }

    @Test func clearsTheCacheButKeepsWhatIsDrawnHere() throws {
        let (library, names) = try importedLibrary()
        try FileManager.default.removeItem(at: library.pictureFile(names[0]))
        try library.storeFetchedPicture(named: names[0], from: try download(300, as: names[0]))

        try library.clearFetchedPictures()
        #expect(try library.fetchedPicturesByteCount() == 0 && !exists(library, names[0]))
        #expect(exists(library, names[1]))
        #expect(try library.picturesToUpload(limit: 10) == [names[1]])
    }

    // MARK: The cache limit

    @Test func removesTheLeastRecentlyShownWhenStoringPastTheLimit() throws {
        let library = try device.library()
        try library.setPicturePolicy(.onDemand(limit: 250))
        for name in ["a", "b"] { try library.storeFetchedPicture(named: name, from: try download(100, as: name)) }
        try backdate(library, "a", seconds: 9_000)
        try backdate(library, "b", seconds: 8_000)

        try library.storeFetchedPicture(named: "c", from: try download(100, as: "c"))
        #expect(!exists(library, "a") && exists(library, "b") && exists(library, "c"))
        #expect(try library.fetchedPicturesByteCount() == 200)
    }

    @Test func sparesPicturesShownInTheLastHour() throws {
        let library = try device.library()
        try library.setPicturePolicy(.onDemand(limit: 100))
        for name in ["a", "b", "c"] { try library.storeFetchedPicture(named: name, from: try download(100, as: name)) }
        #expect(["a", "b", "c"].allSatisfy { exists(library, $0) })
        #expect(try library.fetchedPicturesByteCount() == 300)
    }

    @Test func keepsEverythingWithoutALimit() throws {
        let library = try device.library()
        #expect(try library.picturePolicy() == .onDemand(limit: nil))
        for name in ["a", "b", "c"] {
            try library.storeFetchedPicture(named: name, from: try download(100, as: name))
            try backdate(library, name, seconds: 9_000)
        }
        try library.setPicturePolicy(.onDemand(limit: nil))
        #expect(try library.fetchedPicturesByteCount() == 300)
    }

    @Test func removesAtOnceWhenTheLimitIsLowered() throws {
        let library = try device.library()
        for name in ["a", "b", "c"] {
            try library.storeFetchedPicture(named: name, from: try download(100, as: name))
        }
        try backdate(library, "a", seconds: 9_000)
        try backdate(library, "b", seconds: 8_000)
        try backdate(library, "c", seconds: 7_000)

        try library.setPicturePolicy(.onDemand(limit: 150))
        #expect(!exists(library, "a") && !exists(library, "b") && exists(library, "c"))
    }

    @Test func namesAnEvictedPictureAgainAndDoesNotUploadItBack() throws {
        let (library, names) = try importedLibrary()
        let entry = try #require(try library.artEntries().first { $0.picture == names[0] })
        try FileManager.default.removeItem(at: library.pictureFile(names[0]))
        try library.storeFetchedPicture(named: names[0], from: try download(100, as: names[0]))
        try backdate(library, names[0], seconds: 9_000)

        try library.setPicturePolicy(.onDemand(limit: 0))
        #expect(library.missingPictures(of: entry) == [names[0]])
        #expect(try library.picturesToUpload(limit: 10) == [names[1]])
    }

    @Test func evictsNothingWhenKeepingEverythingAndListsWhatIsStillToDownload() throws {
        let (library, names) = try importedLibrary()
        try library.setPicturePolicy(.everything)
        try FileManager.default.removeItem(at: library.pictureFile(names[0]))
        try library.storeFetchedPicture(named: "a", from: try download(100, as: "a"))
        try backdate(library, "a", seconds: 9_000)
        try library.setPicturePolicy(.everything)

        #expect(exists(library, "a"))
        #expect(try library.picturePolicy() == .everything)
        #expect(try library.missingPictureNames(limit: 10) == [names[0]])
    }

    @Test func keepsThePolicyWhenTheLibraryOpensAgain() throws {
        try device.library().setPicturePolicy(.onDemand(limit: 5_000))
        #expect(try device.library(.turnkeeper).picturePolicy() == .onDemand(limit: 5_000))
    }

    @Test func updatesWhenAPictureWasShownOnlyAfterADay() throws {
        let library = try device.library()
        try library.storeFetchedPicture(named: "a", from: try download(100, as: "a"))
        func shown() throws -> Double? {
            try library.connection().rows("SELECT shown FROM fetchedPictures WHERE name = 'a'").first?.real("shown")
        }
        try backdate(library, "a", seconds: 100)
        let recent = try #require(try shown())
        try library.markPicturesShown(["a"])
        #expect(try shown() == recent)

        try backdate(library, "a", seconds: 200_000)
        try library.markPicturesShown(["a"])
        #expect(try #require(try shown()) > recent)
    }

    @Test func notesAPictureShownThroughTheArtsPicture() throws {
        let (library, names) = try importedLibrary()
        let entry = try #require(try library.artEntries().first { $0.picture == names[0] })
        let image = try Data(contentsOf: library.pictureFile(names[0]))
        try FileManager.default.removeItem(at: library.pictureFile(names[0]))
        let file = device.root.appending(path: "download-image")
        try image.write(to: file)
        try library.storeFetchedPicture(named: names[0], from: file)
        try backdate(library, names[0], seconds: 200_000)
        let before = try library.connection().rows("SELECT shown FROM fetchedPictures").first?.real("shown")

        _ = library.picture(of: entry, maxPixels: 32)
        let after = try library.connection().rows("SELECT shown FROM fetchedPictures").first?.real("shown")
        #expect(try #require(after) > (try #require(before)))
    }

    // MARK: Old files

    @Test func removesFilesNothingNamesExceptRecentOnes() throws {
        let (library, names) = try importedLibrary()
        let old = library.pictureFile("old.heic"), recent = library.pictureFile("recent.heic")
        try Data([1]).write(to: old)
        try Data([1]).write(to: recent)
        let twoHoursAgo = Date().addingTimeInterval(-7_200)
        try FileManager.default.setAttributes([.modificationDate: twoHoursAgo], ofItemAtPath: old.path)
        for name in names {
            try FileManager.default.setAttributes([.modificationDate: twoHoursAgo],
                                                  ofItemAtPath: library.pictureFile(name).path)
        }

        #expect(try library.removeUnreferencedPictures() == 1)
        #expect(!FileManager.default.fileExists(atPath: old.path))
        #expect(FileManager.default.fileExists(atPath: recent.path))
        #expect(names.allSatisfy { exists(library, $0) })
    }

    // MARK: Drawing

    @Test func drawsThePicturesOfALibraryMovedInWithoutAnyAndThenNone() throws {
        let old = try ArtLibrary(folder: device.root.appending(path: "Pawn Shop/Creature Art"))
        try old.add(device.pawnBox(), keeping: true)
        let library = try device.library(.turnkeeper)
        try library.moveIn(LibraryMove(app: .turnkeeper, artFolder: old.folder))
        #expect(try library.artEntries().allSatisfy { $0.picture == nil })

        #expect(try library.drawMissingPictures(limit: 1) == 1)
        #expect(try library.drawMissingPictures(limit: 100) == 1)
        let entries = try library.artEntries()
        #expect(entries.allSatisfy { $0.picture.map { exists(library, $0) } == true })
        #expect(try library.drawMissingPictures(limit: 100) == 0)
        #expect(try library.drawMissingPictures(limit: 0) == 0)
    }

    @Test func drawsAMissingPictureUnderTheNameTheArtAlreadyHas() throws {
        let (library, names) = try importedLibrary()
        let counter = try library.changeCounter()
        try FileManager.default.removeItem(at: library.pictureFile(names[0]))

        #expect(try library.drawMissingPictures(limit: 10) == 1)
        #expect(exists(library, names[0]))
        #expect(try library.artEntries().compactMap(\.picture).sorted() == names)
        #expect(try library.changeCounter() == counter)
    }

    @Test func redrawsAShownPictureUnderItsNameWhenItsFileIsGone() throws {
        let (library, names) = try importedLibrary()
        let entry = try #require(try library.artEntries().first { $0.picture == names[0] })
        try FileManager.default.removeItem(at: library.pictureFile(names[0]))

        #expect(library.picture(of: entry, maxPixels: 32) != nil)
        #expect(exists(library, names[0]))
        #expect(try library.artEntry(id: entry.id)?.picture == names[0])
    }

    @Test func drawsNothingForArtNoPDFReaches() throws {
        let library = try device.library()
        try library.write { writer in
            try SyncFixture.addSource("pawns", to: writer)
            try writer.merge(SyncFixture.entry([.init(.pawn, SyncFixture.pawnKey, "pawns")]))
        }
        #expect(try library.drawMissingPictures(limit: 10) == 0)
    }
}
