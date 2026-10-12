import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Finds the items in a deck of JPG card faces. The backs paint each item on the same background and frame, so
/// the background is the per-pixel median of all backs, and an item is what differs from it. Its name is read
/// off the front (`CardNameReader`).
enum ImageDeckExtractor {
    /// Backs are compared at most this many pixels on their long side, to keep the median's memory small.
    static let longSide = 520
    /// Color differences (largest channel, 0–255) at or below this are background, at or above `opaque` the
    /// item, and between them partly transparent, which softens the item's edge.
    static let transparent = 30
    static let opaque = 60

    static func extract(from deck: ImageDeck) -> ExtractionResult {
        guard let size = size(of: deck) else { return ExtractionResult() }
        let backs = deck.cards.map { Bitmap(url: $0.back, width: size.width, height: size.height) }
        let readable = backs.compactMap { $0 }
        guard readable.count >= ImageDeck.fewestCards else { return ExtractionResult() }
        let background = Bitmap.median(of: readable)
        var result = ExtractionResult()
        for (card, back) in zip(deck.cards, backs) {
            guard let back, let item = back.cutOut(from: background, transparent: transparent, opaque: opaque),
                  let png = item.image.pngData() else { continue }
            let name = card.front.map(CardNameReader.name(onFront:)) ?? ""
            let face = PawnFace(pageIndex: card.number, rect: item.bounds, rotation: 0)
            let digest = SHA256.hash(data: png).map { String(format: "%02x", $0) }.joined()
            PawnExtractor.add(ExtractedPawn(name: name, size: .medium, front: face, back: face.mirroredCopy(),
                                            fingerprint: ArtFingerprint(imageDigests: [digest]), copies: 1,
                                            shape: .drawnItem(png)), to: &result)
        }
        return result
    }

    /// The size the backs are compared at: the first back's, shrunk to `longSide`.
    private static func size(of deck: ImageDeck) -> (width: Int, height: Int)? {
        guard let first = deck.cards.first,
              let source = CGImageSourceCreateWithURL(first.back as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let scale = min(1, Double(longSide) / Double(max(image.width, image.height)))
        return (Int((Double(image.width) * scale).rounded()), Int((Double(image.height) * scale).rounded()))
    }
}

/// An image's pixels as RGBA bytes, row by row from the top.
struct Bitmap {
    let width: Int
    let height: Int
    var pixels: [UInt8]

    init(width: Int, height: Int, pixels: [UInt8]) {
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    /// The image at `url` drawn at this size; nil when it can't be read.
    init?(url: URL, width: Int, height: Int) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = Self.context(buffer.baseAddress, width: width, height: height, alpha: false)
            else { return false }
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        self.init(width: width, height: height, pixels: pixels)
    }

    /// Each pixel's median color over the bitmaps, all of one size.
    static func median(of bitmaps: [Bitmap]) -> Bitmap {
        let first = bitmaps[0]
        var pixels = [UInt8](repeating: 255, count: first.pixels.count)
        var samples = [UInt8](repeating: 0, count: bitmaps.count)
        for index in pixels.indices where index % 4 != 3 {
            for (sample, bitmap) in bitmaps.enumerated() { samples[sample] = bitmap.pixels[index] }
            samples.sort()
            pixels[index] = samples[samples.count / 2]
        }
        return Bitmap(width: first.width, height: first.height, pixels: pixels)
    }

    /// What differs from the background, transparent elsewhere and cropped to its opaque part, with that part's
    /// bounds in the bitmap (from the bottom left); nil when nothing differs.
    func cutOut(from background: Bitmap, transparent: Int, opaque: Int) -> (image: CGImage, bounds: CGRect)? {
        var cut = pixels
        var rows = [Int](repeating: 0, count: height)
        var columns = [Int](repeating: 0, count: width)
        for pixel in 0..<(width * height) {
            let offset = pixel * 4
            let difference = (0..<3).map { abs(Int(pixels[offset + $0]) - Int(background.pixels[offset + $0])) }
                .max() ?? 0
            let alpha = min(255, max(0, (difference - transparent) * 255 / (opaque - transparent)))
            for channel in 0..<3 { cut[offset + channel] = UInt8(Int(pixels[offset + channel]) * alpha / 255) }
            cut[offset + 3] = UInt8(alpha)
            if alpha == 255 {
                rows[pixel / width] += 1
                columns[pixel % width] += 1
            }
        }
        guard let crop = Self.crop(rows: rows, columns: columns) else { return nil }
        let image = cut.withUnsafeMutableBytes { buffer in
            Self.context(buffer.baseAddress, width: width, height: height, alpha: true)?.makeImage()
        }
        guard let cropped = image?.cropping(to: crop) else { return nil }
        let bounds = CGRect(x: crop.minX, y: CGFloat(height) - crop.maxY, width: crop.width, height: crop.height)
        return (cropped, bounds)
    }

    /// The rect (from the top left) spanning the rows and columns with a few opaque pixels, so that a stray
    /// speck of noise doesn't widen it; nil when there are none.
    private static func crop(rows: [Int], columns: [Int]) -> CGRect? {
        let fewest = 3
        guard let top = rows.firstIndex(where: { $0 >= fewest }), let bottom = rows.lastIndex(where: { $0 >= fewest }),
              let left = columns.firstIndex(where: { $0 >= fewest }),
              let right = columns.lastIndex(where: { $0 >= fewest }) else { return nil }
        return CGRect(x: left, y: top, width: right - left + 1, height: bottom - top + 1)
    }

    private static func context(_ data: UnsafeMutableRawPointer?, width: Int, height: Int, alpha: Bool) -> CGContext? {
        CGContext(data: data, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: (alpha ? CGImageAlphaInfo.premultipliedLast : .noneSkipLast).rawValue)
    }
}

extension CGImage {
    /// The image as PNG; nil when it can't be encoded.
    func pngData() -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, self, nil)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }
}
