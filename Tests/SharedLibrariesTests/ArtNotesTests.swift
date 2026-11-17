import ArtExtraction
import ArtExtractionTestSupport
import CoreGraphics
import Foundation
@testable import SharedLibraries
import Testing

/// What is learned about art (shared libraries R3.3), and art an app moves in keyed (R6.1, R6.2).
@Suite struct ArtNotesTests {
    let folder = temporaryFolder()
    let figureKey = UUID(uuidString: "00000000-0000-5000-8000-000000000001")!
    let pawnKey = UUID(uuidString: "FFFFFFFF-0000-5000-8000-000000000002")!

    func library(_ app: TablesideApp = .pawnShop) throws -> SharedLibrary {
        try SharedLibrary(folder: folder.appending(path: "Tableside"), app: app)
    }

    func entry(_ prints: [(ArtKind, UUID)], source: String = "pdf") -> SharedArtEntry {
        let face = PawnFace(pageIndex: 0, rect: CGRect(x: 0, y: 0, width: 80, height: 130), rotation: 0)
        let art = ArtEntry(id: prints[0].1, name: "Ogre", game: .pathfinder, size: .large, traits: [],
                           fingerprint: ArtFingerprint(imageDigests: ["ab"]), prints: [], palette: [])
        return SharedArtEntry(art, prints: prints.map { kind, key in
            SharedPrint(key: key, print: ArtPrint(sourceID: source, kind: kind, face: face, copies: 1))
        })
    }

    @Test func keepsANoteFoundByAnyIDOfItsArt() throws {
        let library = try library()
        try library.write { writer in try writer.merge(entry([(.figure, figureKey)])) }
        let note = ArtNote(userName: "Ogre Brute", tags: ["club"], tagModel: "model 1", isCorrected: true)
        let counter = try library.changeCounter()

        #expect(try library.setNote(note, forArt: figureKey))
        #expect(try library.notes() == [figureKey: note])
        #expect(try library.changes(since: counter).changedTables == [.notes])
        #expect(try !library.setNote(note, forArt: UUID()))
        try library.setNote(nil, forArt: figureKey)
        #expect(try library.notes().isEmpty)
    }

    @Test func movesANoteToTheArtItsArtJoins() throws {
        let library = try library()
        try library.write { writer in try writer.merge(entry([(.figure, figureKey)])) }
        try library.setNote(ArtNote(tags: ["club"]), forArt: figureKey)

        try library.write { writer in try writer.merge(entry([(.pawn, pawnKey), (.figure, figureKey)])) }
        #expect(try library.notes() == [pawnKey: ArtNote(tags: ["club"])])
    }

    @Test func keepsTheCorrectedNoteWhenTwoArtsMerge() throws {
        let library = try library()
        try library.write { writer in
            try writer.merge(entry([(.figure, figureKey)]))
            try writer.upsert(ArtNote(tags: ["club"]), for: figureKey)
            try writer.upsert(ArtNote(tags: ["axe"], isCorrected: true), for: pawnKey)
            try writer.moveNote(from: figureKey, to: pawnKey)
        }
        #expect(try library.notes() == [pawnKey: ArtNote(tags: ["axe"], isCorrected: true)])
    }

    @Test func dropsTheNotesOfArtRemovedWithItsPDF() throws {
        let library = try library()
        try library.write { writer in try writer.merge(entry([(.figure, figureKey)])) }
        try library.setNote(ArtNote(tags: ["club"]), forArt: figureKey)
        _ = try library.write { writer in try writer.remove(sourceID: "pdf") }
        #expect(try library.notes().isEmpty)
    }

    @Test func movesInArtAnAppKeyedItself() throws {
        let files = folder.appending(path: "Pawn Shop", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: files, withIntermediateDirectories: true)
        try Data([1]).write(to: files.appending(path: "kept.pdf"))
        try Data([2]).write(to: files.appending(path: "token.png"))
        let oldID = UUID()
        var move = LibraryMove(app: .pawnShop, artFolder: nil)
        move.keyedSources = [ArtSource(id: "pdf", title: "Pawns", game: .pathfinder, location: .kept, byteCount: 1,
                                       readerVersion: 4, artFound: 1)]
        move.keyedArt = [entry([(.pawn, pawnKey)])]
        move.aliases = [oldID: pawnKey, UUID(): UUID()]
        move.notes = [oldID: ArtNote(userName: "Ogre Brute", isCorrected: true), UUID(): ArtNote()]
        move.keptPDFs = ["pdf": files.appending(path: "kept.pdf")]
        move.pictureFiles = ["\(pawnKey.uuidString).png": files.appending(path: "token.png")]
        let library = try library()

        let report = try #require(try library.moveIn(move))
        #expect(report == MoveReport(art: 1, sharedArt: 1, filesMoved: 2))
        #expect(try library.artEntry(id: oldID)?.id == pawnKey)
        #expect(try library.notes() == [pawnKey: ArtNote(userName: "Ogre Brute", isCorrected: true)])
        #expect(FileManager.default.fileExists(atPath: library.keptFile(sourceID: "pdf").path))

        var later = LibraryMove(app: .turnkeeper, artFolder: nil)
        later.keyedArt = [entry([(.figure, figureKey), (.pawn, pawnKey)])]
        later.notes = [pawnKey: ArtNote(tags: ["club"])]
        try self.library(.turnkeeper).moveIn(later)
        #expect(try library.notes() == [pawnKey: ArtNote(userName: "Ogre Brute", isCorrected: true)])
    }
}
