import ArtExtraction
import Foundation

/// Reading the rows a record is made from.
extension SharedLibrary {
    /// The row a record is made from: its key, and the change counter that says when it last changed. Nil when
    /// the row is gone.
    func syncRow(of id: SyncRecordID, in database: SQLiteDatabase) throws -> (rowKey: String, changed: Int64)? {
        if let rowKey = SyncRecordName.rowKey(of: id) {
            return try syncCounter(of: id.kind, rowKey: rowKey, in: database).map { (rowKey, $0) }
        }
        // A creature's subject is hidden by its record's name: find the row whose subject has that name.
        return try syncRows(of: id.kind, in: database).first {
            SyncRecordName.make(id.kind, rowKey: $0.rowKey) == id.name
        }
    }

    /// The change counter of the row `rowKey`; nil when there is no such row.
    func syncCounter(of kind: SyncKind, rowKey: String, in database: SQLiteDatabase) throws -> Int64? {
        let table = Self.syncTable(of: kind)
        return try database.rows(table.select + " WHERE \(table.keyColumn) = ?", [.text(rowKey)]).first
            .map { $0.integer("changed") ?? 0 }
    }

    /// Every row of a kind with its change counter.
    func syncRows(of kind: SyncKind, in database: SQLiteDatabase) throws -> [(rowKey: String, changed: Int64)] {
        try database.rows(Self.syncTable(of: kind).select).compactMap { row in
            row.text("rowKey").map { ($0, row.integer("changed") ?? 0) }
        }
    }

    /// The record for the row `rowKey`: its payload, title and file. Nil when the row can't be read.
    func syncRecord(_ id: SyncRecordID, rowKey: String, in database: SQLiteDatabase) throws -> SyncRecord? {
        let key = [SQLValue.text(rowKey)]
        switch id.kind {
        case .source: return try sourceRecord(id, in: database)
        case .note:
            return try database.rows("SELECT * FROM notes WHERE entry = ?", key).first.flatMap(notePayload)
                .map { try record(id, $0, title: $0.userName ?? rowKey) }
        case .creatureArt:
            return try database.rows("SELECT * FROM creatureArt WHERE subject = ?", key).first
                .flatMap(creatureArtPayload).map { try record(id, $0, title: $0.subject) }
        case .customCreature:
            return try database.rows("SELECT * FROM customCreatures WHERE id = ?", key).first
                .flatMap(customCreaturePayload).map { try record(id, $0, title: rowKey) }
        case .customArt:
            return try database.rows("SELECT * FROM customArt WHERE id = ?", key).first.flatMap(customArtPayload)
                .map { payload in
                    var record = try record(id, payload, title: payload.file)
                    record.file = customFile(payload.file)
                    return record
                }
        }
    }

    // MARK: Helpers

    /// How a kind's rows and change counters are read. A source's counter is the greatest of its own row's, its
    /// prints', the art they belong to, and that art's aliases, so no writer has to know about syncing.
    private static func syncTable(of kind: SyncKind) -> (select: String, keyColumn: String) {
        switch kind {
        case .source:
            let prints = "SELECT entry FROM prints WHERE source = sources.id"
            return ("SELECT id AS rowKey, MAX(changed, "
                    + "COALESCE((SELECT MAX(changed) FROM prints WHERE source = sources.id), 0), "
                    + "COALESCE((SELECT MAX(changed) FROM art WHERE id IN (\(prints))), 0), "
                    + "COALESCE((SELECT MAX(changed) FROM aliases WHERE entry IN (\(prints))), 0)) AS changed "
                    + "FROM sources", "id")
        case .note: return ("SELECT entry AS rowKey, changed FROM notes", "entry")
        case .creatureArt: return ("SELECT subject AS rowKey, changed FROM creatureArt", "subject")
        case .customCreature: return ("SELECT id AS rowKey, changed FROM customCreatures", "id")
        case .customArt: return ("SELECT id AS rowKey, changed FROM customArt", "id")
        }
    }

    private func record(_ id: SyncRecordID, _ payload: some Encodable, title: String) throws -> SyncRecord {
        SyncRecord(id: id, payload: try SyncPayloads.encode(payload), title: title)
    }

    private func notePayload(_ row: SQLRow) -> NotePayload? {
        guard let entry = row.uuid("entry") else { return nil }
        let tags = row.blob("tags").flatMap { try? JSONDecoder().decode([String].self, from: $0) } ?? []
        return NotePayload(entry: entry, userName: row.text("userName"), tags: tags,
                           tagModel: row.text("tagModel") ?? "", suggestedName: row.text("suggestedName") ?? "",
                           corrected: row.integer("corrected") == 1, modified: row.real("modified") ?? 0)
    }

    private func creatureArtPayload(_ row: SQLRow) -> CreatureArtPayload? {
        row.text("subject").map { subject in
            CreatureArtPayload(subject: subject, entry: row.uuid("entry"), customArt: row.uuid("customArt"),
                               modified: row.real("modified") ?? 0)
        }
    }

    private func customCreaturePayload(_ row: SQLRow) -> CustomCreaturePayload? {
        guard let id = row.uuid("id"), let record = row.blob("record") else { return nil }
        return CustomCreaturePayload(id: id, campaign: row.uuid("campaign"), sharedVersion: row.real("sharedVersion"),
                                     record: record, modified: row.real("modified") ?? 0,
                                     name: row.text("name") ?? "",
                                     game: row.text("game").flatMap(GameSystem.init(rawValue:)),
                                     size: row.text("size").flatMap(CreatureSize.init(rawValue:)))
    }

    private func customArtPayload(_ row: SQLRow) -> CustomArtPayload? {
        guard let id = row.uuid("id"), let file = row.text("file"), let record = row.blob("record") else { return nil }
        return CustomArtPayload(id: id, file: file, sharedVersion: row.real("sharedVersion"), record: record,
                                modified: row.real("modified") ?? 0)
    }
}
