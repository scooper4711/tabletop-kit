import CoreGraphics
import Foundation
import Testing
@testable import ArtExtraction
import ArtExtractionTestSupport

/// Labels rebuilt from the pieces of text a page shows.
@Suite struct LabelLinesTests {
    @Test func recordsEachPiecesSizeAndDirection() throws {
        let pdf = makePDF(pages: [{ context in
            drawText(context, "OGRE", at: CGPoint(x: 100, y: 100), size: 8)
            context.saveGState()
            context.translateBy(x: 300, y: 100)
            context.rotate(by: .pi / 2)
            drawText(context, "TROLL", at: .zero, size: 6)
            context.restoreGState()
        }])
        let glyphs = PageScanner.scan(try #require(document(pdf).page(at: 1))).glyphs
        let ogre = try #require(glyphs.first { $0.text == "OGRE" })
        let troll = try #require(glyphs.first { $0.text == "TROLL" })
        #expect(abs(ogre.fontSize - 8) < 0.01 && abs(ogre.angle) < 0.01)
        #expect(abs(troll.fontSize - 6) < 0.01 && abs(troll.angle - .pi / 2) < 0.01)
    }

    func piece(_ text: String, _ left: CGFloat, _ bottom: CGFloat, angle: CGFloat = 0) -> TextGlyph {
        TextGlyph(text: text, origin: CGPoint(x: left, y: bottom), fontSize: 8, angle: angle)
    }

    @Test func joinsKernedPiecesAndSkipsSecondCopies() {
        let pieces = [piece("PLANAR SCION, ", 533, 760), piece("LANAR SCION, ", 537, 760),
                      piece("PITB", 532, 752), piece("PITB", 532, 752),
                      piece("ORN ADEPT", 545, 752), piece("ORN ADEPT", 545, 752)]
        #expect(LabelLines.runs(of: pieces).map(\.text) == ["PLANAR SCION, ", "PITBORN ADEPT"])
    }

    @Test func skipsASecondCopyStartingWhereTheFirstDoes() {
        let pieces = [piece("P", 533, 760), piece("PLANAR SCION, ", 533, 760), piece("LANAR SCION, ", 537, 760)]
        #expect(LabelLines.runs(of: pieces).map(\.text) == ["PLANAR SCION, "])
    }

    @Test func readsTextRunningUpThePage() {
        let up = CGFloat.pi / 2
        // Text running up the page has its top to the left: the first line is the leftmost.
        let pieces = [piece("SMILODON", 177, 65, angle: up), piece("CAT, ", 168, 40, angle: up),
                      piece("CAT, ", 168, 40, angle: up)]
        #expect(LabelLines.runs(of: pieces).map(\.text) == ["CAT, ", "SMILODON"])
    }

    @Test func givesNothingForNoText() {
        #expect(LabelLines.runs(of: []).isEmpty)
    }
}
