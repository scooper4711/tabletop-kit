import ArtExtraction
import Foundation

/// A PDF in the shared art library. Where it is depends on the app: a kept PDF is in the library's `Sources`
/// folder for every app, a referenced one only reachable by the apps that were given access to it (R3.6).
public struct SharedSource: Identifiable, Hashable, Sendable {
    /// SHA-256 of the file.
    public let id: String
    public var title: String
    public var game: GameSystem
    public var byteCount: Int
    public var readerVersion: Int
    public var artFound: Int
    public var isKept: Bool
    /// How each app reaches the PDF when it isn't kept.
    public var access: [TablesideApp: SourceLocation]

    /// The source as `app` reaches it; nil when `app` can't reach it.
    public func artSource(for app: TablesideApp) -> ArtSource? {
        guard let location = isKept ? .kept : access[app] else { return nil }
        return ArtSource(id: id, title: title, game: game, location: location, byteCount: byteCount,
                         readerVersion: readerVersion, artFound: artFound)
    }
}

/// Where one product prints a piece of art, with its key (R2).
public struct SharedPrint: Hashable, Sendable {
    public var key: UUID
    /// For tokens and items drawn at import, `tokenFile` names the picture in the library's `Pictures` folder.
    public var print: ArtPrint
    /// The pawn's back, when it has one of its own.
    public var back: PawnFace?

    public init(key: UUID, print: ArtPrint, back: PawnFace? = nil) {
        self.key = key
        self.print = print
        self.back = back
    }
}

/// One piece of art in the shared art library, with every print and its key.
public struct SharedArtEntry: Identifiable, Hashable, Sendable {
    /// The first print's key, pawns first (R2.5; `ArtKey.entryID(among:)`).
    public var id: UUID
    public var name: String
    public var game: GameSystem
    public var size: PawnSize
    public var traits: [String]
    public var fingerprint: ArtFingerprint
    public var palette: [Double]
    /// Its prints, figures first (the sharpest), then by key.
    public var prints: [SharedPrint]
    /// Its picture's file in the library's `Pictures` folder (R3.2), once drawn.
    public var picture: String?

    /// The entry with its prints' keys left out, as the apps' art library holds it.
    public var artEntry: ArtEntry {
        ArtEntry(id: id, name: name, game: game, size: size, traits: traits, fingerprint: fingerprint,
                 prints: prints.map(\.print), palette: palette)
    }

    /// The entry `entry`, with `prints` in place of its own and its picture's file, keeping `entry`'s ID.
    public init(_ entry: ArtEntry, prints: [SharedPrint], picture: String? = nil) {
        self.init(entry, keys: [])
        self.prints = prints
        self.picture = picture
        sortPrints()
    }

    /// The entry `entry` with each print's key, in order.
    init(_ entry: ArtEntry, keys: [UUID]) {
        id = entry.id
        name = entry.name
        game = entry.game
        size = entry.size
        traits = entry.traits
        fingerprint = entry.fingerprint
        palette = entry.palette
        prints = zip(entry.prints, keys).map { SharedPrint(key: $1, print: $0) }
    }

    /// Puts the prints in order: figures first, then by key.
    mutating func sortPrints() {
        prints.sort { first, second in
            first.print.kind == second.print.kind ? first.key.uuidString < second.key.uuidString
                                                  : first.print.kind < second.print.kind
        }
    }

    /// The ID its prints give it, or its own without prints.
    var keyedID: UUID {
        ArtKey.entryID(among: prints.map { (kind: $0.print.kind, key: $0.key) }) ?? id
    }
}

/// The art library's sources and art.
extension SharedLibrary {
    /// Every PDF in the library.
    public func sources() throws -> [SharedSource] {
        try ArtRows.sources(in: try connection())
    }

    /// The art added or changed after `counter`, with all its prints; all of it by default.
    public func artEntries(changedSince counter: Int64 = 0) throws -> [SharedArtEntry] {
        try ArtRows.entries(in: try connection(), where: "changed > ? OR id IN "
                            + "(SELECT entry FROM prints WHERE changed > ?)", [.integer(counter), .integer(counter)])
    }

    /// The art with ID `id`, found by its ID, one of its prints' keys, or an alias (R2.5, R2.7).
    public func artEntry(id: UUID) throws -> SharedArtEntry? {
        let database = try connection()
        guard let entryID = try ArtRows.entryID(answeringTo: id, in: database) else { return nil }
        return try ArtRows.entries(in: database, where: "id = ?", [.text(entryID.uuidString)]).first
    }

    /// Where a kept PDF is.
    public func keptFile(sourceID: String) -> URL {
        sourcesFolder.appending(path: "\(sourceID).pdf")
    }

    /// Where a picture in the `Pictures` folder is, such as a token's (`ArtPrint.tokenFile`).
    public func pictureFile(_ name: String) -> URL {
        picturesFolder.appending(path: name)
    }
}
