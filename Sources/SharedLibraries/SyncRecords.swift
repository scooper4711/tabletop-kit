import ArtExtraction
import Foundation

/// The kinds of record the library syncs, in the order fetched records are applied: a source brings the art
/// everything else points at.
public enum SyncKind: String, CaseIterable, Codable, Sendable {
    case source, customArt, customCreature, creatureArt, note
}

/// The CloudKit zones the library's records live in.
public enum SyncZone {
    /// The rows, synced by the engine.
    public static let library = "Library"
    /// One asset per picture, fetched on demand and never by the engine.
    public static let pictures = "Pictures"
}

/// A record's identity in the cloud: its kind and its name, such as `note-<entry UUID>`.
public struct SyncRecordID: Hashable, Sendable {
    public var kind: SyncKind
    public var name: String

    public init(kind: SyncKind, name: String) {
        self.kind = kind
        self.name = name
    }
}

/// A record as it travels between a library and the cloud.
public struct SyncRecord: Equatable, Sendable {
    public var id: SyncRecordID
    /// The canonical JSON of the kind's payload.
    public var payload: Data
    /// What a person reading the CloudKit Console sees to tell records apart.
    public var title: String
    /// Custom art's image.
    public var file: URL?

    public init(id: SyncRecordID, payload: Data, title: String, file: URL? = nil) {
        self.id = id
        self.payload = payload
        self.title = title
        self.file = file
    }
}

/// A record to upload, with what `markSent` needs to remember afterwards.
public struct OutgoingRecord: Sendable {
    public var record: SyncRecord
    /// The server's fields for the record when this device knows it, so the save is a change to it.
    public var systemFields: Data?
    /// The record's change counter when it was built: a change made while it was in flight is still to upload.
    public var changed: Int64
    /// The SHA-256 of the record's content.
    public var digest: String
    /// The key of the local row the record is made from.
    public var rowKey: String
}

/// A change another device made, as the server reported it.
public enum RemoteChange: Sendable {
    case saved(SyncRecord, systemFields: Data)
    case deleted(SyncRecordID)
}

/// What a device has to send: the records to save and those to delete.
public struct SyncCandidates: Equatable, Sendable {
    public var saves: [SyncRecordID] = []
    public var deletions: [SyncRecordID] = []

    public var isEmpty: Bool { saves.isEmpty && deletions.isEmpty }
}

/// What `applyRemote` did with a batch of changes.
public struct RemoteApplyReport: Equatable, Sendable {
    /// Records merged into the library.
    public var applied = 0
    /// Records kept aside: notes until the art they are about arrives, and what this version can't read.
    public var parked = 0
    /// Records the library had already, whose fields were only noted.
    public var unchanged = 0
}

/// How records are named: a prefix for the kind and the key of the row they are made from.
enum SyncRecordName {
    /// The record name of the row `rowKey` of `kind`. A creature's subject can hold any character, so its record
    /// is named by the SHA-256 of the subject.
    static func make(_ kind: SyncKind, rowKey: String) -> String {
        prefix(of: kind) + (kind == .creatureArt ? SyncDigest.hex(of: Data(rowKey.utf8)) : rowKey)
    }

    /// The key of the row a record is made from, except for creature art, whose subject its name hides.
    static func rowKey(of id: SyncRecordID) -> String? {
        guard id.kind != .creatureArt, id.name.hasPrefix(prefix(of: id.kind)) else { return nil }
        return String(id.name.dropFirst(prefix(of: id.kind).count))
    }

    private static func prefix(of kind: SyncKind) -> String {
        switch kind {
        case .source: "source-"
        case .note: "note-"
        case .customCreature: "creature-"
        case .customArt: "customArt-"
        case .creatureArt: "creatureArt-"
        }
    }
}

/// SHA-256 as lowercase hexadecimal, for content digests and names.
enum SyncDigest {
    static func hex(of data: Data) -> String {
        ContentDigest.hex(of: data)
    }
}
