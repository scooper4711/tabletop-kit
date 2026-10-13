import CoreGraphics
import Foundation
import Testing
@testable import BattleCards

@Suite("Covering part of a piece of art")
struct ArtPatchTests {
    /// 100 pixels square, blue, with a white square from 40 to 60 (from the top left).
    func spottedImage() throws -> CGImage {
        let context = try #require(CGContext(data: nil, width: 100, height: 100, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 40, y: 40, width: 20, height: 20))
        return try #require(context.makeImage())
    }

    /// Whether the point, counted from the top left, is white rather than blue (whose red, color matched, isn't
    /// quite 0).
    func isWhite(at point: (x: Int, y: Int), in image: CGImage) throws -> Bool {
        let data = try #require(image.dataProvider?.data as Data?)
        return data[point.y * image.bytesPerRow + point.x * image.bitsPerPixel / 8] > 200
    }

    @Test("The covered part takes the art beside it, and the rest is left alone")
    func coversTheSpot() throws {
        let image = try spottedImage()
        #expect(try isWhite(at: (50, 50), in: image))
        let patch = ArtPatch(area: CGRect(x: 0.35, y: 0.35, width: 0.3, height: 0.3), offset: CGVector(dx: -0.3, dy: 0),
                             feather: 0.02)
        let patched = try #require(ArtPatch.applying([patch], to: image))
        #expect(try !isWhite(at: (50, 50), in: patched))
        #expect(try !isWhite(at: (10, 10), in: patched) && patched.width == 100)
    }

    @Test("A later patch copies from an earlier one's cover")
    func patchesInTurn() throws {
        let first = ArtPatch(area: CGRect(x: 0.35, y: 0.35, width: 0.3, height: 0.3), offset: CGVector(dx: -0.3, dy: 0),
                             feather: 0)
        let second = ArtPatch(area: CGRect(x: 0.35, y: 0.7, width: 0.3, height: 0.2), offset: CGVector(dx: 0, dy: -0.3),
                              feather: 0)
        let patched = try #require(ArtPatch.applying([first, second], to: try spottedImage()))
        #expect(try !isWhite(at: (50, 50), in: patched) && !isWhite(at: (50, 80), in: patched))
    }

    @Test("The blend fades from clear at the edges to opaque inside")
    func mask() throws {
        let mask = try #require(ArtPatch.mask(size: CGSize(width: 20, height: 10), feather: 4))
        let data = try #require(mask.dataProvider?.data as Data?)
        #expect(data[0] == 0 && data[5 * mask.bytesPerRow + 10] == 255 && data[5 * mask.bytesPerRow + 2] < 255)
        #expect(ArtPatch.mask(size: .zero, feather: 4) == nil)
        #expect(ArtPatch.mask(size: CGSize(width: 2, height: 2), feather: 0) != nil)
    }

    @Test("The level shield's rivets are covered")
    func shieldPatches() {
        let shield = CardArtPieces.manifest.first { $0.name == "level-shield" }
        #expect(shield?.patches == CardArtPieces.shieldWithoutRivets && shield?.patches.count == 3)
    }
}
