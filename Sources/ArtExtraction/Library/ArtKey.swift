import CoreGraphics
import CryptoKit
import Foundation

/// What a piece of art's key is made from: how one PDF prints it.
public struct ArtKeyInput: Hashable, Sendable {
    /// The PDF's SHA-256 (`ArtSource.id`).
    public var sourceID: String
    public var name: String
    public var size: PawnSize
    public var fingerprint: ArtFingerprint
    public var face: PawnFace

    public init(sourceID: String, name: String, size: PawnSize, fingerprint: ArtFingerprint, face: PawnFace) {
        self.sourceID = sourceID
        self.name = name
        self.size = size
        self.fingerprint = fingerprint
        self.face = face
    }
}

/// The IDs every app on every device gives the art in a PDF the same way (shared libraries R2): name-based UUIDs of
/// the pictures Paizo embedded and the art's name, or, for art without pictures of its own, of its place on the page.
/// The names hashed are the contract, written out in `docs/specs/shared-libraries/design.md`.
public enum ArtKey {
    public static let namespace = UUID(uuidString: "2A674007-7209-4190-AA36-612838B41B5F")!
    /// The grid, in points, that places art without pictures: about 1/20 of a Letter page.
    static let placeGridPoints: CGFloat = 30

    /// Each print's key, in order. Prints of one PDF that share a picture and name but differ in size add their
    /// size.
    public static func keys(for prints: [ArtKeyInput]) -> [UUID] {
        keyNames(for: prints).map { nameBasedUUID($0) }
    }

    /// The key of the entry printed by `prints`: the first by kind, pawns before tokens, figures and items, so a
    /// pawn keeps its key when a Battle Card adds a sharper picture; then by the key's text. Nil without prints.
    public static func entryID(among prints: [(kind: ArtKind, key: UUID)]) -> UUID? {
        prints.min { first, second in
            first.kind == second.kind ? first.key.uuidString < second.key.uuidString
                                      : entryOrder(first.kind) < entryOrder(second.kind)
        }?.key
    }

    /// A name compared without case, accents, spaces or punctuation: "Demon,brimorak" is "Demon, Brimorak".
    public static func foldedName(_ name: String) -> String {
        let folded = name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).lowercased()
        return String(String.UnicodeScalarView(folded.unicodeScalars.filter(CharacterSet.alphanumerics.contains)))
    }

    /// A version 5 UUID (RFC 9562): SHA-1 of the namespace's bytes followed by `name` in UTF-8.
    public static func nameBasedUUID(_ name: String, namespace: UUID = namespace) -> UUID {
        let namespaceBytes = withUnsafeBytes(of: namespace.uuid) { Array($0) }
        var bytes = Array(Insecure.SHA1.hash(data: namespaceBytes + Array(name.utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: bytes.withUnsafeBytes { $0.load(as: uuid_t.self) })
    }

    /// The names hashed into each print's key.
    static func keyNames(for prints: [ArtKeyInput]) -> [String] {
        let sized = picturesPrintedInSeveralSizes(prints)
        var names = prints.map { print -> String in
            guard !print.fingerprint.imageDigests.isEmpty else { return placeName(of: print) }
            let name = pictureName(of: print)
            return sized.contains(sourced(name, print)) ? "\(name)|\(print.size.rawValue)" : name
        }
        numberSharedPlaces(&names, prints: prints)
        return names
    }

    // MARK: Helpers

    private static func pictureName(of print: ArtKeyInput) -> String {
        "image:\(print.fingerprint.imageDigests.joined(separator: ","))|\(foldedName(print.name))"
    }

    private static func placeName(of print: ArtKeyInput) -> String {
        let column = Int((print.face.rect.midX / placeGridPoints).rounded())
        let row = Int((print.face.rect.midY / placeGridPoints).rounded())
        return "place:\(print.sourceID)|\(print.face.pageIndex)|\(column),\(row)"
    }

    /// A picture name within its PDF.
    private static func sourced(_ name: String, _ print: ArtKeyInput) -> String {
        "\(print.sourceID)\n\(name)"
    }

    /// The picture names, within their PDFs, that a PDF prints in more than one size.
    private static func picturesPrintedInSeveralSizes(_ prints: [ArtKeyInput]) -> Set<String> {
        var sizes: [String: Set<PawnSize>] = [:]
        for print in prints where !print.fingerprint.imageDigests.isEmpty {
            sizes[sourced(pictureName(of: print), print), default: []].insert(print.size)
        }
        return Set(sizes.filter { $0.value.count > 1 }.keys)
    }

    /// Places shared by several pieces of art add `#2`, `#3` in reading order: top to bottom, then left to right.
    private static func numberSharedPlaces(_ names: inout [String], prints: [ArtKeyInput]) {
        let placed = names.indices.filter { names[$0].hasPrefix("place:") }
        for indices in Dictionary(grouping: placed, by: { names[$0] }).values where indices.count > 1 {
            let ordered = indices.sorted { first, second in
                let one = prints[first].face.rect, other = prints[second].face.rect
                if one.midY != other.midY { return one.midY > other.midY }
                return one.midX == other.midX ? first < second : one.midX < other.midX
            }
            for (rank, index) in ordered.enumerated().dropFirst() { names[index] += "#\(rank + 1)" }
        }
    }

    private static func entryOrder(_ kind: ArtKind) -> Int {
        switch kind {
        case .pawn: 0
        case .token: 1
        case .figure: 2
        case .item: 3
        }
    }
}

/// What a document saves to point at extracted art (shared libraries R2.8): its ID, and what to call it on a device
/// without it. Never the art itself (R2.9).
public struct ArtReference: Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    /// The title of the product the art came from.
    public var product: String

    public init(id: UUID, name: String, product: String) {
        self.id = id
        self.name = name
        self.product = product
    }

    /// What is missing: "Goblin Warrior, from Monster Core Pawn Box", or the name alone without a product.
    public var missingDescription: String {
        product.isEmpty ? name : "\(name), from \(product)"
    }
}
