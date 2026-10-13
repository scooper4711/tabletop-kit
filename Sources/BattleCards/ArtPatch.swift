import CoreGraphics
import Foundation

/// Covers part of a piece of art with another part of it, blended in at the edges: how the level shield loses the
/// rivets that would sit behind the level. Areas are fractions of the image, so a patch fits it at any size.
public struct ArtPatch: Sendable, Equatable {
    /// The part to cover, with its origin at the top left.
    public let area: CGRect
    /// Where its cover comes from, relative to `area`.
    public let offset: CGVector
    /// How far in from the edges the cover blends into what was there.
    public let feather: CGFloat

    public init(area: CGRect, offset: CGVector, feather: CGFloat = 0.0125) {
        self.area = area
        self.offset = offset
        self.feather = feather
    }

    /// `image` with each patch applied in turn, so a later one can copy from an earlier one's cover; nil when it
    /// can't be drawn.
    static func applying(_ patches: [ArtPatch], to image: CGImage) -> CGImage? {
        let width = image.width
        let height = image.height
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        context.draw(image, in: bounds)
        for patch in patches {
            guard let current = context.makeImage() else { return nil }
            patch.draw(from: current, into: context)
        }
        return context.makeImage()
    }

    private func draw(from image: CGImage, into context: CGContext) {
        let size = CGSize(width: image.width, height: image.height)
        let target = CGRect(x: area.minX * size.width, y: area.minY * size.height,
                            width: area.width * size.width, height: area.height * size.height).integral
        let source = target.offsetBy(dx: offset.dx * size.width, dy: offset.dy * size.height)
        guard let cover = image.cropping(to: source),
              let mask = Self.mask(size: target.size, feather: feather * size.width) else { return }
        // Contexts draw from the bottom left; image areas count from the top left.
        let drawn = CGRect(x: target.minX, y: size.height - target.maxY, width: target.width, height: target.height)
        context.saveGState()
        context.clip(to: drawn, mask: mask)
        context.draw(cover, in: drawn)
        context.restoreGState()
    }

    /// Opaque in the middle, fading to clear over `feather` pixels at each edge.
    static func mask(size: CGSize, feather: CGFloat) -> CGImage? {
        let width = Int(size.width)
        let height = Int(size.height)
        guard width > 0, height > 0 else { return nil }
        var pixels = [UInt8](repeating: 0, count: width * height)
        for row in 0..<height {
            for column in 0..<width {
                let distance = CGFloat(min(column, row, width - 1 - column, height - 1 - row))
                pixels[row * width + column] = UInt8(255 * min(1, feather > 0 ? distance / feather : 1))
            }
        }
        let data = Data(pixels) as CFData
        guard let provider = CGDataProvider(data: data) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: width,
                       space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: 0),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}
