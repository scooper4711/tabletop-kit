import CoreGraphics
import Foundation

/// A label's lines rebuilt from the pieces of text a page shows. Labels printed beside outline-less pawns break
/// words where the type is kerned ("PITB", "ORN ADEPT") and are drawn twice, a fill and an outline, the second
/// copy sometimes split differently ("PLANAR SCION," then "P", "LANAR SCION,").
enum LabelLines {
    /// A condensed capital is about this wide, as a share of the type's size; enough to tell a second copy
    /// printed over the first from the next piece of the same word.
    static let averageWidth: CGFloat = 0.45

    /// One run per line, top line first, pieces joined as printed and second copies left out.
    static func runs(of glyphs: [TextGlyph]) -> [LabelRun] {
        guard let angle = glyphs.first?.angle else { return [] }
        let along = CGVector(dx: cos(angle), dy: sin(angle))
        let across = CGVector(dx: -sin(angle), dy: cos(angle))
        var lines: [[TextGlyph]] = []
        for glyph in glyphs.sorted(by: { position($0, across) > position($1, across) }) {
            let tolerance = max(glyph.fontSize, 1) / 2
            if let last = lines.last?.last, abs(position(last, across) - position(glyph, across)) <= tolerance {
                lines[lines.count - 1].append(glyph)
            } else {
                lines.append([glyph])
            }
        }
        return lines.map { line in run(of: line.sorted { position($0, along) < position($1, along) }, along: along) }
    }

    /// A line's pieces joined, skipping any that starts well inside the text before it, or where it starts: a
    /// second copy.
    private static func run(of pieces: [TextGlyph], along: CGVector) -> LabelRun {
        var text = ""
        var lastStart = -CGFloat.infinity, end = -CGFloat.infinity
        for piece in pieces {
            let start = position(piece, along)
            guard start >= end - piece.fontSize / 2, start - lastStart > piece.fontSize / 4 else { continue }
            text += piece.text
            lastStart = start
            end = start + CGFloat(piece.text.count) * piece.fontSize * averageWidth
        }
        return LabelRun(text: text, fontSize: pieces.map(\.fontSize).max() ?? 0)
    }

    private static func position(_ glyph: TextGlyph, _ axis: CGVector) -> CGFloat {
        glyph.origin.x * axis.dx + glyph.origin.y * axis.dy
    }
}
