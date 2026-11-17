import ArtExtraction
import ArtExtractionTestSupport
import CoreGraphics
import Foundation
@testable import SharedLibraries
import Testing

/// Art merging by key in the shared library (shared libraries R2.5).
@Suite struct ArtMergeTests {
    let library: SharedLibrary
    let figureKey = UUID(uuidString: "00000000-0000-5000-8000-000000000001")!
    let pawnKey = UUID(uuidString: "FFFFFFFF-0000-5000-8000-000000000002")!

    init() throws {
        library = try SharedLibrary(folder: temporaryFolder().appending(path: "Tableside"), app: .pawnShop)
    }

    func entry(_ prints: [(ArtKind, UUID)], palette: [Double] = [], traits: [String] = []) -> SharedArtEntry {
        let face = PawnFace(pageIndex: 0, rect: CGRect(x: 0, y: 0, width: 80, height: 130), rotation: 0)
        let art = ArtEntry(id: UUID(), name: "Ogre", game: .pathfinder, size: .large, traits: traits,
                           fingerprint: ArtFingerprint(imageDigests: ["ab"]),
                           prints: prints.map { ArtPrint(sourceID: "pdf", kind: $0.0, face: face, copies: 1) },
                           palette: palette)
        return SharedArtEntry(art, keys: prints.map(\.1))
    }

    @Test func aPawnTakesOverTheIDOfArtItJoins() throws {
        let figureID = try library.write { writer in
            try writer.merge(entry([(.figure, figureKey)], palette: [0.5]))
        }
        #expect(figureID == figureKey)
        try library.setCreatureArt(.library(figureID), for: "ogre")
        try library.write { writer in try writer.addAlias(UUID(), app: .turnkeeper, entry: figureID) }
        let counter = try library.changeCounter()

        let mergedID = try library.write { writer in
            try writer.merge(entry([(.pawn, pawnKey), (.figure, figureKey)], traits: ["Giant"]))
        }
        #expect(mergedID == pawnKey)
        let merged = try #require(try library.artEntries().first)
        #expect(try library.artEntries().count == 1)
        #expect(merged.prints.map(\.key) == [figureKey, pawnKey])
        #expect(merged.palette == [0.5] && merged.traits == ["Giant"])
        #expect(try library.artEntry(id: figureKey)?.id == pawnKey)
        #expect(try library.creatureArt() == ["ogre": .library(pawnKey)])
        let aliases = try library.connection().rows("SELECT entry FROM aliases").compactMap { $0.uuid("entry") }
        #expect(aliases == [pawnKey])
        #expect(try library.changes(since: counter).deletions == [.art: [figureKey.uuidString]])
    }

    @Test func keepsANewerReadersFindings() throws {
        let older = ArtSource(id: "pdf", title: "Pawns", game: .pathfinder, location: .kept, byteCount: 10,
                              readerVersion: 1, artFound: 3)
        var newer = older
        newer.readerVersion = 2
        newer.artFound = 5
        try library.write { writer in
            try writer.add(newer, for: .turnkeeper)
            try writer.add(older, for: .fieldGuide)
        }
        let source = try #require(try library.sources().first)
        #expect(source.readerVersion == 2 && source.artFound == 5)
    }

    @Test func artLeftWithoutPrintsHandsItsNoteToTheArtInItsPlace() throws {
        let oldKey = UUID(), newKey = UUID(), oldID = UUID()
        try library.write { writer in try writer.merge(entry([(.figure, oldKey)])) }
        try library.setNote(ArtNote(tags: ["club"], isCorrected: true), forArt: oldKey)
        try library.write { writer in try writer.addAlias(oldID, app: .pawnShop, entry: oldKey) }

        try library.write { writer in
            let older = try writer.takeOutPrints(of: "pdf")
            var reread = entry([(.figure, newKey)])
            reread.name = "Ogre Brute"
            try writer.merge(reread)
            try writer.retire(older, app: .pawnShop)
        }
        #expect(try library.artEntries().map(\.id) == [newKey])
        #expect(try library.notes()[newKey]?.tags == ["club"])
        #expect(try library.artEntry(id: oldKey)?.id == newKey)
        #expect(try library.artEntry(id: oldID)?.id == newKey)
    }

    @Test func findsNothingForAnUnknownID() throws {
        #expect(try library.artEntry(id: UUID()) == nil)
        try library.write { writer in try writer.addAlias(figureKey, app: .pawnShop, entry: figureKey) }
        #expect(try library.connection().rows("SELECT * FROM aliases").isEmpty)
    }
}
