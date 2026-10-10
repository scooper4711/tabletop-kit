import CoreGraphics
import Foundation
import ArtExtraction

public struct DrawnPawn {
    public var rect: CGRect
    public var head: Edge = .top
    public var art: CGImage?
    public var name: String?

    public init(rect: CGRect, head: Edge = .top, art: CGImage? = nil, name: String? = nil) {
        self.rect = rect
        self.head = head
        self.art = art
        self.name = name
    }

    /// The same pawn where the back page prints it, mirrored for duplex.
    public func mirrored(pageWidth: CGFloat) -> DrawnPawn {
        var back = self
        back.rect.origin.x = pageWidth - rect.maxX
        back.head = [.left: .right, .right: .left][head] ?? head
        return back
    }

    public func draw(_ context: CGContext) {
        if let art { context.draw(art, in: rect.insetBy(dx: 4, dy: 20)) }
        strokeOutline(context, rect, head: head)
        if let name {
            drawText(context, name, at: CGPoint(x: rect.minX + 6, y: rect.minY + 10), size: 8)
            drawText(context, "© 2019 PAIZO INC.", at: CGPoint(x: rect.minX + 6, y: rect.minY + 4), size: 4)
        }
    }
}

public func pawnPDF(pages: [[DrawnPawn]]) -> Data {
    makePDF(pages: pages.map { pawns in { context in for pawn in pawns { pawn.draw(context) } } })
}

/// A fresh folder under the system's temporary directory.
public func temporaryFolder() -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("PawnShopTests-\(UUID())")
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// Writes a pawn PDF with a front page and its mirrored back.
public func writePawnPDF(_ pawns: [DrawnPawn], named name: String, in folder: URL) throws -> URL {
    let url = folder.appendingPathComponent(name)
    try pawnPDF(pages: [pawns, pawns.map { $0.mirrored(pageWidth: letterPage.width) }]).write(to: url)
    return url
}

/// A pawn printed without a cut outline, as the second half of Monster Core Pawn Box prints them: a picture with
/// its own transparency, turned so its head points to `head`, with its name and Paizo's copyright along its foot.
public struct DrawnFigurePawn {
    /// Where the picture is drawn.
    public var rect: CGRect
    public var head: Edge
    public var art: CGImage
    public var name: String
    public var copyright: Bool

    public init(rect: CGRect, head: Edge = .top, art: CGImage = creatureArt(), name: String,
                copyright: Bool = true) {
        self.rect = rect
        self.head = head
        self.art = art
        self.name = name
        self.copyright = copyright
    }

    /// The same pawn where the back page prints it, mirrored for duplex.
    public func mirrored(pageWidth: CGFloat) -> DrawnFigurePawn {
        var back = self
        back.rect.origin.x = pageWidth - rect.maxX
        back.head = [.left: .right, .right: .left][head] ?? head
        return back
    }

    public func draw(_ context: CGContext) {
        let turns: [Edge: CGFloat] = [.top: 0, .left: .pi / 2, .bottom: .pi, .right: -.pi / 2]
        let upright = head == .top || head == .bottom ? rect.size : CGSize(width: rect.height, height: rect.width)
        context.saveGState()
        context.translateBy(x: rect.midX, y: rect.midY)
        context.rotate(by: turns[head] ?? 0)
        context.draw(art, in: CGRect(x: -upright.width / 2, y: -upright.height / 2, width: upright.width,
                                     height: upright.height))
        // The label runs along the foot, turned with the pawn, just outside the picture.
        drawText(context, name, at: CGPoint(x: -upright.width / 2 + 4, y: -upright.height / 2 - 9), size: 8)
        if copyright {
            drawText(context, "© 2024 PAIZO INC.", at: CGPoint(x: -upright.width / 2 + 4, y: -upright.height / 2 - 15),
                     size: 4)
        }
        context.restoreGState()
    }
}

/// A PDF of pawns printed without cut outlines, one page per list.
public func figurePawnPDF(pages: [[DrawnFigurePawn]]) -> Data {
    makePDF(pages: pages.map { pawns in { context in for pawn in pawns { pawn.draw(context) } } })
}
