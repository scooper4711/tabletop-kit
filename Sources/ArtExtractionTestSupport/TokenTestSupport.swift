import CoreGraphics
import Foundation
import ImageIO
import ArtExtraction

/// A round token as a test PDF draws it: art clipped to a circle, a name along its rim or a label.
public struct DrawnToken {
    public var center: CGPoint
    public var diameter: CGFloat = 90
    public var art: CGImage? = tokenArt()
    /// Drawn letter by letter along the bottom of the token, twice (an outline and a fill), as path text is.
    public var rimName: String?
    /// Label lines drawn across the middle: a token number, the name, the copyright line.
    public var label: [String] = []

    public init(center: CGPoint, diameter: CGFloat = 90, art: CGImage? = tokenArt(), rimName: String? = nil,
                label: [String] = []) {
        self.center = center
        self.diameter = diameter
        self.art = art
        self.rimName = rimName
        self.label = label
    }

    public var clip: CGRect {
        CGRect(x: center.x - diameter / 2, y: center.y - diameter / 2, width: diameter, height: diameter)
    }

    /// The same token where the back page prints it, mirrored for duplex.
    public func mirrored(pageWidth: CGFloat) -> DrawnToken {
        var back = self
        back.center.x = pageWidth - center.x
        return back
    }

    public func draw(_ context: CGContext) {
        if let art {
            context.saveGState()
            context.addEllipse(in: clip)
            context.clip()
            context.draw(art, in: clip.insetBy(dx: -1, dy: -1))
            context.restoreGState()
        }
        if let rimName {
            for _ in 0..<2 { drawRimName(rimName, context) }
        }
        for (index, line) in label.enumerated() {
            drawText(context, line, at: CGPoint(x: clip.minX + 12, y: center.y + 15 - CGFloat(index) * 10), size: 7)
        }
    }

    private func drawRimName(_ name: String, _ context: CGContext) {
        for (index, letter) in name.enumerated() {
            let angle = CGFloat.pi * (1.25 + 0.5 * CGFloat(index) / CGFloat(max(name.count - 1, 1)))
            let radius = diameter / 2 - 10
            let origin = CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
            drawText(context, String(letter), at: origin, size: 5)
        }
    }
}

/// A picture with an opaque disc in its lower half and nothing (transparent) above, so a PDF embeds it with a
/// soft mask.
public func tokenArt(variant: Int = 0) -> CGImage {
    let context = CGContext(data: nil, width: 60, height: 60, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(srgbRed: variant == 0 ? 0.9 : 0.1, green: 0.5, blue: 0.2, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 60, height: 30))
    context.setFillColor(CGColor(srgbRed: 0.1, green: 0.1, blue: variant == 0 ? 0.8 : 0.3, alpha: 1))
    context.fillEllipse(in: CGRect(x: 10 + variant * 10, y: 5, width: 20, height: 20))
    return context.makeImage()!
}

/// A dark picture covering the page behind the tokens.
public func darkBackground() -> CGImage {
    let context = CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    context.setFillColor(CGColor(srgbRed: 0.15, green: 0.05, blue: 0.25, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
    return context.makeImage()!
}

public func tokenPDF(pages: [[DrawnToken]], background: Bool = false) -> Data {
    makePDF(pages: pages.map { tokens in
        { context in
            if background { context.draw(darkBackground(), in: CGRect(origin: .zero, size: letterPage)) }
            for token in tokens { token.draw(context) }
        }
    })
}

public func extractTokens(_ pages: [[DrawnToken]], background: Bool = false) throws -> ExtractionResult {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).pdf")
    try tokenPDF(pages: pages, background: background).write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }
    return try PawnExtractor.extract(from: url)
}

/// The pixel at (`column`, `row`) from the top left as RGBA bytes.
public func pixel(of image: CGImage, x column: Int, y row: Int) -> [UInt8] {
    let context = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.draw(image, in: CGRect(x: -column, y: row - image.height + 1, width: image.width, height: image.height))
    return Array(UnsafeBufferPointer(start: context.data!.bindMemory(to: UInt8.self, capacity: 4), count: 4))
}

public func image(fromPNG data: Data) -> CGImage? {
    CGImageSourceCreateWithData(data as CFData, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }
}
