import CoreGraphics
import Foundation

/// The adventure's handout: a torn-off piece of the forest map, tinted like parchment, with a dashed trail to an X.
/// It has no grid, as a handout isn't a battle map. Its torn edge comes from a fixed sequence, so the demo PDFs are
/// the same on every run.
extension DemoMaps {
    private static let fragmentSize = CGSize(width: 900, height: 700)

    static func fragment() -> CGImage? {
        let size = fragmentSize
        guard let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.addPath(tornOutline(in: CGRect(origin: .zero, size: size).insetBy(dx: 30, dy: 30)))
        context.clip()
        paintForest(context, size: size)
        context.setFillColor(CGColor(red: 0.93, green: 0.84, blue: 0.62, alpha: 0.45))
        context.fill(CGRect(origin: .zero, size: size))
        drawTrail(context, size: size)
        return context.makeImage()
    }

    /// A rectangle whose edges are torn: points along each side, each pushed in by a fixed, irregular amount.
    static func tornOutline(in rect: CGRect) -> CGPath {
        let corners = [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
                       CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY)]
        let path = CGMutablePath()
        var step = 0
        for (index, start) in corners.enumerated() {
            let end = corners[(index + 1) % corners.count]
            let inward = CGPoint(x: rect.midX - (start.x + end.x) / 2, y: rect.midY - (start.y + end.y) / 2)
            let length = hypot(inward.x, inward.y)
            for part in 0..<18 {
                let along = CGFloat(part) / 18
                let depth = tearDepth(step)
                step += 1
                let point = CGPoint(x: start.x + (end.x - start.x) * along + inward.x / length * depth,
                                    y: start.y + (end.y - start.y) * along + inward.y / length * depth)
                if step == 1 { path.move(to: point) } else { path.addLine(to: point) }
            }
        }
        path.closeSubpath()
        return path
    }

    /// How far the torn edge reaches in at its `step`th point: 0 to 27 pixels, in a fixed, irregular pattern.
    private static func tearDepth(_ step: Int) -> CGFloat {
        CGFloat((step * 37 + step * step * 11) % 28)
    }

    /// A dashed red trail winding up the forest path to an X.
    private static func drawTrail(_ context: CGContext, size: CGSize) {
        let red = CGColor(red: 0.62, green: 0.12, blue: 0.10, alpha: 1)
        context.setStrokeColor(red)
        context.setLineWidth(9)
        context.setLineCap(.round)
        context.setLineDash(phase: 0, lengths: [26, 20])
        let trail = CGMutablePath()
        trail.move(to: CGPoint(x: size.width * 0.47, y: size.height * 0.1))
        trail.addCurve(to: CGPoint(x: size.width * 0.72, y: size.height * 0.7),
                       control1: CGPoint(x: size.width * 0.35, y: size.height * 0.45),
                       control2: CGPoint(x: size.width * 0.8, y: size.height * 0.4))
        context.addPath(trail)
        context.strokePath()
        context.setLineDash(phase: 0, lengths: [])
        context.setLineWidth(14)
        let mark = CGPoint(x: size.width * 0.72, y: size.height * 0.78)
        context.strokeLineSegments(between: [
            CGPoint(x: mark.x - 40, y: mark.y - 40), CGPoint(x: mark.x + 40, y: mark.y + 40),
            CGPoint(x: mark.x - 40, y: mark.y + 40), CGPoint(x: mark.x + 40, y: mark.y - 40)
        ])
    }
}
