import ArtExtractionTestSupport
import CoreGraphics
import Foundation
import ImageIO

/// The pictures the demo PDFs use: the Iconics and the religious and faction symbols from Paizo's Community Use
/// Package when its folder is given, else drawn stand-ins, so the tool runs in tests and on CI.
public struct DemoArt {
    /// An Iconic: its name, such as "Valeros", its class, and its transparent full-body painting.
    public struct Iconic {
        public let name: String
        public let role: String
        public let image: CGImage
    }

    public private(set) var iconics: [Iconic] = []
    /// Religious and faction symbols.
    public private(set) var symbols: [CGImage] = []

    /// The art in the Community Use Package's folder, or stand-ins when `folder` is nil or holds none.
    public init(communityUseFolder folder: URL?) {
        if let folder {
            iconics = Self.iconics(in: folder.appendingPathComponent("Community Use Package- Iconics"))
            symbols = Self.images(in: folder.appendingPathComponent("Community Use Package- Religious Symbols"))
                + Self.images(in: folder.appendingPathComponent("Community Use Package- Faction Symbols"))
        }
        if iconics.isEmpty {
            iconics = ["Valeros", "Kyra", "Merisiel", "Ezren", "Amiri", "Lem"].enumerated().map { index, name in
                Iconic(name: name, role: "Hero", image: creatureArt(variant: index, scale: 4))
            }
        }
        if symbols.isEmpty { symbols = (0..<4).map { tokenArt(variant: $0) } }
    }

    /// The Iconic at `index`, wrapping around.
    func iconic(_ index: Int) -> Iconic {
        iconics[index % iconics.count]
    }

    /// "Fighter - Valeros.png" names Valeros, a Fighter; only PNGs, which are transparent.
    private static func iconics(in folder: URL) -> [Iconic] {
        files(in: folder, extension: "png").compactMap { file in
            let parts = file.deletingPathExtension().lastPathComponent.components(separatedBy: " - ")
            guard parts.count == 2, let image = image(at: file, maxPixels: 600) else { return nil }
            return Iconic(name: parts[1], role: parts[0], image: image)
        }
    }

    private static func images(in folder: URL) -> [CGImage] {
        files(in: folder, extension: "png").prefix(12).compactMap { image(at: $0, maxPixels: 300) }
    }

    private static func files(in folder: URL, extension: String) -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.filter { $0.lowercased().hasSuffix("." + `extension`) }.sorted()
            .map { folder.appendingPathComponent($0) }
    }

    /// The image scaled down so its longer side is at most `maxPixels`, keeping the files small.
    static func image(at file: URL, maxPixels: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(file as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                        kCGImageSourceThumbnailMaxPixelSize: maxPixels,
                                        kCGImageSourceCreateThumbnailWithTransform: true]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
