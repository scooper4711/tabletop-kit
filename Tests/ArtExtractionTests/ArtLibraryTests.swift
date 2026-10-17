import CoreGraphics
import Foundation
import Testing
@testable import ArtExtraction
import ArtExtractionTestSupport

/// The art library (R2).
@Suite struct ArtLibraryTests {
    let folder = temporaryFolder()
    let goblin = DrawnPawn(rect: CGRect(x: 20, y: 600, width: 81, height: 138), art: creatureArt(variant: 0),
                           name: "GOBLIN WARRIOR")
    let ogre = DrawnPawn(rect: CGRect(x: 120, y: 600, width: 81, height: 138), art: creatureArt(variant: 1),
                         name: "OGRE")

    func library() throws -> ArtLibrary { try ArtLibrary(folder: folder.appendingPathComponent("Library")) }

    func writePawns(_ pawns: [DrawnPawn], named name: String = "Pathfinder Test Pawn Box PDF.pdf") throws -> URL {
        try writePawnPDF(pawns, named: name, in: folder)
    }

    @Test func keepsAPDFAndDrawsItsArt() throws {
        let library = try library()
        let report = try library.add(try writePawns([goblin, ogre]), keeping: true)
        #expect(report.added == 2)
        #expect(library.entries.map(\.name).sorted() == ["Goblin Warrior", "Ogre"])
        let source = try #require(library.sources.first)
        #expect(source.location == .kept && source.game == .pathfinder)
        #expect(FileManager.default.fileExists(atPath: library.keptFile(id: source.id).path))
        let picture = try #require(library.picture(of: library.entries[0], maxPixels: 200))
        #expect(max(picture.width, picture.height) == 200)
    }

    @Test func referencesAPDFAndReportsItMissingWhenDeleted() throws {
        let library = try library()
        let file = try writePawns([goblin])
        try library.add(file, keeping: false)
        let source = try #require(library.sources.first)
        guard case .referenced = source.location else { Issue.record("expected a reference"); return }
        #expect(!FileManager.default.fileExists(atPath: library.keptFile(id: source.id).path))
        #expect(library.status(of: source) == .available)

        try FileManager.default.removeItem(at: file)
        library.refreshStatuses()
        #expect(library.missingSources == [source])
        #expect(library.entries(from: source).map(\.name) == ["Goblin Warrior"])
        #expect(!library.isAvailable(library.entries[0]))
        #expect(library.picture(of: library.entries[0]) == nil)

        _ = try writePawns([goblin])
        library.refreshStatuses()
        #expect(library.missingSources.isEmpty)
        #expect(library.picture(of: library.entries[0]) != nil)
    }

    @Test func addingAPDFAgainChangesNothing() throws {
        let library = try library()
        let file = try writePawns([goblin])
        try library.add(file, keeping: true)
        #expect(library.contains(file))
        #expect(try library.add(file, keeping: true).wasImported)
        #expect(library.entries.count == 1 && library.sources.count == 1)
    }

    @Test func readsAPDFAgainWithANewerReader() throws {
        let library = try library()
        let file = try writePawns([goblin, ogre])
        try library.add(file, keeping: true)
        library.sources[0].readerVersion = PawnExtractor.version - 1
        let report = try library.add(file, keeping: true)
        #expect(!report.wasImported && report.added == 2)
        #expect(library.entries.count == 2 && library.sources.map(\.readerVersion) == [PawnExtractor.version])
    }

    @Test func mergesACardsCreatureWithThePawnOfTheSamePainting() throws {
        let library = try library()
        // The ogre pawn shows a different painting from the ogre card.
        let otherOgre = DrawnPawn(rect: ogre.rect, art: artImage(variant: 1), name: "OGRE")
        try library.add(try writePawns([goblin, otherOgre]), keeping: true)
        let deck = [DrawnCard(name: "GOBLIN WARRIOR", traits: "N SMALL GOBLIN HUMANOID",
                              creature: creatureArt(variant: 0, scale: 4)),
                    DrawnCard(name: "OGRE", creature: creatureArt(variant: 2, scale: 4))]
        let report = try library.add(try writeCardDeck(deck, in: folder), keeping: true)
        #expect(report.alreadyKnown == 1 && report.added == 1)
        let goblinEntry = try #require(library.entries.first { $0.name == "Goblin Warrior" })
        #expect(goblinEntry.prints.map(\.kind) == [.figure, .pawn])
        #expect(goblinEntry.traits.contains("goblin"))
        #expect(goblinEntry.size == .medium)
        #expect(library.entries.filter { $0.name == "Ogre" }.count == 2)
    }

    @Test func keepsATokensArtWhenItsPDFGoesMissing() throws {
        let library = try library()
        let url = folder.appendingPathComponent("Starfinder Test Token Box.pdf")
        try tokenPDF(pages: [[DrawnToken(center: CGPoint(x: 100, y: 600), rimName: "VESK SOLDIER")]]).write(to: url)
        try library.add(url, keeping: false)
        let entry = try #require(library.entries.first)
        #expect(entry.game == .starfinder && entry.prints.first?.kind == .token)
        try FileManager.default.removeItem(at: url)
        library.refreshStatuses()
        #expect(library.isAvailable(entry))
        #expect(library.picture(of: entry) != nil)
    }

    @Test func addsNewFilesFromAWatchedFolderByReference() throws {
        let downloads = folder.appendingPathComponent("Scrollkeeper/Files/Pathfinder Test Pawn Box", isDirectory: true)
        try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
        let pawns = try writePawnPDF([goblin], named: "Pathfinder Test Pawn Box PDF.pdf", in: downloads)
        try makePDF(pages: [{ _ in }]).write(to: downloads.appendingPathComponent("Core Rulebook.pdf"))
        let library = try library()
        try library.watch(folder.appendingPathComponent("Scrollkeeper/Files"))
        var read: [String] = []
        let results = library.addNewFiles { read.append($0) }
        #expect(read == ["Pathfinder Test Pawn Box PDF.pdf"])
        #expect(results.count == 1)
        let source = try #require(library.sources.first)
        #expect(source.location == .inFolder(library.watchedFolders[0],
                                             relativePath: "Pathfinder Test Pawn Box/Pathfinder Test Pawn Box PDF.pdf"))
        #expect(library.addNewFiles().isEmpty)

        try FileManager.default.removeItem(at: pawns)
        library.refreshStatuses()
        #expect(library.missingSources == [source])
    }

    @Test func watchingAFolderAgainRestoresAccessToItsPDFs() throws {
        let downloads = folder.appendingPathComponent("Scrollkeeper/Files", isDirectory: true)
        try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
        try writePawnPDF([goblin], named: "Pathfinder Test Pawn Box PDF.pdf", in: downloads)
        let library = try library()
        try library.watch(downloads)
        library.addNewFiles()
        // A bookmark that no longer grants access, like one made before the app was sandboxed.
        let stale = FileReference(bookmark: Data("stale".utf8), path: library.watchedFolders[0].path)
        library.sources[0].location = .inFolder(stale, relativePath: "Pathfinder Test Pawn Box PDF.pdf")
        library.refreshStatuses()
        #expect(library.missingSources.count == 1)

        try library.watch(downloads)
        #expect(library.sources[0].location == .inFolder(library.watchedFolders[0],
                                                         relativePath: "Pathfinder Test Pawn Box PDF.pdf"))
        #expect(library.missingSources.isEmpty)
    }

    @Test func watchingAFolderTakesInPDFsAddedFromIt() throws {
        let library = try library()
        let pawns = try writePawns([goblin])
        try library.add(pawns, keeping: false)
        try library.watch(folder)
        let relinked = SourceLocation.inFolder(library.watchedFolders[0], relativePath: pawns.lastPathComponent)
        #expect(library.sources[0].location == relinked)
        #expect(library.missingSources.isEmpty)
    }

    @Test func removesAPDFWithTheArtOnlyItPrints() throws {
        let library = try library()
        try library.add(try writePawns([goblin, ogre]), keeping: true)
        try library.add(try writePawns([goblin], named: "Pathfinder Second Pawn Box PDF.pdf"), keeping: true)
        let first = try #require(library.sources.first)
        try library.remove(first)
        #expect(library.entries.map(\.name) == ["Goblin Warrior"])
        #expect(library.entries[0].prints.allSatisfy { $0.sourceID != first.id })
        #expect(!FileManager.default.fileExists(atPath: library.keptFile(id: first.id).path))
    }

    @Test func keepsItsArtBetweenLaunches() throws {
        try library().add(try writePawns([goblin, ogre]), keeping: false)
        let reopened = try library()
        #expect(reopened.entries.map(\.name).sorted() == ["Goblin Warrior", "Ogre"])
        #expect(reopened.sources.count == 1)
        #expect(reopened.picture(of: reopened.entries[0]) != nil)
    }

    @Test func leavesOutArtWithNoName() throws {
        let nameless = DrawnPawn(rect: CGRect(x: 20, y: 600, width: 81, height: 138), art: creatureArt(variant: 2))
        let report = try library().add(try writePawns([nameless]), keeping: true)
        #expect(report.unnamed == 1 && report.added == 0)
    }

    @Test func keepsItemsApartFromCreaturesOfTheSameName() throws {
        let library = try library()
        let pawns = [DrawnPawn(rect: CGRect(x: 20, y: 600, width: 81, height: 138), art: creatureArt(variant: 0),
                               name: "BAYONET")]
        try library.add(try writePawns(pawns), keeping: true)
        let items = folder.appendingPathComponent("Pathfinder Guns Deck")
        try FileManager.default.createDirectory(at: items, withIntermediateDirectories: true)
        var cards = threeItems
        cards[0].creature = creatureArt(variant: 0, scale: 4)
        try library.add(try writeCardDeck(cards, named: "Guns.pdf", in: items), keeping: true)
        #expect(library.entries.map(\.name) == ["Bayonet", "Healing Potion", "Bayonet", "Knuckle Duster"])
        #expect(library.entries.map(\.isItem) == [false, true, true, true])
        #expect(library.entries[1].prints.first?.kind == .item)
        #expect(library.picture(of: library.entries[1], maxPixels: 100) != nil)
    }
}
