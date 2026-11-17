import Foundation

/// One record from another device, with what the library notes of it.
struct IncomingRecord {
    var record: SyncRecord
    /// The server's fields for the record.
    var fields: Data
    /// The digest of the record's content as this version encodes it.
    var digest: String

    var id: SyncRecordID { record.id }
}

/// Applying changes from other devices inside one `SharedLibrary.write`.
struct RemoteApplication {
    let writer: LibraryWriter
    let library: SharedLibrary
    private(set) var applied = 0
    private(set) var parked = 0
    /// What to delete from the disk once the transaction has committed.
    private var picturesToDelete: [String] = []
    private var removedSources: [String] = []
    /// The sources applied, settled once all are in.
    private var appliedSources: [IncomingRecord] = []

    var database: SQLiteDatabase { writer.database }

    init(writer: LibraryWriter, library: SharedLibrary) {
        self.writer = writer
        self.library = library
    }

    mutating func apply(_ changes: [RemoteChange]) throws {
        for change in changes {
            switch change {
            case .saved(let record, let fields): try applySaved(record, fields: fields)
            case .deleted(let id): try applyDeleted(id)
            }
        }
        try retryParked()
        try settleSources()
    }

    /// Deletes the files the transaction left behind: pictures no art uses, and removed PDFs' kept copies.
    func finish() {
        for name in picturesToDelete { try? FileManager.default.removeItem(at: library.pictureFile(name)) }
        for source in removedSources { try? FileManager.default.removeItem(at: library.keptFile(sourceID: source)) }
    }

    // MARK: Saved records

    mutating func applySaved(_ record: SyncRecord, fields: Data) throws {
        let kind = record.id.kind
        let digest = try SyncPayloads.digest(ofIncoming: record.payload, kind: kind)
        let incoming = IncomingRecord(record: record, fields: fields, digest: digest)
        switch kind {
        case .source: try applySource(try SyncPayloads.decode(SourceReading.self, from: record.payload, kind: kind),
                                      incoming)
        case .note: try applyNote(try SyncPayloads.decode(NotePayload.self, from: record.payload, kind: kind),
                                  incoming)
        case .creatureArt: try applyCreatureArt(
            try SyncPayloads.decode(CreatureArtPayload.self, from: record.payload, kind: kind), incoming)
        case .customCreature: try applyCustomCreature(
            try SyncPayloads.decode(CustomCreaturePayload.self, from: record.payload, kind: kind), incoming)
        case .customArt: try applyCustomArt(
            try SyncPayloads.decode(CustomArtPayload.self, from: record.payload, kind: kind), incoming)
        }
    }

    /// Notes what the library holds of the record `incoming`: the server's fields and content. When the local row
    /// now has that content, nothing is left to send; otherwise the row stays to be sent, merged.
    func settle(_ incoming: IncomingRecord, rowKey: String) throws {
        var sentChanged = try library.cloudRecord(named: incoming.id.name, in: database)?.sentChanged ?? -1
        if let changed = try library.syncCounter(of: incoming.id.kind, rowKey: rowKey, in: database),
           let local = try library.syncRecord(incoming.id, rowKey: rowKey, in: database),
           SyncDigest.hex(of: local.payload) == incoming.digest {
            sentChanged = changed
        }
        try store(incoming, rowKey: rowKey, sentChanged: sentChanged)
    }

    func store(_ incoming: IncomingRecord, rowKey: String, sentChanged: Int64) throws {
        try library.storeCloudRecord(CloudRecord(name: incoming.id.name, kind: incoming.id.kind.rawValue,
                                                 rowKey: rowKey, systemFields: incoming.fields,
                                                 sentChanged: sentChanged, digest: incoming.digest), in: database)
    }

    /// True when the row has changes the server hasn't seen.
    func hasUnsentChanges(_ kind: SyncKind, rowKey: String) throws -> Bool {
        guard let changed = try library.syncCounter(of: kind, rowKey: rowKey, in: database) else { return false }
        let name = SyncRecordName.make(kind, rowKey: rowKey)
        return try library.cloudRecord(named: name, in: database)?.isInStep(at: changed) != true
    }

    /// When the user last changed the row `key` of `table`; nil without the row.
    func modified(in table: LibraryTable, key: String) throws -> Double? {
        try database.rows("SELECT modified FROM \(table.rawValue) WHERE \(table.keyColumns[0]) = ?", [.text(key)])
            .first?.real("modified")
    }

    mutating func countApplied() { applied += 1 }
    mutating func countParked() { parked += 1 }
    mutating func resetParked(to count: Int) { parked = count }
    mutating func addPicturesToDelete(_ names: [String]) { picturesToDelete += names }
    mutating func addRemovedSource(_ id: String) { removedSources.append(id) }
    mutating func addAppliedSource(_ incoming: IncomingRecord) { appliedSources.append(incoming) }

    // MARK: Parked and settled

    /// Tries again every note that arrived before its art.
    private mutating func retryParked() throws {
        let before = parked
        for row in try database.rows("SELECT * FROM parkedRecords ORDER BY name") {
            guard let name = row.text("name"), let kind = row.text("kind").flatMap(SyncKind.init(rawValue:)),
                  let payload = row.blob("payload"), let fields = row.blob("systemFields") else { continue }
            try database.run("DELETE FROM parkedRecords WHERE name = ?", [.text(name)])
            try applySaved(SyncRecord(id: SyncRecordID(kind: kind, name: name), payload: payload, title: name),
                           fields: fields)
        }
        parked = before
    }

    private func settleSources() throws {
        for source in appliedSources {
            guard let sourceID = SyncRecordName.rowKey(of: source.id) else { continue }
            try settle(source, rowKey: sourceID)
        }
    }
}
