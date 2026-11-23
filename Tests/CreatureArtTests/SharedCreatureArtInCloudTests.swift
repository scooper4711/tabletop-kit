import ArtExtraction
import ArtExtractionTestSupport
import CoreGraphics
import Foundation
@testable import SharedLibraries
import Testing
@testable import CreatureArt

/// Art on a device that can't reach its PDF, as on an iPad syncing a Mac's library (library sync R4.2).
@Suite("Creature art whose pictures are in iCloud")
struct SharedCreatureArtInCloudTests {
    let folder = temporaryFolder()
    let goblin = DrawnPawn(rect: CGRect(x: 20, y: 600, width: 81, height: 138), art: creatureArt(variant: 0),
                           name: "GOBLIN WARRIOR")

    private var libraryFolder: URL { folder.appending(path: "Tableside") }

    /// A library whose only PDF is gone from this device.
    private func libraryWithoutItsPDF() async throws -> (store: CreatureArtStore, library: SharedLibrary) {
        let store = try CreatureArtStore(sharedLibraryIn: libraryFolder, app: .turnkeeper)
        let files = folder.appending(path: "Files", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: files, withIntermediateDirectories: true)
        let pdf = try writePawnPDF([goblin], named: "Pathfinder Pawn Box PDF.pdf", in: files)
        _ = await store.importFolder(files) { _ in }
        try FileManager.default.removeItem(at: pdf)
        return (store, try SharedLibrary(folder: libraryFolder, app: .turnkeeper))
    }

    @Test("Art whose picture is only in iCloud can be shown, and its PDF needs no attention")
    func pictureInICloud() async throws {
        let (store, library) = try await libraryWithoutItsPDF()
        for entry in try library.artEntries() {
            try FileManager.default.removeItem(at: library.pictureFile(try #require(entry.picture)))
        }

        let catalog = await store.catalog()

        #expect(catalog.art.allSatisfy { $0.isAvailable })
        #expect(catalog.missingSources.count == 1)
        #expect(catalog.sourcesWithLostArt.isEmpty)
    }

    @Test("Art with neither a picture nor a PDF is lost, and its PDF needs attention")
    func noPictureAnywhere() async throws {
        let (store, library) = try await libraryWithoutItsPDF()
        try library.connection().run("UPDATE art SET picture = NULL")

        let catalog = await store.catalog()

        #expect(catalog.art.allSatisfy { !$0.isAvailable })
        #expect(catalog.sourcesWithLostArt.map(\.title) == catalog.missingSources.map(\.title))
        #expect(catalog.sourcesWithLostArt.count == 1)
    }
}
