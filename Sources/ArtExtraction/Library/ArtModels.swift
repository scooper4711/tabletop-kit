import CoreGraphics
import Foundation

/// The game a product belongs to, read from its title.
public enum GameSystem: String, Codable, CaseIterable, Sendable {
    case pathfinder, starfinder

    public init(title: String) {
        self = title.localizedCaseInsensitiveContains("Starfinder") ? .starfinder : .pathfinder
    }
}

/// Where a PDF in the art library is.
public enum SourceLocation: Codable, Hashable, Sendable {
    /// A copy in the library's folder, so the art survives the original being moved.
    case kept
    /// The file where it is, remembered by a bookmark, without copying it.
    case referenced(FileReference)
    /// A file in a watched folder (`ArtLibrary.watch`), at a path inside it, without copying it: access to a file
    /// found in a folder chosen on the iPad comes from the folder.
    case inFolder(FileReference, relativePath: String)
}

/// Whether a PDF's art can be drawn.
public enum SourceStatus: Equatable, Sendable {
    case available
    /// The file was deleted, moved where its bookmark can't follow, or can't be opened.
    case missing
}

/// A PDF in the art library.
public struct ArtSource: Codable, Identifiable, Hashable, Sendable {
    /// SHA-256 of the file, so the same PDF is recognized wherever it is.
    public let id: String
    public var title: String
    public var game: GameSystem
    public var location: SourceLocation
    /// The file's size when added, to recognize it again without hashing it.
    public var byteCount: Int
    /// The `PawnExtractor.version` that read it.
    public var readerVersion: Int
    /// How many pieces of art reading it found.
    public var artFound: Int

    public init(id: String, title: String, game: GameSystem, location: SourceLocation, byteCount: Int,
                readerVersion: Int, artFound: Int) {
        self.id = id
        self.title = title
        self.game = game
        self.location = location
        self.byteCount = byteCount
        self.readerVersion = readerVersion
        self.artFound = artFound
    }
}

/// What a piece of art is printed as.
public enum ArtKind: String, Codable, Sendable, Comparable {
    /// A creature on a Battle Card, or a pawn printed without a cut outline: its picture alone.
    case figure
    /// A pawn in its cut outline.
    case pawn
    /// A round token's art.
    case token
    /// An item on an item deck's card, drawn as a figure is.
    case item

    /// Figures come first: their pictures are the sharpest.
    public static func < (lhs: ArtKind, rhs: ArtKind) -> Bool {
        lhs.order < rhs.order
    }

    private var order: Int {
        switch self {
        case .figure: 0
        case .pawn: 1
        case .token: 2
        case .item: 3
        }
    }
}

/// Where one product prints a piece of art.
public struct ArtPrint: Codable, Hashable, Sendable {
    public var sourceID: String
    public var kind: ArtKind
    /// The art's place on its page, and how to turn it upright.
    public var face: PawnFace
    /// For figures: the picture's index among the images its page draws.
    public var imageIndex: Int?
    /// For tokens: the token's art drawn alone at import, a file in the library's `Tokens` folder.
    public var tokenFile: String?
    /// How many copies the product prints.
    public var copies: Int

    public init(sourceID: String, kind: ArtKind, face: PawnFace, imageIndex: Int? = nil, tokenFile: String? = nil,
                copies: Int) {
        self.sourceID = sourceID
        self.kind = kind
        self.face = face
        self.imageIndex = imageIndex
        self.tokenFile = tokenFile
        self.copies = copies
    }
}

/// One piece of creature or item art, with every product that prints it, its sharpest print first.
public struct ArtEntry: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public var game: GameSystem
    public var size: PawnSize
    /// The creature's traits, from a Battle Card.
    public var traits: [String]
    public var fingerprint: ArtFingerprint
    public var prints: [ArtPrint]
    /// The colors of the art's figure (see `Figure.palette`), once measured to compare it with art of the same
    /// name; empty until then.
    public var palette: [Double]

    public init(id: UUID, name: String, game: GameSystem, size: PawnSize, traits: [String],
                fingerprint: ArtFingerprint, prints: [ArtPrint], palette: [Double]) {
        self.id = id
        self.name = name
        self.game = game
        self.size = size
        self.traits = traits
        self.fingerprint = fingerprint
        self.prints = prints
        self.palette = palette
    }

    /// True for an item's art, from an item deck, rather than a creature's.
    public var isItem: Bool { prints.contains { $0.kind == .item } }
}

/// What adding a PDF to the art library found.
public struct ArtImportReport: Equatable, Sendable {
    public var sourceTitle: String
    /// New pieces of art.
    public var added = 0
    /// Art already in the library from another product, now printed by this one too.
    public var alreadyKnown = 0
    /// Art with no name printed, left out.
    public var unnamed = 0
    /// Pages printed as one flattened picture (zero-based).
    public var unreadablePages: [Int] = []
    /// True when the PDF was in the library already, so nothing changed.
    public var wasImported = false
    /// True when another app is reading the PDF into a shared library: its art arrives with that app's change.
    public var isReadByAnotherApp = false

    public init(sourceTitle: String, unreadablePages: [Int] = []) {
        self.sourceTitle = sourceTitle
        self.unreadablePages = unreadablePages
    }
}

extension ArtPrint {
    /// Where `found` is printed in the PDF `sourceID`. A token's or drawn item's picture is kept in the file
    /// `pictureFile` (`ExtractedPawn.keptPicture`).
    public init(found: ExtractedPawn, sourceID: String, pictureFile: String?) {
        let kind: ArtKind, imageIndex: Int?
        switch found.shape {
        case .pawn: (kind, imageIndex) = (.pawn, nil)
        case .card(let index): (kind, imageIndex) = (.figure, index)
        case .item(let index): (kind, imageIndex) = (.item, index)
        case .drawnItem: (kind, imageIndex) = (.item, nil)
        case .token: (kind, imageIndex) = (.token, nil)
        }
        self.init(sourceID: sourceID, kind: kind, face: found.front, imageIndex: imageIndex, tokenFile: pictureFile,
                  copies: found.copies)
    }
}

extension ExtractedPawn {
    /// The picture drawn at import that the library keeps, as PNG: a token's art, or an item cut out of a card
    /// printed as a picture.
    public var keptPicture: Data? {
        switch shape {
        case .token(let pictures): pictures.front
        case .drawnItem(let png): png
        case .pawn, .card, .item: nil
        }
    }
}

extension ArtSource {
    /// Runs `body` with the PDF's file and access to it, a kept PDF being `keptFile`; nil when it is missing.
    public func withFile<Result>(keptFile: URL, _ body: (URL) throws -> Result) rethrows -> Result? {
        switch location {
        case .kept:
            return FileManager.default.fileExists(atPath: keptFile.path) ? try body(keptFile) : nil
        case .referenced(let reference):
            return try reference.withAccess(body)
        case .inFolder(let reference, let relativePath):
            let found = try reference.withAccess { folder -> Result? in
                let url = folder.appendingPathComponent(relativePath)
                return FileManager.default.isReadableFile(atPath: url.path) ? try body(url) : nil
            }
            return found ?? nil
        }
    }
}
