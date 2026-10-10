import ArtExtractionTestSupport
import Bestiary
import CoreGraphics
import Foundation
import Testing
@testable import CreatureArt

@Suite("The creature art store")
struct CreatureArtStoreTests {
    let folder = temporaryFolder()
    let goblin = DrawnPawn(rect: CGRect(x: 20, y: 600, width: 81, height: 138), art: creatureArt(variant: 0),
                           name: "GOBLIN WARRIOR")
    let ogre = DrawnPawn(rect: CGRect(x: 120, y: 600, width: 81, height: 138), art: creatureArt(variant: 1),
                         name: "OGRE")

    func store() throws -> CreatureArtStore { try CreatureArtStore(folder: folder.appendingPathComponent("Art")) }

    /// Scrollkeeper's folder with a Monster Core pawn box.
    func downloads() throws -> (folder: URL, pdf: URL) {
        let product = folder.appendingPathComponent("Files/Pathfinder Monster Core Pawn Box", isDirectory: true)
        try FileManager.default.createDirectory(at: product, withIntermediateDirectories: true)
        let pdf = try writePawnPDF([goblin, ogre], named: "Pathfinder Monster Core Pawn Box PDF.pdf", in: product)
        return (folder.appendingPathComponent("Files"), pdf)
    }

    @Test("Importing a folder adds its PDFs by reference, for the catalog")
    func importsAFolder() async throws {
        let store = try store()
        let (files, _) = try downloads()
        let summary = await store.importFolder(files) { _ in }
        #expect(summary.pdfs == 1 && summary.added == 2 && summary.failures.isEmpty)
        #expect(summary.message == "Read 1 PDF: 2 new pieces of creature art.")
        let catalog = await store.catalog()
        #expect(catalog.art.map(\.name).sorted() == ["Goblin Warrior", "Ogre"])
        #expect(catalog.art.allSatisfy { $0.isRemastered && $0.isAvailable && $0.game == .pathfinder })
        #expect(catalog.sources.map(\.title) == ["Pathfinder Monster Core Pawn Box"])
        #expect(catalog.watchedFolders == [files.path])
        #expect(await store.addNewFiles().message == "No new PDFs of creature art.")
    }

    @Test("A deleted PDF is missing, with its art")
    func reportsMissingPDFs() async throws {
        let store = try store()
        let (files, pdf) = try downloads()
        _ = await store.importFolder(files) { _ in }
        try FileManager.default.removeItem(at: pdf)
        let catalog = await store.catalog()
        #expect(catalog.missingSources.map(\.title) == ["Pathfinder Monster Core Pawn Box"])
        #expect(catalog.art.allSatisfy { !$0.isAvailable })
    }

    @Test("Chosen PDFs are kept, drawn, and removed with their art")
    func addsAndRemovesFiles() async throws {
        let store = try store()
        let pdf = try writePawnPDF([goblin], named: "Starfinder Test Pawn Box PDF.pdf", in: folder)
        let summary = await store.addFiles([pdf, folder.appendingPathComponent("Missing.pdf")]) { _ in }
        #expect(summary.pdfs == 1 && summary.failures.count == 1)
        let catalog = await store.catalog()
        #expect(catalog.sources.first?.place == "Kept in the app")
        let entry = try #require(catalog.art.first)
        #expect(entry.game == .starfinder && !entry.isRemastered)
        #expect(await store.picture(id: entry.id, maxPixels: 64) != nil)
        #expect(await store.picture(id: UUID(), maxPixels: 64) == nil)
        try await store.removeSource(id: try #require(catalog.sources.first?.id))
        #expect(await store.catalog().art.isEmpty)
    }

    @Test("A folder can stop being watched")
    func unwatches() async throws {
        let store = try store()
        let (files, _) = try downloads()
        _ = await store.importFolder(files) { _ in }
        try await store.unwatch(files.path)
        #expect(await store.catalog().watchedFolders.isEmpty)
    }
}
