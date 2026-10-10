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
}

/// What a piece of art is printed as.
public enum ArtKind: String, Codable, Sendable, Comparable {
    /// A creature on a Battle Card, or a pawn printed without a cut outline: its picture alone.
    case figure
    /// A pawn in its cut outline.
    case pawn
    /// A round token's art.
    case token

    /// Figures come first: their pictures are the sharpest.
    public static func < (lhs: ArtKind, rhs: ArtKind) -> Bool {
        lhs.order < rhs.order
    }

    private var order: Int {
        switch self {
        case .figure: 0
        case .pawn: 1
        case .token: 2
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
}

/// One piece of creature art, with every product that prints it, its sharpest print first.
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
}
