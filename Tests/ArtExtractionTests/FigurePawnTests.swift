import CoreGraphics
import Foundation
import Testing
@testable import ArtExtraction
import ArtExtractionTestSupport

/// Pawns printed without cut outlines, found from their pictures (R1.7).
@Suite struct FigurePawnTests {
    let goblin = creatureArt(variant: 0), ogre = creatureArt(variant: 1)

    func extract(_ data: Data) throws -> ExtractionResult {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).pdf")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        return try PawnExtractor.extract(from: url)
    }

    @Test func findsUprightPawnsFromTheirPicturesAndLabels() throws {
        let row = [DrawnFigurePawn(rect: CGRect(x: 20, y: 600, width: 100, height: 146), art: goblin,
                                   name: "GOBLIN WARRIOR"),
                   DrawnFigurePawn(rect: CGRect(x: 130, y: 600, width: 100, height: 146), art: goblin,
                                   name: "GOBLIN WARRIOR"),
                   DrawnFigurePawn(rect: CGRect(x: 240, y: 600, width: 100, height: 146), art: ogre, name: "OGRE")]
        let result = try extract(figurePawnPDF(pages: [row]))
        #expect(result.pawns.map(\.name) == ["Goblin Warrior", "Ogre"])
        #expect(result.pawns.map(\.copies) == [2, 1])
        let goblinPawn = try #require(result.pawns.first)
        #expect(goblinPawn.size == .medium)
        #expect(goblinPawn.front.rotation == 0)
        #expect(goblinPawn.back == goblinPawn.front.mirroredCopy())
        guard case .card = goblinPawn.shape else { Issue.record("expected the picture alone"); return }
    }

    @Test(arguments: [(Edge.right, 90), (.left, 270), (.bottom, 180)])
    func turnsSidewaysPawnsUpright(head: Edge, rotation: Int) throws {
        let size = head == .bottom ? CGSize(width: 148, height: 190) : CGSize(width: 190, height: 148)
        let pawn = DrawnFigurePawn(rect: CGRect(origin: CGPoint(x: 200, y: 300), size: size), head: head, art: ogre,
                                   name: "HILL GIANT")
        let found = try #require(try extract(figurePawnPDF(pages: [[pawn]])).pawns.first)
        #expect(found.name == "Hill Giant")
        #expect(found.front.rotation == rotation)
        #expect(found.size == .large)
    }

    @Test func readsTheBackPageOnce() throws {
        let fronts = [DrawnFigurePawn(rect: CGRect(x: 20, y: 600, width: 100, height: 146), art: goblin,
                                      name: "GOBLIN WARRIOR"),
                      DrawnFigurePawn(rect: CGRect(x: 240, y: 300, width: 190, height: 148), head: .right, art: ogre,
                                      name: "OGRE")]
        let result = try extract(figurePawnPDF(pages: [fronts, fronts.map { $0.mirrored(pageWidth: 612) }]))
        #expect(result.pawns.map(\.name).sorted() == ["Goblin Warrior", "Ogre"])
        #expect(result.pawns.allSatisfy { $0.copies == 1 && $0.front.pageIndex == 0 })
    }

    @Test func ignoresPicturesWithoutPaizosCopyright() throws {
        let cover = DrawnFigurePawn(rect: CGRect(x: 100, y: 300, width: 300, height: 400), art: ogre,
                                    name: "PATHFINDER PAWNS", copyright: false)
        #expect(try extract(figurePawnPDF(pages: [[cover]])).pawns.isEmpty)
    }

    @Test func ignoresBlurbsBesideACoversArt() throws {
        let blurb = String(repeating: "THIS PRODUCT INCLUDES PAWNS ", count: 3)
        let cover = DrawnFigurePawn(rect: CGRect(x: 100, y: 300, width: 300, height: 400), art: ogre, name: blurb)
        #expect(try extract(figurePawnPDF(pages: [[cover]])).pawns.isEmpty)
    }

    @Test func reportsPagesPrintedAsOneFlattenedPicture() throws {
        let flattened = artImage(variant: 0, width: 85, height: 110)
        let pdf = makePDF(pages: [
            { context in drawText(context, "NPC CORE PAWN BOX", at: CGPoint(x: 50, y: 700)) },
            { context in context.draw(flattened, in: CGRect(origin: .zero, size: letterPage)) }
        ])
        #expect(try extract(pdf).unreadablePages == [1])
    }

    @Test func leavesOutlinedPagesToTheirOutlines() throws {
        let outlined = DrawnPawn(rect: CGRect(x: 20, y: 600, width: 81, height: 138), art: artImage(variant: 0),
                                 name: "GOBLIN WARRIOR")
        let found = try #require(try extract(pawnPDF(pages: [[outlined]])).pawns.first)
        guard case .pawn = found.shape else { Issue.record("expected the outlined face"); return }
    }
}
