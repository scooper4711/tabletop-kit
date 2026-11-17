import Foundation

/// What is learned about a piece of art (shared libraries R3.3), so one app's names and tags help the others match
/// creatures: Pawn Shop's names, its tagging model's tags, and the user's corrections.
public struct ArtNote: Equatable, Sendable {
    /// The name the user gave the art, when it differs from the name printed.
    public var userName: String?
    /// Search keywords for what the art shows besides its name, such as "scimitar" and "cloak".
    public var tags: [String]
    /// The model and prompt that chose `tags`; empty until the art is tagged.
    public var tagModel: String
    /// A name the model suggests for art printed without one.
    public var suggestedName: String
    /// True once the user corrected the tags: tagging then leaves them alone, and a move keeps them (R6.2).
    public var isCorrected: Bool

    public init(userName: String? = nil, tags: [String] = [], tagModel: String = "", suggestedName: String = "",
                isCorrected: Bool = false) {
        self.userName = userName
        self.tags = tags
        self.tagModel = tagModel
        self.suggestedName = suggestedName
        self.isCorrected = isCorrected
    }
}

extension SharedLibrary {
    /// The notes changed after `counter`, by the ID of the art they are about; all of them by default.
    public func notes(changedSince counter: Int64 = 0) throws -> [UUID: ArtNote] {
        try ArtRows.notes(in: try connection(), where: "changed > ?", [.integer(counter)])
    }

    /// Saves what is learned about the art with ID, print key or alias `id`; nil forgets it. False when the
    /// library has no such art.
    @discardableResult
    public func setNote(_ note: ArtNote?, forArt id: UUID) throws -> Bool {
        try write { writer in
            guard let entry = try ArtRows.entryID(answeringTo: id, in: writer.database) else { return false }
            guard let note else {
                try writer.delete(from: .notes, where: "entry = ?", [.text(entry.uuidString)])
                return true
            }
            try writer.upsert(note, for: entry)
            return true
        }
    }
}

extension LibraryWriter {
    func upsert(_ note: ArtNote, for entry: UUID) throws {
        try upsert(.notes, [("entry", .text(entry.uuidString)), ("userName", note.userName.map { .text($0) } ?? .null),
                            ("tags", try ArtRows.encoded(note.tags)), ("tagModel", .text(note.tagModel)),
                            ("suggestedName", .text(note.suggestedName)),
                            ("corrected", .integer(note.isCorrected ? 1 : 0))])
    }

    /// Moves the note about art `old` to art `new`, unless `new` has a note the user corrected.
    func moveNote(from old: UUID, to new: UUID) throws {
        guard let moved = try ArtRows.notes(in: database, where: "entry = ?", [.text(old.uuidString)])[old] else {
            return
        }
        let kept = try ArtRows.notes(in: database, where: "entry = ?", [.text(new.uuidString)])[new]
        if kept?.isCorrected != true { try upsert(moved, for: new) }
        try delete(from: .notes, where: "entry = ?", [.text(old.uuidString)])
    }
}

extension ArtRows {
    /// The notes matching `condition`, by the art they are about.
    static func notes(in database: SQLiteDatabase, where condition: String,
                      _ values: [SQLValue]) throws -> [UUID: ArtNote] {
        var notes: [UUID: ArtNote] = [:]
        for row in try database.rows("SELECT * FROM notes WHERE \(condition)", values) {
            guard let entry = row.uuid("entry") else { continue }
            let tags = row.blob("tags").flatMap { try? JSONDecoder().decode([String].self, from: $0) } ?? []
            notes[entry] = ArtNote(userName: row.text("userName"), tags: tags, tagModel: row.text("tagModel") ?? "",
                                   suggestedName: row.text("suggestedName") ?? "",
                                   isCorrected: row.integer("corrected") == 1)
        }
        return notes
    }
}
