import Foundation

/// A custom creature as the creature library keeps it (shared libraries R4): Turnkeeper's `CustomCreature` encoded
/// by Turnkeeper, with what the library needs to know about it.
public struct CustomCreatureRecord: Equatable, Sendable {
    public var id: UUID
    /// The campaign it was made in, so Turnkeeper can list that campaign's creatures first (R4.1).
    public var campaignID: UUID?
    /// The version last shared with another device (R4.5).
    public var sharedVersion: Date?
    /// The creature as its app encodes it.
    public var record: Data

    public init(id: UUID, campaignID: UUID?, sharedVersion: Date?, record: Data) {
        self.id = id
        self.campaignID = campaignID
        self.sharedVersion = sharedVersion
        self.record = record
    }
}

/// Art the user pasted or dropped for a creature (R4.2): Turnkeeper's `CustomArt` encoded by Turnkeeper, and its
/// image file in the library's `Custom` folder.
public struct CustomArtRecord: Equatable, Sendable {
    public var id: UUID
    /// The image's file name in `Custom`, such as `<id>.jpg`.
    public var fileName: String
    public var sharedVersion: Date?
    public var record: Data

    public init(id: UUID, fileName: String, sharedVersion: Date?, record: Data) {
        self.id = id
        self.fileName = fileName
        self.sharedVersion = sharedVersion
        self.record = record
    }
}

/// The art chosen for a creature, the same in Turnkeeper and Field Guide (R3.4).
public enum CreatureArtChoice: Hashable, Sendable {
    /// Art from the art library, by its ID or one of its print keys or aliases.
    case library(UUID)
    /// Custom art, by its ID.
    case custom(UUID)
}

/// The creature library: custom creatures, the art the user added, and the art chosen for each creature.
extension SharedLibrary {
    /// The custom creatures changed after `counter`; all of them by default.
    public func customCreatures(changedSince counter: Int64 = 0) throws -> [CustomCreatureRecord] {
        try connection().rows("SELECT * FROM customCreatures WHERE changed > ?", [.integer(counter)])
            .compactMap { row in
                guard let id = row.uuid("id"), let record = row.blob("record") else { return nil }
                return CustomCreatureRecord(id: id, campaignID: row.uuid("campaign"),
                                            sharedVersion: row.real("sharedVersion").map(Self.date), record: record)
            }
    }

    /// Adds a custom creature or saves a change to it.
    public func save(_ creature: CustomCreatureRecord) throws {
        try write { writer in try writer.upsert(creature) }
    }

    public func removeCustomCreature(id: UUID) throws {
        try write { writer in
            try writer.delete(from: .customCreatures, where: "id = ?", [.text(id.uuidString)])
        }
    }

    /// The custom art changed after `counter`; all of it by default.
    public func customArt(changedSince counter: Int64 = 0) throws -> [CustomArtRecord] {
        try connection().rows("SELECT * FROM customArt WHERE changed > ?", [.integer(counter)]).compactMap { row in
            guard let id = row.uuid("id"), let file = row.text("file"), let record = row.blob("record") else {
                return nil
            }
            return CustomArtRecord(id: id, fileName: file, sharedVersion: row.real("sharedVersion").map(Self.date),
                                   record: record)
        }
    }

    /// Adds custom art or saves a change to it, writing `image` to its file first when given.
    public func save(_ art: CustomArtRecord, image: Data? = nil) throws {
        if let image {
            do {
                try image.write(to: customFile(art.fileName), options: .atomic)
            } catch {
                throw SharedLibraryError(operation: "Saving \(art.fileName)", detail: error.localizedDescription)
            }
        }
        try write { writer in try writer.upsert(art) }
    }

    /// Takes custom art out, with its image file.
    public func removeCustomArt(id: UUID) throws {
        let files = try customArt().filter { $0.id == id }.map(\.fileName)
        try write { writer in
            try writer.delete(from: .customArt, where: "id = ?", [.text(id.uuidString)])
        }
        for file in files { try? FileManager.default.removeItem(at: customFile(file)) }
    }

    /// Where custom art's image is.
    public func customFile(_ fileName: String) -> URL {
        customFolder.appending(path: fileName)
    }

    /// The art chosen for each creature, by its bestiary key or `custom.<id>`.
    public func creatureArt() throws -> [String: CreatureArtChoice] {
        var choices: [String: CreatureArtChoice] = [:]
        for row in try connection().rows("SELECT * FROM creatureArt") {
            guard let subject = row.text("subject") else { continue }
            if let entry = row.uuid("entry") {
                choices[subject] = .library(entry)
            } else if let custom = row.uuid("customArt") {
                choices[subject] = .custom(custom)
            }
        }
        return choices
    }

    /// Chooses the art for a creature; nil goes back to its default art.
    public func setCreatureArt(_ choice: CreatureArtChoice?, for subject: String) throws {
        try write { writer in
            guard let choice else {
                return try writer.delete(from: .creatureArt, where: "subject = ?", [.text(subject)])
            }
            try writer.upsert(choice, for: subject)
        }
    }

    static func date(_ interval: Double) -> Date { Date(timeIntervalSinceReferenceDate: interval) }
}

extension LibraryWriter {
    /// The four `upsert`s of what the user makes take `modified`, the time of the user's change, which settles
    /// edits made on two devices (library sync).
    func upsert(_ creature: CustomCreatureRecord, modified: Date = Date()) throws {
        try upsert(.customCreatures, [("id", .text(creature.id.uuidString)),
                                      ("campaign", creature.campaignID.map { .text($0.uuidString) } ?? .null),
                                      ("sharedVersion", Self.value(of: creature.sharedVersion)),
                                      ("record", .blob(creature.record)), Self.modified(modified)])
    }

    func upsert(_ art: CustomArtRecord, modified: Date = Date()) throws {
        try upsert(.customArt, [("id", .text(art.id.uuidString)), ("file", .text(art.fileName)),
                                ("sharedVersion", Self.value(of: art.sharedVersion)), ("record", .blob(art.record)),
                                Self.modified(modified)])
    }

    func upsert(_ choice: CreatureArtChoice, for subject: String, modified: Date = Date()) throws {
        let (entry, custom): (SQLValue, SQLValue) = switch choice {
        case .library(let id): (.text(id.uuidString), .null)
        case .custom(let id): (.null, .text(id.uuidString))
        }
        try upsert(.creatureArt, [("subject", .text(subject)), ("entry", entry), ("customArt", custom),
                                  Self.modified(modified)])
    }

    static func modified(_ date: Date) -> (String, SQLValue) {
        ("modified", .real(date.timeIntervalSinceReferenceDate))
    }

    private static func value(of date: Date?) -> SQLValue {
        date.map { .real($0.timeIntervalSinceReferenceDate) } ?? .null
    }
}
