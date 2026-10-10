import CoreGraphics
import Foundation
import Testing
@testable import ArtExtraction
import ArtExtractionTestSupport

/// Drawing a figure turned upright.
@Suite struct FigureRotationTests {
    /// A figure whose head points right on its page: the creature art turned a quarter clockwise.
    func sidewaysFigure() -> Figure {
        let art = creatureArt(variant: 0)
        let rect = CGRect(x: 0, y: 0, width: 90, height: 60)
        let transform = CGAffineTransform(a: 0, b: -60, c: 90, d: 0, tx: 0, ty: 60)
        let placement = ImagePlacement(rect: rect, identity: .empty, transform: transform)
        return Figure(placement: placement, image: art, bounds: rect)
    }

    @Test func turnsTheHeadToTheTop() throws {
        let side = 60, height = 90
        let context = try #require(CGContext(data: nil, width: side, height: height, bitsPerComponent: 8,
                                             bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        sidewaysFigure().draw(in: CGRect(x: 0, y: 0, width: side, height: height), rotation: 90, context: context)
        let image = try #require(context.makeImage())
        // The head (green) is drawn near the top, the body (red) below it.
        #expect(pixel(of: image, x: 30, y: 20)[1] > 100)
        #expect(pixel(of: image, x: 30, y: 60)[0] > 100)
    }
}
