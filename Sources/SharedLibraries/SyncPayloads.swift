import ArtExtraction
import Foundation

// What a record holds, as JSON. Fields are only ever added, as optionals, and a missing field keeps the local
// value (library sync design). Dates are seconds since the reference date.

/// One PDF's whole reading: its prints, the art they belong to, and that art's aliases.
struct SourceReading: Codable, Equatable {
    var id: String
    var title: String
    var game: GameSystem
    var byteCount: Int
    var readerVersion: Int
    var artFound: Int
    /// By `entry`.
    var groups: [ReadingGroup]
}

/// One piece of art, as far as this PDF prints it.
struct ReadingGroup: Codable, Equatable {
    /// The art's ID on the sender.
    var entry: UUID
    var name: String
    var game: GameSystem
    var size: PawnSize
    var traits: [String]
    var fingerprint: ArtFingerprint
    var palette: [Double]
    var picture: String?
    var needsName: Bool
    /// Every print key of the art, from any PDF, sorted: how art the sender had as one piece becomes one piece.
    var keys: [UUID]
    /// This PDF's prints, by key.
    var prints: [ReadingPrint]
    /// By `oldID`.
    var aliases: [ReadingAlias]
}

struct ReadingPrint: Codable, Equatable {
    var key: UUID
    var kind: ArtKind
    var front: PawnFace
    var back: PawnFace?
    var imageIndex: Int?
    var picture: String?
    var backPicture: String?
    var copies: Int
}

struct ReadingAlias: Codable, Equatable {
    var oldID: UUID
    var app: TablesideApp
}

struct NotePayload: Codable, Equatable {
    var entry: UUID
    var userName: String?
    var tags: [String]
    var tagModel: String
    var suggestedName: String
    var corrected: Bool
    var modified: Double
}

struct CreatureArtPayload: Codable, Equatable {
    var subject: String
    var entry: UUID?
    var customArt: UUID?
    var modified: Double
}

struct CustomCreaturePayload: Codable, Equatable {
    var id: UUID
    var campaign: UUID?
    var sharedVersion: Double?
    var record: Data
    var modified: Double
}

struct CustomArtPayload: Codable, Equatable {
    var id: UUID
    var file: String
    var sharedVersion: Double?
    var record: Data
    var modified: Double
}

/// Encoding payloads one way, so a content digest means the same on every device and version.
enum SyncPayloads {
    /// The canonical JSON of `payload`: keys sorted.
    static func encode(_ payload: some Encodable) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(payload)
    }

    static func decode<Payload: Decodable>(_ type: Payload.Type, from data: Data, kind: SyncKind) throws -> Payload {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw SharedLibraryError(operation: "Reading a \(kind.rawValue) record", detail: "\(error)")
        }
    }

    /// True when this version can read a saved record. A newer app may have written what this one doesn't know.
    static func isReadable(_ change: RemoteChange) -> Bool {
        guard case .saved(let record, _) = change else { return true }
        return (try? digest(ofIncoming: record.payload, kind: record.id.kind)) != nil
    }

    /// The digest of `data` as this version encodes it: decoded and encoded again, never the bytes as they came,
    /// or two versions that add different fields would upload over each other for ever.
    static func digest(ofIncoming data: Data, kind: SyncKind) throws -> String {
        switch kind {
        case .source: SyncDigest.hex(of: try encode(try decode(SourceReading.self, from: data, kind: kind)))
        case .note: SyncDigest.hex(of: try encode(try decode(NotePayload.self, from: data, kind: kind)))
        case .creatureArt: SyncDigest.hex(of: try encode(try decode(CreatureArtPayload.self, from: data, kind: kind)))
        case .customCreature:
            SyncDigest.hex(of: try encode(try decode(CustomCreaturePayload.self, from: data, kind: kind)))
        case .customArt: SyncDigest.hex(of: try encode(try decode(CustomArtPayload.self, from: data, kind: kind)))
        }
    }
}
