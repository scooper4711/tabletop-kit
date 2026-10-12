import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// A card face printed as a picture, in pixels.
public let pictureCardSize = (width: 300, height: 420)

/// Writes an item deck printed as pictures into `folder`: for each name, "Deck Backs<n>.jpg" painting a 60 × 84
/// shape on a striped background every back shares, each card's in a place of its own (so the median of the
/// backs is the background), and "Deck Fronts<n>.jpg" with the name across the top.
public func writeImageDeck(_ names: [String], in folder: URL) throws {
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    for (index, name) in names.enumerated() {
        try writeJPEG(to: folder.appendingPathComponent("Deck Backs\(index + 1).jpg")) { context in
            drawStripes(context)
            context.setFillColor(CGColor(srgbRed: 0.9, green: 0.85, blue: 0.2, alpha: 1))
            context.fill(CGRect(x: 20 + (index % 3) * 90, y: 40 + (index / 3) * 120, width: 60, height: 84))
        }
        try writeJPEG(to: folder.appendingPathComponent("Deck Fronts\(index + 1).jpg")) { context in
            context.setFillColor(CGColor(srgbRed: 0.95, green: 0.92, blue: 0.8, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: pictureCardSize.width, height: pictureCardSize.height))
            context.setFillColor(CGColor(gray: 0, alpha: 1))
            drawText(context, name, at: CGPoint(x: 20, y: 370), size: 30)
            drawText(context, "This weapon is a test.", at: CGPoint(x: 20, y: 330), size: 12)
        }
    }
}

/// Dark red stripes, the same on every back.
private func drawStripes(_ context: CGContext) {
    for column in stride(from: 0, to: pictureCardSize.width, by: 10) {
        let shade = column.isMultiple(of: 20) ? 0.45 : 0.3
        context.setFillColor(CGColor(srgbRed: shade, green: 0.05, blue: 0.05, alpha: 1))
        context.fill(CGRect(x: column, y: 0, width: 10, height: pictureCardSize.height))
    }
}

private func writeJPEG(to url: URL, draw: (CGContext) -> Void) throws {
    let context = CGContext(data: nil, width: pictureCardSize.width, height: pictureCardSize.height,
                            bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    draw(context)
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, [kCGImageDestinationLossyCompressionQuality: 0.95]
                               as CFDictionary)
    CGImageDestinationFinalize(destination)
}
