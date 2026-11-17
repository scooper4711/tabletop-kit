import ArtExtraction
import ArtExtractionTestSupport
import CoreGraphics
import Foundation
@testable import SharedLibraries
import Testing

/// Turnkeeper's and Field Guide's libraries moving in (shared libraries R6).
@Suite struct LibraryMoveTests {
    let folder = temporaryFolder()
    let goblin = DrawnPawn(rect: CGRect(x: 20, y: 600, width: 81, height: 138), art: creatureArt(variant: 0),
                           name: "GOBLIN WARRIOR")
    let ogre = DrawnPawn(rect: CGRect(x: 120, y: 600, width: 81, height: 138), art: creatureArt(variant: 1),
                         name: "OGRE")

    var sharedFolder: URL { folder.appending(path: "Tableside") }

    func oldLibrary(_ app: TablesideApp) throws -> ArtLibrary {
        try ArtLibrary(folder: folder.appending(path: "\(app.rawValue)/Creature Art"))
    }

    func pawnBox() throws -> URL {
        try writePawnPDF([goblin, ogre], named: "Pathfinder Test Pawn Box PDF.pdf", in: folder)
    }

    @Test func movesAnArtLibraryInWithItsIDsAsAliases() throws {
        let old = try oldLibrary(.turnkeeper)
        try old.add(try pawnBox(), keeping: true)
        let oldGoblin = try #require(old.entries.first { $0.name == "Goblin Warrior" })
        let library = try SharedLibrary(folder: sharedFolder, app: .turnkeeper)

        let report = try #require(try library.moveIn(LibraryMove(app: .turnkeeper, artFolder: old.folder)))
        #expect(report == MoveReport(art: 2, sharedArt: 2, filesMoved: 1))
        let goblin = try #require(try library.artEntry(id: oldGoblin.id))
        #expect(goblin.name == "Goblin Warrior" && goblin.id != oldGoblin.id)
        #expect(goblin.id == goblin.prints[0].key && goblin.artEntry.prints == oldGoblin.prints)
        #expect(try library.artEntry(id: goblin.id) == goblin)

        let source = try #require(try library.sources().first)
        #expect(source.isKept && source.artSource(for: .fieldGuide)?.location == .kept)
        #expect(FileManager.default.fileExists(atPath: library.keptFile(sourceID: source.id).path))
        #expect(FileManager.default.fileExists(atPath: old.folder.appending(path: "art-library.json.moved").path))
        #expect(try library.hasMovedIn(.turnkeeper) && !library.hasMovedIn(.fieldGuide))
        #expect(try library.moveIn(LibraryMove(app: .turnkeeper, artFolder: old.folder)) == nil)
    }

    @Test func mergesTheSameArtFromTwoApps() throws {
        let pdf = try pawnBox()
        let turnkeeper = try oldLibrary(.turnkeeper), fieldGuide = try oldLibrary(.fieldGuide)
        try turnkeeper.add(pdf, keeping: true)
        try fieldGuide.add(pdf, keeping: false)
        try fieldGuide.watch(folder)
        let library = try SharedLibrary(folder: sharedFolder, app: .fieldGuide)

        try library.moveIn(LibraryMove(app: .turnkeeper, artFolder: turnkeeper.folder))
        let report = try #require(try library.moveIn(LibraryMove(app: .fieldGuide, artFolder: fieldGuide.folder)))
        #expect(report.sharedArt == 2 && report.filesMoved == 0)
        for entry in turnkeeper.entries + fieldGuide.entries {
            #expect(try library.artEntry(id: entry.id)?.name == entry.name)
        }
        let source = try #require(try library.sources().first)
        #expect(source.isKept && source.access.keys.contains(.fieldGuide))
        let watched = try library.connection().rows("SELECT path FROM watchedFolders")
        #expect(watched.compactMap { $0.text("path") } == [folder.path])
    }

    @Test func keepsAReferencedPDFReachableByTheAppGivenIt() throws {
        let old = try oldLibrary(.fieldGuide)
        try old.add(try pawnBox(), keeping: false)
        let library = try SharedLibrary(folder: sharedFolder, app: .fieldGuide)
        try library.moveIn(LibraryMove(app: .fieldGuide, artFolder: old.folder))

        let source = try #require(try library.sources().first)
        #expect(!source.isKept && source.artSource(for: .turnkeeper) == nil)
        guard case .referenced = source.artSource(for: .fieldGuide)?.location else {
            Issue.record("expected Field Guide's reference")
            return
        }
    }

    @Test func movesTokenPicturesUnderTheirKeys() throws {
        let old = try oldLibrary(.turnkeeper)
        let url = folder.appending(path: "Starfinder Test Token Box.pdf")
        try tokenPDF(pages: [[DrawnToken(center: CGPoint(x: 100, y: 600), rimName: "VESK SOLDIER")]]).write(to: url)
        try old.add(url, keeping: false)
        let library = try SharedLibrary(folder: sharedFolder, app: .turnkeeper)

        try library.moveIn(LibraryMove(app: .turnkeeper, artFolder: old.folder))
        let token = try #require(try library.artEntries().first?.prints.first)
        #expect(token.print.tokenFile == token.key.uuidString + ".png")
        #expect(FileManager.default.fileExists(atPath: library.pictureFile(token.key.uuidString + ".png").path))
    }

    @Test func bringsInTurnkeepersCreatureLibrary() throws {
        let old = try oldLibrary(.turnkeeper)
        try old.add(try pawnBox(), keeping: true)
        let artFolder = folder.appending(path: "Turnkeeper/Art")
        try FileManager.default.createDirectory(at: artFolder, withIntermediateDirectories: true)
        try Data([7]).write(to: artFolder.appending(path: "pasted.jpg"))
        let pasted = CustomArtRecord(id: UUID(), fileName: "pasted.jpg", sharedVersion: nil, record: Data())
        let oldOgre = try #require(old.entries.first { $0.name == "Ogre" })
        let library = try SharedLibrary(folder: sharedFolder, app: .turnkeeper)
        try library.setCreatureArt(.custom(pasted.id), for: "chosen.before")

        var move = LibraryMove(app: .turnkeeper, artFolder: old.folder)
        move.customCreatures = [creature(named: "Gremlin")]
        move.customArt = [pasted]
        move.customArtFolder = artFolder
        move.creatureArt = ["pathfinder.ogre": .library(oldOgre.id), "custom.1": .custom(pasted.id),
                            "chosen.before": .library(oldOgre.id)]
        try library.moveIn(move)

        let ogre = try #require(try library.artEntry(id: oldOgre.id))
        #expect(try library.creatureArt() == ["pathfinder.ogre": .library(ogre.id), "custom.1": .custom(pasted.id),
                                              "chosen.before": .custom(pasted.id)])
        #expect(try library.customCreatures().count == 1 && library.customArt() == [pasted])
        #expect(try Data(contentsOf: library.customFile("pasted.jpg")) == Data([7]))
    }

    @Test func finishesAMoveCutShort() throws {
        let old = try oldLibrary(.turnkeeper)
        try old.add(try pawnBox(), keeping: true)
        let library = try SharedLibrary(folder: sharedFolder, app: .turnkeeper)
        let move = LibraryMove(app: .turnkeeper, artFolder: old.folder)
        let plan = try MovePlan(move: move, library: library)
        try library.write { writer in try plan.record(with: writer) }
        #expect(try !library.hasMovedIn(.turnkeeper))

        let report = try #require(try library.moveIn(move))
        #expect(report.filesMoved == 1 && report.sharedArt == 2)
        #expect(try library.hasMovedIn(.turnkeeper))
    }

    @Test func dropsAKeptPDFTheLibraryHasAlready() throws {
        let pdf = try pawnBox()
        let turnkeeper = try oldLibrary(.turnkeeper), fieldGuide = try oldLibrary(.fieldGuide)
        try turnkeeper.add(pdf, keeping: true)
        try fieldGuide.add(pdf, keeping: true)
        let library = try SharedLibrary(folder: sharedFolder, app: .turnkeeper)
        try library.moveIn(LibraryMove(app: .turnkeeper, artFolder: turnkeeper.folder))

        let report = try #require(try library.moveIn(LibraryMove(app: .fieldGuide, artFolder: fieldGuide.folder)))
        #expect(report.filesMoved == 0)
        let kept = fieldGuide.folder.appending(path: "Sources")
        #expect(try FileManager.default.contentsOfDirectory(atPath: kept.path).isEmpty)
    }

    @Test func movesAnAppWithoutAnArtLibrary() throws {
        let library = try SharedLibrary(folder: sharedFolder, app: .turnkeeper)
        var move = LibraryMove(app: .turnkeeper, artFolder: folder.appending(path: "Nothing"))
        move.customCreatures = [creature(named: "Gremlin")]
        #expect(try library.moveIn(move) == MoveReport())
        #expect(try library.customCreatures().count == 1)
    }
}
