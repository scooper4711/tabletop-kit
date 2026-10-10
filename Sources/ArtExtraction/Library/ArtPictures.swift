import CoreGraphics
import Foundation
import ImageIO

/// Drawing the library's art alone, upright, from the PDFs that print it (R2.6).
extension ArtLibrary {
    /// The art on a transparent background, upright, at most `maxPixels` on its long side: from its sharpest print
    /// that can be drawn. Nil when every PDF printing it is missing.
    public func picture(of entry: ArtEntry, maxPixels: Int = 1024) -> CGImage? {
        for print in entry.prints {
            if let image = picture(of: print, maxPixels: maxPixels) { return image }
        }
        return nil
    }

    func picture(of print: ArtPrint, maxPixels: Int) -> CGImage? {
        if let file = print.tokenFile {
            return CGImageSourceCreateWithURL(tokenURL(file) as CFURL, nil)
                .flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }
        }
        guard let figure = figure(of: print) else { return nil }
        return Self.render(figure, rotation: print.face.rotation, maxPixels: maxPixels)
    }

    /// The figure a print shows, read from its PDF; nil when the PDF is missing.
    func figure(of print: ArtPrint) -> Figure? {
        guard let source = source(id: print.sourceID), status(of: source) == .available else { return nil }
        let found: Figure?? = withFile(of: source) { url in
            guard let page = CGPDFDocument(url as CFURL)?.page(at: print.face.pageIndex + 1) else { return nil }
            return Self.figure(of: print, among: PageScanner.images(on: page))
        }
        return found ?? nil
    }

    /// The figure among a page's images: a figure's own picture cut to its face, or the largest picture inside a
    /// pawn's outline, trimmed.
    static func figure(of print: ArtPrint, among images: [ImagePlacement]) -> Figure? {
        guard let index = print.imageIndex else { return Figure.largest(inside: print.face.rect, among: images) }
        guard images.indices.contains(index), let image = images[index].stream.flatMap(EmbeddedImage.maskedImage(of:))
        else { return nil }
        return Figure(placement: images[index], image: image, bounds: print.face.rect)
    }

    /// The colors of an entry's figure, measured once from its first print that can be drawn and kept with it.
    func palette(of index: Int) -> [Double] {
        if !entries[index].palette.isEmpty { return entries[index].palette }
        for print in entries[index].prints where print.kind != .token {
            if let figure = figure(of: print) {
                entries[index].palette = figure.palette()
                break
            }
        }
        return entries[index].palette
    }

    /// The figure turned upright, as large as fits in `maxPixels` on its long side.
    static func render(_ figure: Figure, rotation: Int, maxPixels: Int) -> CGImage? {
        let bounds = figure.bounds
        let upright = rotation % 180 == 0 ? bounds.size : CGSize(width: bounds.height, height: bounds.width)
        guard upright.width > 0, upright.height > 0 else { return nil }
        let scale = CGFloat(maxPixels) / max(upright.width, upright.height)
        let width = max(1, Int((upright.width * scale).rounded()))
        let height = max(1, Int((upright.height * scale).rounded()))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        figure.draw(in: CGRect(x: 0, y: 0, width: width, height: height), rotation: rotation, context: context)
        return context.makeImage()
    }
}
