import ArtExtraction
import ArtExtractionTestSupport
import CoreGraphics
import Foundation
import SharedLibraries
import Testing
@testable import CreatureArt

@Suite("The creature art store on the shared library")
struct SharedCreatureArtStoreTests {
    let folder = temporaryFolder()
    let goblin = DrawnPawn(rect: CGRect(x: 20, y: 600, width: 81, height: 138), art: creatureArt(variant: 0),
                           name: "GOBLIN WARRIOR")
    let ogre = DrawnPawn(rect: CGRect(x: 120, y: 600, width: 81, height: 138), art: creatureArt(variant: 1),
                         name: "OGRE")

    func shared(_ app: TablesideApp = .turnkeeper) throws -> SharedLibrary {
        try SharedLibrary(folder: folder.appending(path: "Tableside"), app: app)
    }

    func store(_ app: TablesideApp = .turnkeeper) throws -> CreatureArtStore {
        try CreatureArtStore(sharedLibraryIn: folder.appending(path: "Tableside"), app: app)
    }

    func downloads() throws -> (folder: URL, pdf: URL) {
        let product = folder.appending(path: "Files/Pathfinder Monster Core Pawn Box", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: product, withIntermediateDirectories: true)
        let pdf = try writePawnPDF([goblin, ogre], named: "Pathfinder Monster Core Pawn Box PDF.pdf", in: product)
        return (folder.appending(path: "Files"), pdf)
    }

    @Test("Importing a folder adds its PDFs by reference, for the catalog")
    func importsAFolder() async throws {
        let store = try store()
        let (files, _) = try downloads()
        let summary = await store.importFolder(files) { _ in }
        #expect(summary.pdfs == 1 && summary.added == 2 && summary.failures.isEmpty)
        let catalog = await store.catalog()
        #expect(catalog.art.map(\.name).sorted() == ["Goblin Warrior", "Ogre"])
        #expect(catalog.art.allSatisfy { $0.isRemastered && $0.isAvailable && $0.game == .pathfinder })
        #expect(catalog.sources.map(\.artCount) == [2])
        #expect(catalog.watchedFolders == [files.path])
        #expect(await store.addNewFiles().message == "No new PDFs of creature art.")
    }

    @Test("A deleted PDF is missing, but its art still shows from its pictures")
    func keepsArtOfMissingPDFs() async throws {
        let store = try store()
        let (files, pdf) = try downloads()
        _ = await store.importFolder(files) { _ in }
        try FileManager.default.removeItem(at: pdf)
        let catalog = await store.catalog()
        #expect(catalog.missingSources.map(\.title) == ["Pathfinder Monster Core Pawn Box"])
        #expect(catalog.art.allSatisfy { $0.isAvailable })
        let entry = try #require(catalog.art.first)
        #expect(await store.picture(id: entry.id, maxPixels: 64) != nil)
    }

    @Test("Another app's PDF is named by the app that reads it")
    func namesTheAppThatReadsAPDF() async throws {
        let (_, pdf) = try downloads()
        try shared(.fieldGuide).add(pdf, keeping: false)
        let catalog = await try store(.turnkeeper).catalog()
        #expect(catalog.sources.map(\.place) == ["Read by Field Guide"])
        #expect(catalog.sources.first?.isMissing == true && catalog.art.allSatisfy { $0.isAvailable })
    }

    @Test("Chosen PDFs are kept, drawn, and removed with their art")
    func addsAndRemovesFiles() async throws {
        let store = try store()
        let pdf = try writePawnPDF([goblin], named: "Starfinder Test Pawn Box PDF.pdf", in: folder)
        let summary = await store.addFiles([pdf, folder.appending(path: "Missing.pdf")]) { _ in }
        #expect(summary.pdfs == 1 && summary.failures.count == 1)
        let catalog = await store.catalog()
        #expect(catalog.sources.first?.place == "Kept in the app")
        let entry = try #require(catalog.art.first)
        #expect(await store.picture(id: entry.id, maxPixels: 64) != nil)
        #expect(await store.picture(id: UUID(), maxPixels: 64) == nil)
        try await store.removeSource(id: try #require(catalog.sources.first?.id))
        #expect(await store.catalog().art.isEmpty)
    }

    @Test("Art moved in is found by the ID the app gave it before")
    func findsArtByItsOldID() async throws {
        let old = try ArtLibrary(folder: folder.appending(path: "Turnkeeper/Creature Art"))
        try old.add(try downloads().pdf, keeping: true)
        let oldID = try #require(old.entries.first?.id)
        let store = try store()
        #expect(try await store.moveIn(LibraryMove(app: .turnkeeper, artFolder: old.folder))?.art == 2)
        await store.close()
        #expect(await store.picture(id: oldID, maxPixels: 64) != nil)
        #expect(await !store.catalog().art.map(\.id).contains(oldID))
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
