import CoreGraphics
import Foundation

/// Battle maps drawn by the tool, on a regular one-inch grid Mapsmith detects: one picture per page, as map packs
/// print them.
enum DemoMaps {
    /// Pixels in one inch of the map, and its squares across and down.
    private static let pixelsPerInch = 150
    private static let squares = (across: 8, down: 10)

    static func forest() -> Data {
        map { context, size in
            context.setFillColor(CGColor(red: 0.42, green: 0.55, blue: 0.30, alpha: 1))
            context.fill(CGRect(origin: .zero, size: size))
            context.setFillColor(CGColor(red: 0.55, green: 0.45, blue: 0.30, alpha: 1))
            context.fill(CGRect(x: size.width * 0.4, y: 0, width: size.width * 0.15, height: size.height))
            context.setFillColor(CGColor(red: 0.20, green: 0.35, blue: 0.18, alpha: 1))
            for index in 0..<24 {
                let treeX = CGFloat((index * 397) % Int(size.width))
                let treeY = CGFloat((index * 613) % Int(size.height))
                guard abs(treeX - size.width * 0.47) > size.width * 0.12 else { continue }
                context.fillEllipse(in: CGRect(x: treeX, y: treeY, width: 140, height: 140))
            }
        }
    }

    static func starshipDecks() -> Data {
        map { context, size in
            context.setFillColor(CGColor(gray: 0.62, alpha: 1))
            context.fill(CGRect(origin: .zero, size: size))
            context.setFillColor(CGColor(red: 0.30, green: 0.34, blue: 0.40, alpha: 1))
            for row in stride(from: 0, to: Int(size.height), by: 450) {
                context.fill(CGRect(x: 0, y: CGFloat(row), width: size.width, height: 40))
            }
            context.setFillColor(CGColor(red: 0.85, green: 0.55, blue: 0.20, alpha: 1))
            context.fill(CGRect(x: size.width * 0.3, y: size.height * 0.45, width: 300, height: 150))
        }
    }

    /// A page holding the drawn map, with dark grid lines every inch, and the notice after it.
    private static func map(_ paint: (CGContext, CGSize) -> Void) -> Data {
        let size = CGSize(width: squares.across * pixelsPerInch, height: squares.down * pixelsPerInch)
        guard let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return Data() }
        paint(context, size)
        context.setStrokeColor(CGColor(gray: 0.1, alpha: 1))
        context.setLineWidth(3)
        for column in 0...squares.across {
            context.strokeLineSegments(between: [CGPoint(x: column * pixelsPerInch, y: 0),
                                                 CGPoint(x: CGFloat(column * pixelsPerInch), y: size.height)])
        }
        for row in 0...squares.down {
            context.strokeLineSegments(between: [CGPoint(x: 0, y: row * pixelsPerInch),
                                                 CGPoint(x: size.width, y: CGFloat(row * pixelsPerInch))])
        }
        guard let image = context.makeImage() else { return Data() }
        return makeDemoPDF(pages: [{ page in
            page.draw(image, in: CGRect(x: 18, y: 36, width: CGFloat(squares.across * 72),
                                        height: CGFloat(squares.down * 72)))
        }, DemoNotice.draw])
    }
}

/// A letter-size PDF with one page per drawing closure.
func makeDemoPDF(pages: [(CGContext) -> Void]) -> Data {
    let data = NSMutableData()
    var mediaBox = CGRect(origin: .zero, size: ProsePage.size)
    guard let consumer = CGDataConsumer(data: data as CFMutableData),
          let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return Data() }
    for draw in pages {
        context.beginPDFPage(nil)
        draw(context)
        context.endPDFPage()
    }
    context.closePDF()
    return data as Data
}
