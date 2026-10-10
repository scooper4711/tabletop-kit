import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Copies the cards' UI art from the user's Rexard packs into an app's folder (`CardArtPieces.manifest`), so it
/// ships inside the app and nowhere else.
public enum CardArtCopier {
    /// Pieces larger than this on their long side are scaled down: the cards never draw them larger.
    public static let largestSide = 1600

    /// Copies every piece found under `packs` into `folder` as `<name>.png`; returns the pieces it couldn't find.
    @discardableResult
    public static func copy(from packs: URL, to folder: URL) throws -> [CardArtPieces.Piece] {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var missing: [CardArtPieces.Piece] = []
        for piece in CardArtPieces.manifest {
            guard let source = find(piece.packPath, in: packs),
                  let image = CGImageSourceCreateWithURL(source as CFURL, nil).flatMap(scaledImage)
            else {
                missing.append(piece)
                continue
            }
            try write(image, to: folder.appendingPathComponent(piece.name + ".png"))
        }
        return missing
    }

    /// The file at `path` under `root`, matching each part of the path without regard to case, as the packs mix
    /// ".png" and ".PNG".
    static func find(_ path: String, in root: URL) -> URL? {
        var url = root
        for part in path.split(separator: "/").map(String.init) {
            let names = (try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []
            guard let name = names.first(where: { $0.caseInsensitiveCompare(part) == .orderedSame }) else { return nil }
            url.appendPathComponent(name)
        }
        return url
    }

    private static func scaledImage(_ source: CGImageSource) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: largestSide
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    private static func write(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1,
                                                                nil) else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: url.path])
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: url.path])
        }
    }
}
