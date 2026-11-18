import Foundation

/// What this device has to send to the cloud (library sync design): the records changed since the cloud last agreed,
/// and those whose rows are gone. `cloudRecords` remembers what the cloud holds, shared by the apps on the device, so
/// a record one app has sent isn't sent by another.
extension SharedLibrary {
    /// The records to save and to delete; neither while syncing is paused. A record whose copy in the cloud this
    /// version can't read isn't saved over it: it waits for the version that can.
    public func syncCandidates() throws -> SyncCandidates {
        guard try !isSyncPaused else { return SyncCandidates() }
        let database = try connection()
        let known = try cloudRecords(inZone: SyncZone.library, in: database)
        let unreadable = try unreadableRecordNames(in: database)
        var candidates = SyncCandidates()
        var live: Set<String> = []
        for kind in SyncKind.allCases {
            for (rowKey, changed) in try syncRows(of: kind, in: database) {
                let name = SyncRecordName.make(kind, rowKey: rowKey)
                live.insert(name)
                if let record = known[name], record.isInStep(at: changed) { continue }
                if unreadable.contains(name) { continue }
                candidates.saves.append(SyncRecordID(kind: kind, name: name))
            }
        }
        candidates.deletions = known.values.filter { $0.systemFields != nil && !live.contains($0.name) }
            .compactMap { record in SyncKind(rawValue: record.kind).map { SyncRecordID(kind: $0, name: record.name) } }
        candidates.deletions.sort { $0.name < $1.name }
        return candidates
    }

    /// The record to send for `id`; nil when its row is gone, when the cloud already holds this content (another
    /// app sent it, or a write changed nothing that syncs), or when this version can't read the cloud's copy.
    public func outgoingRecord(_ id: SyncRecordID) throws -> OutgoingRecord? {
        let database = try connection()
        // The counter is read before the content: a change in between is then sent again, and dropped by its digest.
        guard try !unreadableRecordNames(in: database).contains(id.name),
              let row = try syncRow(of: id, in: database),
              let record = try syncRecord(id, rowKey: row.rowKey, in: database) else { return nil }
        let digest = SyncDigest.hex(of: record.payload)
        let known = try cloudRecord(named: id.name, in: database)
        if let known, known.systemFields != nil, known.digest == digest {
            try database.run("UPDATE cloudRecords SET sentChanged = MAX(sentChanged, ?) WHERE zone = ? AND name = ?",
                             [.integer(row.changed), .text(SyncZone.library), .text(id.name)])
            return nil
        }
        return OutgoingRecord(record: record, systemFields: known?.systemFields, changed: row.changed,
                              digest: digest, rowKey: row.rowKey)
    }

    /// Remembers that the cloud now holds `sent`, with the fields it answered with.
    public func markSent(_ sent: OutgoingRecord, systemFields: Data) throws {
        try storeCloudRecord(CloudRecord(name: sent.record.id.name, kind: sent.record.id.kind.rawValue,
                                         rowKey: sent.rowKey, systemFields: systemFields,
                                         sentChanged: sent.changed, digest: sent.digest), in: connection())
    }

    /// Remembers that the cloud no longer holds the record.
    public func markDeleted(_ id: SyncRecordID) throws {
        try connection().run("DELETE FROM cloudRecords WHERE zone = ? AND name = ?",
                             [.text(SyncZone.library), .text(id.name)])
    }

    /// Remembers that the cloud doesn't have the record after all (`unknownItem`), so it is sent again as new.
    public func forgetSystemFields(of id: SyncRecordID) throws {
        try connection().run("UPDATE cloudRecords SET systemFields = NULL WHERE zone = ? AND name = ?",
                             [.text(SyncZone.library), .text(id.name)])
    }

    /// Forgets everything known about the cloud, as when another account signs in or the zone is deleted: every
    /// record is then sent again.
    public func forgetServer() throws {
        try connection().transaction {
            let database = try connection()
            try database.run("DELETE FROM cloudRecords")
            try database.run("DELETE FROM parkedRecords")
            try database.run("DELETE FROM syncState WHERE key LIKE 'engine.%'")
        }
    }

    // MARK: Helpers

    func cloudRecords(inZone zone: String, in database: SQLiteDatabase) throws -> [String: CloudRecord] {
        let rows = try database.rows("SELECT * FROM cloudRecords WHERE zone = ?", [.text(zone)])
        return Dictionary(rows.compactMap(CloudRecord.init(row:)).map { ($0.name, $0) }) { first, _ in first }
    }

    func storeCloudRecord(_ record: CloudRecord, in database: SQLiteDatabase) throws {
        try database.run("INSERT OR REPLACE INTO cloudRecords (zone, name, kind, rowKey, systemFields, "
                         + "sentChanged, digest) VALUES (?, ?, ?, ?, ?, ?, ?)",
                         [.text(SyncZone.library), .text(record.name), .text(record.kind), .text(record.rowKey),
                          record.systemFields.map { .blob($0) } ?? .null, .integer(record.sentChanged),
                          .text(record.digest)])
    }

    /// What this device knows of the library's record `name` in the cloud.
    func cloudRecord(named name: String, in database: SQLiteDatabase) throws -> CloudRecord? {
        try database.rows("SELECT * FROM cloudRecords WHERE zone = ? AND name = ?",
                          [.text(SyncZone.library), .text(name)]).first.flatMap(CloudRecord.init(row:))
    }
}

/// What a device knows the cloud holds for one record.
struct CloudRecord {
    var name: String
    var kind: String
    var rowKey: String
    /// Nil once the cloud is known not to have it.
    var systemFields: Data?
    var sentChanged: Int64
    var digest: String

    /// True when the cloud has the record and the row hasn't changed since it agreed.
    func isInStep(at changed: Int64) -> Bool {
        systemFields != nil && changed <= sentChanged
    }
}

extension CloudRecord {
    init?(row: SQLRow) {
        guard let name = row.text("name") else { return nil }
        self.init(name: name, kind: row.text("kind") ?? "", rowKey: row.text("rowKey") ?? "",
                  systemFields: row.blob("systemFields"), sentChanged: row.integer("sentChanged") ?? 0,
                  digest: row.text("digest") ?? "")
    }
}
