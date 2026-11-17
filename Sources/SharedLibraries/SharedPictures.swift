import ArtExtraction
import CoreGraphics
import Foundation
import ImageIO

/// The art's pictures (R3.2): drawn once from a PDF and saved, so the art shows without its PDF.
extension SharedLibrary {
    /// The longest side, in pixels, a picture is saved at.
    public static let pictureMaxPixels = 1024

    /// The art's picture, upright on a transparent background, at most `maxPixels` on its long side: the saved
    /// picture, or else one drawn from a PDF this app can reach, then saved. Nil when neither is there.
    public func picture(of entry: SharedArtEntry, maxPixels: Int = pictureMaxPixels) -> CGImage? {
        if let name = entry.picture, let image = Self.image(at: pictureFile(name), maxPixels: maxPixels) {
            return image
        }
        for print in entry.prints {
            guard let figure = figure(of: print.print) else { continue }
            let drawn = try? savePicture(of: figure, print: print)
            return drawn.flatMap { Self.image(at: pictureFile($0), maxPixels: maxPixels) }
        }
        return nil
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

    /// Draws the pictures a PDF's art needs from the PDF at `file`, a page per core, and records them.
    func drawPictures(_ jobs: [PictureJob], from file: URL) throws {
        let pages = Array(Dictionary(grouping: jobs) { $0.print.print.face.pageIndex })
        let drawn = DrawnPictures()
        DispatchQueue.concurrentPerform(iterations: pages.count) { index in
            guard let page = CGPDFDocument(file as CFURL)?.page(at: pages[index].key + 1) else { return }
            let images = PageScanner.images(on: page)
            for job in pages[index].value {
                guard let figure = ArtLibrary.figure(of: job.print.print, among: images) else { continue }
                drawn.add(Result { (job.print.key, try writePicture(of: figure, print: job.print)) })
            }
        }
        let pictures = try drawn.pictures()
        guard !pictures.isEmpty else { return }
        try write { writer in
            for (key, name) in pictures { try writer.setPicture(name, ofArtPrinting: key) }
        }
    }

    // MARK: Helpers

    private func savePicture(of figure: Figure, print: SharedPrint) throws -> String {
        let name = try writePicture(of: figure, print: print)
        try write { writer in try writer.setPicture(name, ofArtPrinting: print.key) }
        return name
    }

    /// Saves a figure as `<key>.heic`, at the size its PDF embeds it, at most `pictureMaxPixels`.
    private func writePicture(of figure: Figure, print: SharedPrint) throws -> String {
        let name = "\(print.key.uuidString).heic"
        let pixels = min(Self.pictureMaxPixels, max(figure.embeddedPixels, 1))
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
        return name
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
    func setPicture(_ name: String, ofArtPrinting key: UUID) throws {
        try database.run("UPDATE art SET picture = ?, changed = ? WHERE id = (SELECT entry FROM prints WHERE key = ?)",
                         [.text(name), .integer(counter), .text(key.uuidString)])
    }
}

/// The pictures drawn on several threads at once: each print's key and picture, or the first failure.
private final class DrawnPictures: @unchecked Sendable {
    private let lock = NSLock()
    private var results: [Result<(UUID, String), Error>] = []

    func add(_ result: Result<(UUID, String), Error>) {
        lock.withLock { results.append(result) }
    }

    func pictures() throws -> [(UUID, String)] {
        try lock.withLock { try results.map { try $0.get() } }
    }
}
