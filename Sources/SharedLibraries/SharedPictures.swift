import ArtExtraction
import CoreGraphics
import Foundation
import ImageIO

/// The art's pictures (R3.2): drawn once from a PDF and saved, so the art shows without its PDF.
extension SharedLibrary {
    /// The longest side, in pixels, a picture is saved at.
    public static let pictureMaxPixels = 1024

    /// The art's picture, upright on a transparent background, at most `maxPixels` on its long side: the saved
    /// picture, or else one drawn from a PDF this app can reach. Nil when neither is there.
    public func picture(of entry: SharedArtEntry, maxPixels: Int = pictureMaxPixels) -> CGImage? {
        if let name = entry.picture, let image = Self.image(at: pictureFile(name), maxPixels: maxPixels) {
            try? markPicturesShown([name])
            return image
        }
        return drawnPicture(of: entry, maxPixels: maxPixels)
    }

    /// The name of the picture drawn from `print`. Art reads its picture's name from its row; this only tells
    /// whether a picture whose file is missing is one this device can draw again.
    static func pictureName(drawnFrom print: SharedPrint) -> String {
        "\(print.key.uuidString).heic"
    }

    /// True when the art can be shown: it has a picture, or a PDF printing it can be reached.
    public func isAvailable(_ entry: SharedArtEntry) -> Bool {
        if let name = entry.picture, FileManager.default.fileExists(atPath: pictureFile(name).path) { return true }
        let sources = (try? self.sources()) ?? []
        return entry.prints.contains { print in
            sources.first { $0.id == print.print.sourceID }.map { status(of: $0) == .available } == true
        }
    }

    /// Whether this app can reach a PDF.
    public func status(of source: SharedSource) -> SourceStatus {
        withFile(of: source) { _ in true } == true ? .available : .missing
    }

    /// Runs `body` with a PDF's file, as this app reaches it; nil when it can't.
    func withFile<Result>(of source: SharedSource, _ body: (URL) throws -> Result) rethrows -> Result? {
        guard let artSource = source.artSource(for: app) else { return nil }
        return try artSource.withFile(keptFile: keptFile(sourceID: source.id), body)
    }

    /// The figure a print shows, read from its PDF; nil when this app can't reach it.
    func figure(of print: ArtPrint) -> Figure? {
        guard let source = try? sources().first(where: { $0.id == print.sourceID }) else { return nil }
        let found: Figure?? = withFile(of: source) { url in
            guard let page = CGPDFDocument(url as CFURL)?.page(at: print.face.pageIndex + 1) else { return nil }
            return ArtLibrary.figure(of: print, among: PageScanner.images(on: page))
        }
        return found ?? nil
    }

    /// Draws the pictures a PDF's art needs from the PDF at `file`, a page per core, and records them. Returns how
    /// many it drew.
    @discardableResult
    func drawPictures(_ jobs: [PictureJob], from file: URL) throws -> Int {
        let pages = Array(Dictionary(grouping: jobs) { $0.print.print.face.pageIndex })
        let drawn = DrawnPictures()
        DispatchQueue.concurrentPerform(iterations: pages.count) { index in
            guard let page = CGPDFDocument(file as CFURL)?.page(at: pages[index].key + 1) else { return }
            let images = PageScanner.images(on: page)
            for job in pages[index].value {
                guard let figure = ArtLibrary.figure(of: job.print.print, among: images) else { continue }
                drawn.add(Result { DrawnPicture(job: job, picture: try writePicture(of: figure, print: job.print)) })
            }
        }
        let pictures = try drawn.pictures()
        let new = pictures.filter { !$0.job.isRedraw }
        guard !new.isEmpty else { return pictures.count }
        try write { writer in
            for drawn in new { try writer.setPicture(drawn.picture, ofArtPrinting: drawn.job.print.key) }
        }
        return pictures.count
    }

    // MARK: Helpers

    /// The art's picture drawn from the first of its prints this app can reach. It is saved when the art has no
    /// picture yet, or names the one that print gives, whose file is then back. A picture another print gave the
    /// art comes from iCloud: the drawing only stands in for it, or a blurrier one would pass for the sharp one
    /// under its name, be sent to iCloud, and never be replaced.
    private func drawnPicture(of entry: SharedArtEntry, maxPixels: Int) -> CGImage? {
        let own = entry.prints.filter { Self.pictureName(drawnFrom: $0) == entry.picture }
        for print in own + entry.prints.filter({ !own.contains($0) }) {
            guard let figure = figure(of: print.print) else { continue }
            guard entry.picture == nil || own.contains(print) else {
                return ArtLibrary.render(figure, rotation: print.print.face.rotation,
                                         maxPixels: min(maxPixels, Self.savedPixels(of: figure)))
            }
            let saved = try? savePicture(of: figure, for: PictureJob(print: print, isRedraw: entry.picture != nil))
            return saved.flatMap { Self.image(at: pictureFile($0.name), maxPixels: maxPixels) }
        }
        return nil
    }

    /// Draws the job's picture and gives it to the art, unless the art names it already.
    private func savePicture(of figure: Figure, for job: PictureJob) throws -> ArtPicture {
        let saved = try writePicture(of: figure, print: job.print)
        guard !job.isRedraw else { return saved }
        try write { writer in try writer.setPicture(saved, ofArtPrinting: job.print.key) }
        return saved
    }

    /// The long side a figure's picture is saved at: the size its PDF embeds it, at most `pictureMaxPixels`.
    private static func savedPixels(of figure: Figure) -> Int {
        min(pictureMaxPixels, max(figure.embeddedPixels, 1))
    }

    /// Saves a figure under the name its print gives it (`pictureName(drawnFrom:)`).
    private func writePicture(of figure: Figure, print: SharedPrint) throws -> ArtPicture {
        let name = Self.pictureName(drawnFrom: print)
        let pixels = Self.savedPixels(of: figure)
        guard let image = ArtLibrary.render(figure, rotation: print.print.face.rotation, maxPixels: pixels),
              let destination = CGImageDestinationCreateWithURL(pictureFile(name) as CFURL, "public.heic" as CFString,
                                                                1, nil) else {
            throw SharedLibraryError(operation: "Drawing \(name)", detail: "the picture couldn't be made")
        }
        let options = [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary
        CGImageDestinationAddImage(destination, image, options)
        guard CGImageDestinationFinalize(destination) else {
            throw SharedLibraryError(operation: "Saving \(name)", detail: "the HEIC encoder failed")
        }
        return ArtPicture(name: name, pixels: max(image.width, image.height))
    }

    private static func image(at url: URL, maxPixels: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                        kCGImageSourceThumbnailMaxPixelSize: maxPixels,
                                        kCGImageSourceCreateThumbnailWithTransform: true]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}

extension LibraryWriter {
    /// Records the picture of the art that has the print `key`, wherever merging has put it since.
    func setPicture(_ picture: ArtPicture, ofArtPrinting key: UUID) throws {
        try database.run("UPDATE art SET picture = ?, picturePixels = ?, changed = ? WHERE id = "
                         + "(SELECT entry FROM prints WHERE key = ?)",
                         [.text(picture.name), .integer(Int64(picture.pixels)), .integer(counter),
                          .text(key.uuidString)])
    }
}

/// A picture drawn for a job.
private struct DrawnPicture {
    var job: PictureJob
    var picture: ArtPicture
}

/// The pictures drawn on several threads at once, or the first failure.
private final class DrawnPictures: @unchecked Sendable {
    private let lock = NSLock()
    private var results: [Result<DrawnPicture, Error>] = []

    func add(_ result: Result<DrawnPicture, Error>) {
        lock.withLock { results.append(result) }
    }

    func pictures() throws -> [DrawnPicture] {
        try lock.withLock { try results.map { try $0.get() } }
    }
}
