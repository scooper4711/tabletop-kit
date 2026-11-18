import ArtExtraction
import Foundation
@testable import SharedLibraries
import Testing

/// The sizes of the pictures a device draws, and what it draws for a picture it lacks (library sync design,
/// "Pictures").
@Suite struct SyncPictureDrawingTests {
    let devices: SyncedDevices

    init() throws {
        devices = try SyncedDevices()
    }

    var first: SharedLibrary { devices.firstLibrary }
    var second: SharedLibrary { devices.secondLibrary }

    /// The first device's library with the pawn box read, and its pictures' names.
    func importedLibrary() throws -> (library: SharedLibrary, names: [String]) {
        try first.add(devices.first.pawnBox(), keeping: true)
        return (first, try first.artEntries().compactMap(\.picture).sorted())
    }

    // MARK: Sizes

    @Test func notesThePixelsOfThePicturesItDraws() throws {
        let (library, _) = try importedLibrary()
        let entries = try library.artEntries()
        #expect(entries.count == 2)
        for entry in entries {
            let name = try #require(entry.picture)
            #expect(entry.picturePixels > 0 && entry.picturePixels == library.pixels(ofPicture: name))
        }
        try devices.exchange()
        #expect(try second.artEntries().map(\.picturePixels) == entries.map(\.picturePixels))
    }

    @Test func measuresThePicturesSavedBeforeSizesWereKept() throws {
        let (library, names) = try importedLibrary()
        let sizes = try library.artEntries().map(\.picturePixels)
        try library.connection().run("UPDATE art SET picturePixels = 0")
        try FileManager.default.removeItem(at: library.pictureFile(names[0]))

        #expect(try library.measurePictures() == 1)
        #expect(try library.artEntries().map(\.picturePixels).sorted() == [0, sizes.max() ?? 0])
        #expect(try library.measurePictures() == 0)
        #expect(library.pixels(ofPicture: "nothing.heic") == 0)
    }

    // MARK: A picture that can't be drawn

    @Test func drawsTheOtherPicturesWhenOneCantBeSaved() throws {
        let device = devices.first
        let old = try ArtLibrary(folder: device.root.appending(path: "Pawn Shop/Creature Art"))
        try old.add(device.pawnBox(), keeping: true)
        let library = try device.library(.turnkeeper)
        try library.moveIn(LibraryMove(app: .turnkeeper, artFolder: old.folder))
        let blocked = try #require(try library.artEntries().min { $0.id.uuidString < $1.id.uuidString })
        let name = SharedLibrary.pictureName(drawnFrom: try #require(blocked.prints.first))
        // A folder where the picture's file would go, so the picture can't be saved.
        try FileManager.default.createDirectory(at: library.pictureFile(name).appending(path: "in the way"),
                                                withIntermediateDirectories: true)

        #expect(try library.drawMissingPictures(limit: 100) == 1)
        #expect(try library.artEntries().filter { $0.picture != nil }.count == 1)
        #expect(try library.artEntry(id: blocked.id)?.picture == nil)
        // With only that one left, nothing is drawn, and the caller is told why.
        #expect(throws: SharedLibraryError.self) { try library.drawMissingPictures(limit: 100) }
    }

    // MARK: A picture another print gave the art

    /// Names the first art's picture as another device would after drawing it from a print this one lacks.
    func nameAnotherPicture(in library: SharedLibrary) throws -> SharedArtEntry {
        let id = try #require(try library.artIDs().first)
        try library.connection().run("UPDATE art SET picture = 'elsewhere.heic', picturePixels = 1024 WHERE id = ?",
                                     [.text(id.uuidString)])
        return try #require(try library.artEntry(id: id))
    }

    @Test func standsInForAPictureAnotherPrintGaveTheArtWithoutSavingIt() throws {
        let (library, _) = try importedLibrary()
        let entry = try nameAnotherPicture(in: library)
        let counter = try library.changeCounter()

        #expect(library.picture(of: entry, maxPixels: 32) != nil)
        #expect(!FileManager.default.fileExists(atPath: library.pictureFile("elsewhere.heic").path))
        #expect(library.missingPictures(of: entry) == ["elsewhere.heic"])
        #expect(try library.artEntry(id: entry.id)?.picture == "elsewhere.heic")
        #expect(try library.changeCounter() == counter)
    }

    @Test func leavesAPictureAnotherPrintGaveTheArtToComeFromTheCloud() throws {
        let (library, _) = try importedLibrary()
        let entry = try nameAnotherPicture(in: library)

        #expect(try library.drawMissingPictures(limit: 10) == 0)
        #expect(!FileManager.default.fileExists(atPath: library.pictureFile("elsewhere.heic").path))
        #expect(try library.picturesToUpload(limit: 10).contains("elsewhere.heic") == false)
        #expect(try library.artEntry(id: entry.id)?.picture == "elsewhere.heic")
    }
}
