import CoreGraphics
import Foundation

/// Battle maps drawn by the tool at the size of Paizo's Flip-Mats, 24 by 30 inches, on a regular one-inch grid
/// Mapsmith detects: one picture per page, the page the map's own size, as Flip-Mat PDFs print them.
enum DemoMaps {
    /// Pixels in one inch of the map, and its squares across and down.
    private static let pixelsPerInch = 150
    private static let squares = (across: 24, down: 30)
    private static let inch = CGFloat(pixelsPerInch)

    static func forest() -> Data {
        map(paintForest)
    }

    /// The forest with a trail through it, filling `size`.
    static func paintForest(_ context: CGContext, size: CGSize) {
        context.setFillColor(CGColor(red: 0.42, green: 0.55, blue: 0.30, alpha: 1))
        context.fill(CGRect(origin: .zero, size: size))
        context.setFillColor(CGColor(red: 0.55, green: 0.45, blue: 0.30, alpha: 1))
        let trail = CGRect(x: size.width * 0.4, y: 0, width: size.width * 0.15, height: size.height)
        context.fill(trail)
        context.setFillColor(CGColor(red: 0.20, green: 0.35, blue: 0.18, alpha: 1))
        for tree in trees(in: size) where !trail.insetBy(dx: -inch / 2, dy: 0).intersects(tree) {
            context.fillEllipse(in: tree)
        }
    }

    static func starshipDecks() -> Data {
        map { context, size in
            context.setFillColor(CGColor(gray: 0.62, alpha: 1))
            context.fill(CGRect(origin: .zero, size: size))
            context.setFillColor(CGColor(red: 0.30, green: 0.34, blue: 0.40, alpha: 1))
            for row in stride(from: 0, to: size.height, by: 3 * inch) {
                context.fill(CGRect(x: 0, y: row, width: size.width, height: 0.27 * inch))
            }
            context.setFillColor(CGColor(red: 0.85, green: 0.55, blue: 0.20, alpha: 1))
            for (column, row) in [(3, 4), (14, 4), (7, 13), (17, 16), (2, 22), (12, 25)] {
                let corner = CGPoint(x: CGFloat(column) * inch, y: CGFloat(row) * inch)
                context.fill(CGRect(origin: corner, size: CGSize(width: 4 * inch, height: 2 * inch)))
            }
        }
    }

    /// About three trees in every ten square inches of `size`, each about an inch across, scattered evenly but always
    /// in the same places (the R2 low-discrepancy sequence), so the map is the same every time it is written.
    private static func trees(in size: CGSize) -> [CGRect] {
        let count = Int(size.width * size.height / (inch * inch)) * 3 / 10
        return (0..<count).map { index in
            let position = Double(index) + 0.5
            let across = (position * 0.754_877_666).truncatingRemainder(dividingBy: 1)
            let down = (position * 0.569_840_291).truncatingRemainder(dividingBy: 1)
            let diameter = inch * (0.8 + 0.1 * CGFloat(index % 5))
            return CGRect(x: across * size.width - diameter / 2, y: down * size.height - diameter / 2,
                          width: diameter, height: diameter)
        }
    }

    /// A page the map's size holding the drawn map, with dark grid lines every inch, then the letter-size notice.
    private static func map(_ paint: (CGContext, CGSize) -> Void) -> Data {
        let size = CGSize(width: squares.across * pixelsPerInch, height: squares.down * pixelsPerInch)
        guard let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return Data() }
        paint(context, size)
        drawGrid(in: context, size: size)
        guard let image = context.makeImage() else { return Data() }
        let page = CGRect(x: 0, y: 0, width: squares.across * 72, height: squares.down * 72)
        return makeDemoPDF(sizedPages: [DemoPage(size: page.size) { $0.draw(image, in: page) },
                                        DemoPage(draw: DemoNotice.page(.drawnMaps))])
    }

    private static func drawGrid(in context: CGContext, size: CGSize) {
        context.setStrokeColor(CGColor(gray: 0.1, alpha: 1))
        context.setLineWidth(3)
        for column in 0...squares.across {
            let left = CGFloat(column) * inch
            context.strokeLineSegments(between: [CGPoint(x: left, y: 0), CGPoint(x: left, y: size.height)])
        }
        for row in 0...squares.down {
            let bottom = CGFloat(row) * inch
            context.strokeLineSegments(between: [CGPoint(x: 0, y: bottom), CGPoint(x: size.width, y: bottom)])
        }
    }
}

/// A page of a demo PDF: its size and what is drawn on it.
struct DemoPage {
    var size = ProsePage.size
    var draw: (CGContext) -> Void
}

/// A letter-size PDF with one page per drawing closure.
func makeDemoPDF(pages: [(CGContext) -> Void]) -> Data {
    makeDemoPDF(sizedPages: pages.map { DemoPage(draw: $0) })
}

/// A PDF with one page per `DemoPage`, each its own size.
func makeDemoPDF(sizedPages pages: [DemoPage]) -> Data {
    let data = NSMutableData()
    guard let consumer = CGDataConsumer(data: data as CFMutableData),
          let context = CGContext(consumer: consumer, mediaBox: nil, nil) else { return Data() }
    for page in pages {
        var box = CGRect(origin: .zero, size: page.size)
        let mediaBox = Data(bytes: &box, count: MemoryLayout<CGRect>.size) as CFData
        context.beginPDFPage([kCGPDFContextMediaBox as String: mediaBox] as CFDictionary)
        page.draw(context)
        context.endPDFPage()
    }
    context.closePDF()
    return data as Data
}
