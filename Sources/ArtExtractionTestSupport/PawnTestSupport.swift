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
