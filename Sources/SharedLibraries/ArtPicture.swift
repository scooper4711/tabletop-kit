import Foundation
import ImageIO

/// An art's picture: its file's name in the `Pictures` folder and its long side in pixels, 0 when the picture was
/// saved before sizes were kept.
struct ArtPicture: Equatable, Sendable {
    var name: String
    var pixels: Int

    /// True when this picture stays over `other`, on every device alike: the sharper one, or of two as sharp the
    /// one whose name sorts first (library sync design, "Pictures").
    func stays(over other: ArtPicture) -> Bool {
        pixels == other.pixels ? name <= other.name : pixels > other.pixels
    }
}

extension SharedArtEntry {
    /// Its picture with its size; nil without one.
    var artPicture: ArtPicture? {
        get { picture.map { ArtPicture(name: $0, pixels: picturePixels) } }
        set {
            picture = newValue?.name
            picturePixels = newValue?.pixels ?? 0
        }
    }

    /// Takes the picture that stays among its own and those of `known`, the art it joins.
    mutating func keepSharpestPicture(among known: [SharedArtEntry]) {
        for candidate in known.compactMap(\.artPicture) {
            if let kept = artPicture, kept.stays(over: candidate) { continue }
            artPicture = candidate
        }
    }
}

/// How sharp the saved pictures are.
extension SharedLibrary {
    /// Notes the size of every picture art names whose size isn't known and whose file is here: those saved before
    /// sizes were kept. Returns how many pieces of art it noted. Sync calls it before it first sends, so two
    /// devices settle on the sharper picture.
    @discardableResult
    public func measurePictures() throws -> Int {
        let unsized = try connection().rows("SELECT id, picture FROM art WHERE picture IS NOT NULL "
                                            + "AND picturePixels = 0 ORDER BY id")
        let measured = unsized.compactMap { row -> (id: String, picture: ArtPicture)? in
            guard let id = row.text("id"), let name = row.text("picture") else { return nil }
            let pixels = pixels(ofPicture: name)
            return pixels > 0 ? (id, ArtPicture(name: name, pixels: pixels)) : nil
        }
        guard !measured.isEmpty else { return 0 }
        try write { writer in
            for art in measured {
                // Only while the art still names the picture measured: another app may have given it another since.
                try writer.database.run("UPDATE art SET picturePixels = ?, changed = ? WHERE id = ? AND picture = ?",
                                        [.integer(Int64(art.picture.pixels)), .integer(writer.counter),
                                         .text(art.id), .text(art.picture.name)])
            }
        }
        return measured.count
    }

    /// The long side, in pixels, of the picture `name` in the `Pictures` folder; 0 when it isn't there or can't be
    /// read. Only the file's header is read.
    func pixels(ofPicture name: String) -> Int {
        guard let source = CGImageSourceCreateWithURL(pictureFile(name) as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return 0
        }
        let width = properties[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = properties[kCGImagePropertyPixelHeight] as? Int ?? 0
        return max(width, height)
    }
}
