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
    /// What to change on the disk once the transaction has committed, so a failed batch leaves every file as it
    /// was: pictures and custom images to delete, removed PDFs, and custom images copied in under a staged name.
    private var picturesToDelete: [String] = []
    private var removedSources: [String] = []
    private var customImagesToDelete: [String] = []
    private var stagedImages: Set<String> = []
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

    /// Changes the files, the transaction having committed: deletes the pictures nothing names any more (art
    /// applied later in the batch may name one again), removed PDFs' kept copies and deleted custom art's images,
    /// and puts the staged custom images in place.
    func finish() {
        library.removePictures(noLongerNamedAmong: picturesToDelete)
        for source in removedSources { try? FileManager.default.removeItem(at: library.keptFile(sourceID: source)) }
        let files = try? database.rows("SELECT file FROM customArt").compactMap { $0.text("file") }
        if let named = files.map(Set.init) {
            for file in customImagesToDelete where !named.contains(file) {
                try? FileManager.default.removeItem(at: library.customFile(file))
            }
        }
        for file in stagedImages {
            try? FileManager.default.removeItem(at: library.customFile(file))
            try? FileManager.default.moveItem(at: library.stagedCustomFile(file), to: library.customFile(file))
        }
    }

    // MARK: Saved records

    /// Merges a saved record in. What was kept aside under its name is older, and goes.
    mutating func applySaved(_ record: SyncRecord, fields: Data) throws {
        let kind = record.id.kind
        try database.run("DELETE FROM parkedRecords WHERE name = ?", [.text(record.id.name)])
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
    /// now says nothing more than that content, nothing is left to send; otherwise the row stays to be sent, merged.
    func settle(_ incoming: IncomingRecord, rowKey: String) throws {
        var sentChanged = try library.cloudRecord(named: incoming.id.name, in: database)?.sentChanged ?? -1
        if let changed = try library.syncCounter(of: incoming.id.kind, rowKey: rowKey, in: database),
           try addsNothing(to: incoming, rowKey: rowKey) {
            sentChanged = changed
        }
        try store(incoming, rowKey: rowKey, sentChanged: sentChanged)
    }

    /// True when the local row has the content of `incoming`, or is a PDF's reading that only knows less of where
    /// else its art is printed (`SourceReading.isCovered`).
    private func addsNothing(to incoming: IncomingRecord, rowKey: String) throws -> Bool {
        guard let local = try library.syncRecord(incoming.id, rowKey: rowKey, in: database) else { return false }
        if SyncDigest.hex(of: local.payload) == incoming.digest { return true }
        guard incoming.id.kind == .source else { return false }
        let own = try SyncPayloads.decode(SourceReading.self, from: local.payload, kind: .source)
        let theirs = try SyncPayloads.decode(SourceReading.self, from: incoming.record.payload, kind: .source)
        return own.isCovered(by: theirs)
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
    mutating func addPicturesToDelete(_ names: [String]) { picturesToDelete += names }
    mutating func addRemovedSource(_ id: String) { removedSources.append(id) }
    mutating func addCustomImageToDelete(_ file: String) { customImagesToDelete.append(file) }
    mutating func addStagedImage(_ file: String) { stagedImages.insert(file) }
    mutating func addAppliedSource(_ incoming: IncomingRecord) { appliedSources.append(incoming) }

    // MARK: Parked and settled

    /// Tries again every note that arrived before its art. Records this version can't read wait for another.
    private mutating func retryParked() throws {
        let before = parked
        let waiting = try database.rows("SELECT * FROM parkedRecords WHERE unreadable = 0 ORDER BY name")
        for case .saved(let record, let fields)? in waiting.map(SharedLibrary.parkedChange) {
            try applySaved(record, fields: fields)
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
