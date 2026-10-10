import CoreGraphics
import Foundation

/// Pawns printed without cut outlines (the second half of Monster Core Pawn Box, Dawn of Flame): each picture with
/// its own transparency that has a label with Paizo's copyright beside it is a pawn, and the label marks its foot.
enum FigurePawns {
    /// Smaller pictures are badges and icons, not pawns.
    static let smallestFigure: CGFloat = 36
    /// How far outside its picture a pawn's label may be printed.
    static let labelReach: CGFloat = 18

    /// A pawn found from its picture, before its label is read.
    struct Found {
        /// The picture's index among the images its page draws.
        let imageIndex: Int
        let image: ImagePlacement
        let headEdge: Edge
        /// The label's lines, top first.
        let label: [LabelRun]

        /// The size whose outline is closest to the picture's, upright.
        var size: PawnSize {
            let rect = image.rect
            let upright = headEdge == .top || headEdge == .bottom ? rect.size : CGSize(width: rect.height,
                                                                                      height: rect.width)
            return PawnSize.closest(to: upright)
        }

        var rotation: Int { Outline(rect: image.rect, headEdge: headEdge).uprightRotation }
    }

    /// The pawns a page prints as pictures with labels.
    static func figures(on page: PageContent) -> [Found] {
        let candidates = page.images.indices.filter { isCandidate(page.images[$0]) }
        var labels: [Int: [TextGlyph]] = [:]
        for glyph in page.glyphs {
            guard let index = owner(of: middle(of: glyph), among: candidates, images: page.images) else { continue }
            labels[index, default: []].append(glyph)
        }
        return candidates.compactMap { index -> Found? in
            guard let glyphs = labels[index], glyphs.contains(where: isCopyright) else { return nil }
            let rect = page.images[index].rect
            return Found(imageIndex: index, image: page.images[index],
                         headEdge: footEdge(of: rect, glyphs: glyphs).opposite, label: LabelLines.runs(of: glyphs))
        }
    }

    /// True when the next page prints the same pictures again, as the back of a page printed for duplex.
    static func isBackPage(_ next: [Found], of fronts: [Found]) -> Bool {
        let backDigests = Set(next.map(\.image.identity.digest))
        let shared = fronts.count { backDigests.contains($0.image.identity.digest) }
        return !fronts.isEmpty && shared * 2 >= fronts.count
    }

    private static func isCandidate(_ image: ImagePlacement) -> Bool {
        guard let stream = image.stream, min(image.rect.width, image.rect.height) >= smallestFigure
        else { return false }
        return EmbeddedImage.hasSoftMask(stream)
    }

    private static func isCopyright(_ glyph: TextGlyph) -> Bool {
        glyph.text.contains("©") || glyph.text.localizedCaseInsensitiveContains("paizo")
    }

    /// The picture a piece of text belongs to: the one it is printed inside, nearest that picture's edge, or else
    /// the nearest one it is printed within reach of.
    private static func owner(of point: CGPoint, among candidates: [Int], images: [ImagePlacement]) -> Int? {
        let scored = candidates.compactMap { index -> (index: Int, score: CGFloat)? in
            let rect = images[index].rect
            let outside = distance(from: point, to: rect)
            guard outside <= labelReach else { return nil }
            // Inside a picture scores below zero, nearer its edge lower still, so it beats any picture outside.
            return (index, outside > 0 ? outside : edgeDistances(of: point, in: rect).min()! - labelReach * 2)
        }
        return scored.min { $0.score < $1.score }?.index
    }

    /// About the middle of a piece of text: its start moved half its estimated length along it and a third of its
    /// size up.
    static func middle(of glyph: TextGlyph) -> CGPoint {
        let length = CGFloat(glyph.text.count) * glyph.fontSize * LabelLines.averageWidth
        let along = CGVector(dx: cos(glyph.angle), dy: sin(glyph.angle))
        return CGPoint(x: glyph.origin.x + along.dx * length / 2 - along.dy * glyph.fontSize / 3,
                       y: glyph.origin.y + along.dy * length / 2 + along.dx * glyph.fontSize / 3)
    }

    /// The edge the label is printed along: the one nearest its text.
    private static func footEdge(of rect: CGRect, glyphs: [TextGlyph]) -> Edge {
        let middles = glyphs.map(middle(of:))
        let center = CGPoint(x: middles.map(\.x).reduce(0, +) / CGFloat(middles.count),
                             y: middles.map(\.y).reduce(0, +) / CGFloat(middles.count))
        let distances = edgeDistances(of: center, in: rect)
        let edges: [Edge] = [.left, .right, .bottom, .top]
        return edges[distances.indices.min { distances[$0] < distances[$1] }!]
    }

    /// Distances from `point` to the left, right, bottom and top edges' lines.
    private static func edgeDistances(of point: CGPoint, in rect: CGRect) -> [CGFloat] {
        [abs(point.x - rect.minX), abs(rect.maxX - point.x), abs(point.y - rect.minY), abs(rect.maxY - point.y)]
    }

    private static func distance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return (dx * dx + dy * dy).squareRoot()
    }
}

extension Edge {
    /// The edge across the rectangle.
    var opposite: Edge {
        switch self {
        case .top: .bottom
        case .bottom: .top
        case .left: .right
        case .right: .left
        }
    }
}

extension PawnSize {
    /// The printed size whose outline is closest to `upright` (small to huge; Paizo prints no gargantuan pawns).
    static func closest(to upright: CGSize) -> PawnSize {
        func distance(_ size: PawnSize) -> CGFloat {
            abs(size.outlineSize.width - upright.width) + abs(size.outlineSize.height - upright.height)
        }
        return [PawnSize.small, .medium, .large, .huge].min { distance($0) < distance($1) } ?? .medium
    }
}
