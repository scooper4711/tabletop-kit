import Bestiary
import CoreGraphics
import Foundation
import ImageIO
import SwiftUI
import Testing
import UniformTypeIdentifiers
@testable import BattleCards

@Suite("Copying the card art from the packs")
struct CardArtCopierTests {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("CardArtTests-\(UUID())")

    /// A pack folder with every piece but the last, some named in other cases, one of them too large.
    func writePacks() throws -> URL {
        let packs = folder.appendingPathComponent("packs")
        for (index, piece) in CardArtPieces.manifest.dropLast().enumerated() {
            var path = piece.packPath
            if index.isMultiple(of: 3) { path = path.uppercased() }
            let url = packs.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try writePNG(side: index == 0 ? 2000 : 8, to: url)
        }
        return packs
    }

    @Test("Each piece is copied by name, scaled down when large, and the missing ones listed")
    func copiesThePieces() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let output = folder.appendingPathComponent("CardArt")
        let missing = try CardArtCopier.copy(from: try writePacks(), to: output)
        #expect(missing == [CardArtPieces.manifest.last!])
        let pieces = CardArtPieces(folder: output)
        #expect(pieces.image(CardArtPieces.manifest[1].name) != nil)
        #expect(pieces.image(CardArtPieces.manifest.last!.name) == nil)
        let first = output.appendingPathComponent(CardArtPieces.manifest[0].name + ".png")
        let size = CGImageSourceCreateWithURL(first as CFURL, nil)
            .flatMap { CGImageSourceCopyPropertiesAtIndex($0, 0, nil) as? [CFString: Any] }
        #expect(size?[kCGImagePropertyPixelWidth] as? Int == CardArtCopier.largestSide)
    }

    @Test("Without pieces there is no art to draw")
    func noFolder() {
        #expect(CardArtPieces(folder: nil).image("parchment") == nil)
    }
}
