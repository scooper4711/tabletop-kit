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

    @Test func readsPawnsWithoutACopyrightLine() throws {
        let pawn = DrawnFigurePawn(rect: CGRect(x: 20, y: 600, width: 100, height: 146), art: goblin,
                                   name: "GOBLIN WARRIOR", copyright: false)
        #expect(try extract(figurePawnPDF(pages: [[pawn]])).pawns.map(\.name) == ["Goblin Warrior"])
    }

    @Test func leavesTheCopyrightOutOfTheName() throws {
        let pawn = DrawnFigurePawn(rect: CGRect(x: 20, y: 600, width: 100, height: 146), art: goblin,
                                   name: "GOBLIN WARRIOR © 2026 PAIZO INC.", copyright: false)
        #expect(try extract(figurePawnPDF(pages: [[pawn]])).pawns.map(\.name) == ["Goblin Warrior"])
    }

    @Test func ignoresACoversArt() throws {
        let cover = DrawnFigurePawn(rect: CGRect(x: 100, y: 300, width: 300, height: 400), art: ogre,
                                    name: "PATHFINDER PAWNS", copyright: false)
        #expect(try extract(figurePawnPDF(pages: [[cover]])).pawns.isEmpty)
    }

    @Test func ignoresBlurbsBesideACoversArt() throws {
        let blurb = String(repeating: "THIS PRODUCT INCLUDES PAWNS ", count: 3)
        let cover = DrawnFigurePawn(rect: CGRect(x: 100, y: 300, width: 300, height: 400), art: ogre, name: blurb)
        #expect(try extract(figurePawnPDF(pages: [[cover]])).pawns.isEmpty)
    }

    @Test func ignoresPicturesAmongAnAdsText() throws {
        let pictures = [DrawnFigurePawn(rect: CGRect(x: 20, y: 600, width: 100, height: 146), art: goblin,
                                        name: "177. ZAHRA", copyright: false),
                        DrawnFigurePawn(rect: CGRect(x: 130, y: 600, width: 100, height: 146), art: ogre,
                                        name: "24) AVENNA", copyright: false)]
        let advertisement = makePDF(pages: [{ context in
            pictures.forEach { $0.draw(context) }
            for line in 0..<12 {
                drawText(context, "KEY MONSTERS AND NPCS COME ALIVE ON YOUR TABLETOP",
                         at: CGPoint(x: 300, y: 400 - CGFloat(line) * 12), size: 9)
            }
        }])
        #expect(try extract(advertisement).pawns.isEmpty)
    }

    @Test func ignoresAPictureUnderACoversTitle() throws {
        let cover = makePDF(pages: [{ [goblin] context in
            context.draw(goblin, in: CGRect(x: 200, y: 400, width: 100, height: 146))
            drawText(context, "PAWN COLLECTION", at: CGPoint(x: 204, y: 380), size: 32)
        }])
        #expect(try extract(cover).pawns.isEmpty)
    }

    /// Traps & Treasures' cover shows small copies of its pawns, labels and all.
    @Test func ignoresPawnsShownUnderACoversTitle() throws {
        let shown = [DrawnFigurePawn(rect: CGRect(x: 200, y: 400, width: 60, height: 60), art: goblin, name: "SPIKES"),
                     DrawnFigurePawn(rect: CGRect(x: 270, y: 400, width: 60, height: 60), art: ogre, name: "LEVER")]
        let cover = makePDF(pages: [{ context in
            shown.forEach { $0.draw(context) }
            drawText(context, "PC", at: CGPoint(x: 250, y: 100), size: 36)
        }])
        #expect(try extract(cover).pawns.isEmpty)
    }

    @Test func readsPawnsAmongLabeledPiecesWithoutTransparency() throws {
        let pawn = DrawnFigurePawn(rect: CGRect(x: 20, y: 600, width: 100, height: 146), art: goblin,
                                   name: "COMM UNIT")
        let scenery = makePDF(pages: [{ context in
            pawn.draw(context)
            for column in 1...4 {
                let rect = CGRect(x: 20 + CGFloat(column) * 110, y: 600, width: 100, height: 146)
                context.draw(artImage(variant: column), in: rect)
                drawText(context, "WALL OF FIRE", at: CGPoint(x: rect.minX + 4, y: rect.minY - 9), size: 8)
            }
        }])
        #expect(try extract(scenery).pawns.map(\.name) == ["Comm Unit"])
    }

    @Test func aPageWithoutTextIsOneOfPawns() {
        #expect(FigurePawns.isPawnPage(PageContent()))
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
