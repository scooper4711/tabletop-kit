import CoreGraphics
import Foundation
import Testing
@testable import ArtExtraction
import ArtExtractionTestSupport

/// A pawn as a test PDF draws it: outline, art and label.
@Suite struct PawnExtractorTests {
    let goblin = artImage(variant: 0), otherGoblin = artImage(variant: 2), ogre = artImage(variant: 1)

    var fronts: [DrawnPawn] {
        [DrawnPawn(rect: CGRect(x: 20, y: 600, width: 81, height: 138), art: goblin, name: "GOBLIN WARRIOR"),
         DrawnPawn(rect: CGRect(x: 120, y: 600, width: 81, height: 138), art: goblin, name: "GOBLIN WARRIOR"),
         DrawnPawn(rect: CGRect(x: 220, y: 600, width: 81, height: 138), art: otherGoblin, name: "GOBLIN WARRIOR"),
         DrawnPawn(rect: CGRect(x: 20, y: 300, width: 180, height: 138), head: .right, art: ogre, name: "OGRE"),
         DrawnPawn(rect: CGRect(x: 320, y: 600, width: 81, height: 138), art: ogre)]
    }

    func extract(_ pages: [[DrawnPawn]]) throws -> ExtractionResult {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).pdf")
        try pawnPDF(pages: pages).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        return try PawnExtractor.extract(from: url)
    }

    @Test func countsCopiesOfTheSameArtOnly() throws {
        let result = try extract([fronts, fronts.map { $0.mirrored(pageWidth: letterPage.width) }])
        let goblins = result.pawns.filter { $0.name == "Goblin Warrior" }
        #expect(goblins.map(\.copies).sorted() == [1, 2])
        #expect(result.pawns.count == 4)
    }

    @Test func takesBacksFromTheMirroredPage() throws {
        let result = try extract([fronts, fronts.map { $0.mirrored(pageWidth: letterPage.width) }])
        let ogre = try #require(result.pawns.first { $0.name == "Ogre" })
        #expect(ogre.size == .large)
        #expect(ogre.front.rotation == 90)
        #expect(ogre.back.pageIndex == 1 && ogre.back.rotation == 270 && !ogre.back.mirrored)
        #expect(abs(ogre.back.rect.minX - (letterPage.width - 200)) < 0.5)
    }

    @Test func mirrorsTheFrontWhenThereIsNoBackPage() throws {
        let result = try extract([fronts])
        #expect(result.pawns.allSatisfy { $0.back == $0.front.mirroredCopy() })
    }

    @Test func leavesPawnsWithoutANameNamelessAndReportsThem() throws {
        let result = try extract([fronts])
        #expect(result.unnamed.count == 1)
        #expect(abs((result.unnamed.first?.rect.minX ?? 0) - 320) < 0.5)
        #expect(result.pawns.contains { $0.name.isEmpty && $0.copies == 1 })
    }

    @Test func rejectsFilesThatAreNotPDFs() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).pdf")
        try Data("not a pdf".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(throws: PawnExtractionError.unreadable(url.lastPathComponent)) { try PawnExtractor.extract(from: url) }
        #expect(PawnExtractionError.unreadable("x.pdf").description.contains("x.pdf"))
    }

    @Test func pairsOnlyMirroredPages() {
        let front = Outline(rect: CGRect(x: 20, y: 600, width: 81, height: 138), headEdge: .top)
        let mirrored = Outline(rect: CGRect(x: 511, y: 600, width: 81, height: 138), headEdge: .top)
        let elsewhere = Outline(rect: CGRect(x: 300, y: 100, width: 81, height: 138), headEdge: .top)
        let page = { (outlines: [Outline]) in PageContent(outlines: outlines) }
        #expect(PagePairing.backs(for: page([front]), among: page([mirrored])) == [mirrored])
        #expect(PagePairing.backs(for: page([front]), among: page([elsewhere])) == nil)
        #expect(PagePairing.backs(for: page([]), among: page([mirrored])) == nil)
    }

    @Test func doesNotTakeTheNextPageOfFrontsForBacks() throws {
        let nextFronts = fronts.map { pawn in
            var other = pawn.mirrored(pageWidth: letterPage.width)
            other.art = artImage(variant: 3)
            other.name = "KOBOLD"
            return other
        }
        let result = try extract([fronts, nextFronts])
        #expect(result.pawns.allSatisfy { $0.back == $0.front.mirroredCopy() })
        #expect(result.pawns.contains { $0.name == "Kobold" && $0.front.pageIndex == 1 })
    }

    @Test func takesBacksThatEmbedTheArtMirrored() throws {
        let backs = fronts.map { pawn in
            var back = pawn.mirrored(pageWidth: letterPage.width)
            back.art = pawn.art.map(horizontallyFlipped)
            return back
        }
        let result = try extract([fronts, backs])
        #expect(result.pawns.allSatisfy { $0.back.pageIndex == 1 })
    }
}
