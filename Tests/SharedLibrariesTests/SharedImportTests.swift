import ArtExtraction
import ArtExtractionTestSupport
import CoreGraphics
import Foundation
@testable import SharedLibraries
import Testing

/// Reading PDFs into the shared art library (shared libraries R1.3, R2, R3.2).
@Suite struct SharedImportTests {
    let folder = temporaryFolder()
    let goblin = DrawnPawn(rect: CGRect(x: 20, y: 600, width: 81, height: 138), art: creatureArt(variant: 0),
                           name: "GOBLIN WARRIOR")
    let ogre = DrawnPawn(rect: CGRect(x: 120, y: 600, width: 81, height: 138), art: creatureArt(variant: 1),
                         name: "OGRE")

    func library(_ app: TablesideApp = .turnkeeper) throws -> SharedLibrary {
        try SharedLibrary(folder: folder.appending(path: "Tableside"), app: app)
    }

    func pawnBox(_ pawns: [DrawnPawn]? = nil) throws -> URL {
        try writePawnPDF(pawns ?? [goblin, ogre], named: "Pathfinder Test Pawn Box PDF.pdf", in: folder)
    }

    @Test func keepsAPDFAndSavesItsArtsPictures() throws {
        let library = try library()
        let pdf = try pawnBox()
        let report = try library.add(pdf, keeping: true)
        #expect(report.added == 2 && !report.wasImported)
        let entries = try library.artEntries()
        #expect(entries.map(\.name).sorted() == ["Goblin Warrior", "Ogre"])
        for entry in entries {
            #expect(entry.id == entry.prints[0].key && entry.picture == "\(entry.id.uuidString).heic")
            #expect(entry.prints[0].back != nil)
            let picture = try #require(library.picture(of: entry, maxPixels: 64))
            #expect(max(picture.width, picture.height) <= 64)
            #expect(![.none, .noneSkipFirst, .noneSkipLast].contains(picture.alphaInfo))
            #expect(library.isAvailable(entry))
        }
        let source = try #require(try library.sources().first)
        #expect(source.isKept && library.status(of: source) == .available)
        #expect(try library.add(pdf, keeping: true).wasImported)
    }

    @Test func letsASecondAppReachAPDFWithoutReadingItAgain() throws {
        let pdf = try pawnBox()
        try library(.turnkeeper).add(pdf, keeping: false)
        let fieldGuide = try library(.fieldGuide)
        let counter = try fieldGuide.changeCounter()

        #expect(try fieldGuide.add(pdf, keeping: false).wasImported)
        let changes = try fieldGuide.changes(since: counter)
        #expect(changes.changedTables == [.sources, .sourceAccess])
        let source = try #require(try fieldGuide.sources().first)
        #expect(Set(source.access.keys) == [.turnkeeper, .fieldGuide])
        #expect(fieldGuide.contains(pdf))
        #expect(try fieldGuide.add(pdf, keeping: false).wasImported)
    }

    @Test func skipsAPDFAnotherAppIsReading() throws {
        let pdf = try pawnBox()
        let prepared = try ArtLibrary.prepare(pdf)
        #expect(try library(.fieldGuide).claim(sourceID: prepared.digest))
        let report = try library(.turnkeeper).commit(prepared, location: .kept)
        #expect(report.isReadByAnotherApp && report.added == 0)
        #expect(try library().artEntries().isEmpty)
    }

    @Test func mergesACardsCreatureWithThePawnOfTheSamePainting() throws {
        let library = try library()
        let otherOgre = DrawnPawn(rect: ogre.rect, art: artImage(variant: 1), name: "OGRE")
        try library.add(try pawnBox([goblin, otherOgre]), keeping: true)
        let goblinID = try #require(try library.artEntries().first { $0.name == "Goblin Warrior" }?.id)
        let deck = [DrawnCard(name: "GOBLIN WARRIOR", traits: "N SMALL GOBLIN HUMANOID",
                              creature: creatureArt(variant: 0, scale: 4)),
                    DrawnCard(name: "OGRE", creature: creatureArt(variant: 2, scale: 4))]

        let report = try library.add(try writeCardDeck(deck, in: folder), keeping: true)
        #expect(report.alreadyKnown == 1 && report.added == 1)
        let goblin = try #require(try library.artEntries().first { $0.name == "Goblin Warrior" })
        #expect(goblin.id == goblinID && goblin.prints.map(\.print.kind) == [.figure, .pawn])
        #expect(goblin.traits.contains("goblin") && goblin.size == .medium)
        let figureKey = try #require(goblin.prints.first?.key)
        #expect(goblin.picture == "\(figureKey.uuidString).heic")
        #expect(try library.artEntries().filter { $0.name == "Ogre" }.count == 2)
    }

    @Test func mergesACardsCreatureWithAPawnNamingMoreOfItsFamily() throws {
        let library = try library()
        let devilImp = DrawnPawn(rect: goblin.rect, art: creatureArt(variant: 0), name: "DEVIL, IMP")
        let golemWood = DrawnPawn(rect: ogre.rect, art: creatureArt(variant: 2), name: "GOLEM, WOOD")
        try library.add(try pawnBox([devilImp, golemWood]), keeping: true)
        let deck = [DrawnCard(name: "IMP", creature: creatureArt(variant: 0, scale: 4)),
                    DrawnCard(name: "GIANT, WOOD", creature: creatureArt(variant: 2, scale: 4))]

        let report = try library.add(try writeCardDeck(deck, in: folder), keeping: true)
        #expect(report.alreadyKnown == 1 && report.added == 1)
        let imp = try #require(try library.artEntries().first { $0.name == "Devil, Imp" })
        #expect(imp.prints.map(\.print.kind) == [.figure, .pawn])
    }

    @Test func keepsEveryProductPrintingOnePictureUnderOneName() throws {
        let library = try library()
        var reprint = goblin
        reprint.rect.origin.x = 300
        try library.add(try pawnBox([goblin]), keeping: true)
        let other = try writePawnPDF([reprint, ogre], named: "Pathfinder Other Pawn Box PDF.pdf", in: folder)
        #expect(try library.add(other, keeping: true).alreadyKnown == 1)
        let entry = try #require(try library.artEntries().first { $0.name == "Goblin Warrior" })
        #expect(entry.prints.count == 2 && Set(entry.prints.map(\.key)).count == 1)
        #expect(Set(entry.prints.map(\.print.sourceID)).count == 2)
        try library.remove(sourceID: try #require(entry.prints.first?.print.sourceID))
        #expect(try library.artEntry(id: entry.id)?.prints.count == 1)
    }

    @Test func matchesNamesThatPrintMoreOrLessOfTheFamily() {
        #expect(CreatureName.matches("Elemental, Air, Invisible Stalker", "Elemental, Invisible Stalker"))
        #expect(CreatureName.matches("Invisible Stalker", "Elemental, Air, Invisible Stalker"))
        #expect(!CreatureName.matches("Giant, Wood", "Golem, Wood") && !CreatureName.matches("Ghoul", "Ghast"))
        #expect(CreatureName.familyKey("Elemental, Air, Invisible Stalker ") == "invisiblestalker")
    }

    @Test func keepsATokensPictureAsDrawnAtImport() throws {
        let library = try library()
        let url = folder.appending(path: "Starfinder Test Token Box.pdf")
        try tokenPDF(pages: [[DrawnToken(center: CGPoint(x: 100, y: 600), rimName: "VESK SOLDIER")]]).write(to: url)
        try library.add(url, keeping: false)
        let entry = try #require(try library.artEntries().first)
        #expect(entry.game == .starfinder && entry.picture == "\(entry.id.uuidString).png")
        try FileManager.default.removeItem(at: url)
        let source = try #require(try library.sources().first)
        #expect(library.status(of: source) == .missing)
        #expect(library.isAvailable(entry) && library.picture(of: entry) != nil)
    }

    @Test func drawsAMissingPictureFromItsPDF() throws {
        let library = try library()
        try library.add(try pawnBox(), keeping: true)
        var entry = try #require(try library.artEntries().first)
        try FileManager.default.removeItem(at: library.pictureFile(entry.picture ?? ""))
        entry.picture = nil
        #expect(library.picture(of: entry) != nil)
        let drawn = library.pictureFile("\(entry.prints[0].key.uuidString).heic")
        #expect(FileManager.default.fileExists(atPath: drawn.path))
    }

    @Test func keepsOldKeysWhenANewerReaderReadsAPDFAgain() throws {
        let library = try library()
        let pdf = try pawnBox()
        try library.add(pdf, keeping: true)
        let ogreEntry = try #require(try library.artEntries().first { $0.name == "Ogre" })
        let oldKey = UUID()
        try library.connection().run("UPDATE prints SET key = ? WHERE key = ?",
                                     [.text(oldKey.uuidString), .text(ogreEntry.id.uuidString)])
        try library.connection().run("UPDATE sources SET readerVersion = 0")
        try library.setCreatureArt(.library(ogreEntry.id), for: "ogre")

        let report = try library.add(pdf, keeping: true)
        #expect(!report.wasImported && report.alreadyKnown == 2)
        #expect(try library.artEntries().count == 2)
        #expect(try library.artEntry(id: oldKey)?.id == ogreEntry.id)
        #expect(try library.creatureArt() == ["ogre": .library(ogreEntry.id)])
        #expect(try library.sources().first?.readerVersion == PawnExtractor.version)
    }

    @Test func removesAPDFWithTheArtOnlyItPrints() throws {
        let library = try library()
        try library.add(try pawnBox(), keeping: true)
        let entries = try library.artEntries()
        try library.setCreatureArt(.library(entries[0].id), for: "goblin")
        let source = try #require(try library.sources().first)

        try library.remove(sourceID: source.id)
        #expect(try library.artEntries().isEmpty && library.sources().isEmpty && library.creatureArt().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: library.keptFile(sourceID: source.id).path))
        let pictures = entries.map { library.pictureFile($0.picture ?? "").path }
        #expect(pictures.allSatisfy { !FileManager.default.fileExists(atPath: $0) })
    }

    @Test func addsNewFilesFromAWatchedFolderByReference() throws {
        let downloads = folder.appending(path: "Scrollkeeper/Files/Pathfinder Test Pawn Box",
                                         directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
        let pdf = try writePawnPDF([goblin], named: "Pathfinder Test Pawn Box PDF.pdf", in: downloads)
        let library = try library()
        try library.add(pdf, keeping: false)
        let scrollkeeper = folder.appending(path: "Scrollkeeper/Files", directoryHint: .isDirectory)

        try library.watch(scrollkeeper)
        let source = try #require(try library.sources().first)
        guard case .inFolder(_, let path) = source.access[.turnkeeper] else {
            Issue.record("expected the PDF reached through the watched folder")
            return
        }
        #expect(path == "Pathfinder Test Pawn Box/Pathfinder Test Pawn Box PDF.pdf")
        _ = try writePawnPDF([ogre], named: "Pathfinder Other Pawn Box PDF.pdf", in: downloads)
        var names: [String] = []
        let results = library.addNewFiles { names.append($0) }
        #expect(results.count == 1 && names == ["Pathfinder Other Pawn Box PDF.pdf"])
        #expect(try library.artEntries().count == 2)
        #expect(try library.watchedFolders().map(\.path) == [scrollkeeper.path])
        #expect(try self.library(.fieldGuide).watchedFolders().isEmpty)

        try library.unwatch(path: scrollkeeper.path)
        #expect(try library.watchedFolders().isEmpty)
    }

    @Test func foldsTheNamesOfArtSavedBeforeVersionTwo() throws {
        let shared = folder.appending(path: "Tableside", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: shared, withIntermediateDirectories: true)
        do {
            let database = try SQLiteDatabase(path: shared.appending(path: SharedLibrary.fileName).path)
            try database.execute(LibrarySchema.versions[0] + "PRAGMA user_version = 1;")
            try database.run("INSERT INTO art (id, name, game, size, traits, fingerprint, palette, changed) "
                             + "VALUES ('a', 'Demon, Brimorak', 'pathfinder', 'medium', '', '', '', 1)")
        }
        let library = try library()
        let row = try library.connection().rows("SELECT foldedName, nameKey FROM art").first
        #expect(row?.text("foldedName") == "demonbrimorak" && row?.text("nameKey") == "brimorak")
    }
}
