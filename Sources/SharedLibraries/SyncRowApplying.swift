import Foundation

/// Applying the records that are one row each: notes, the art chosen for creatures, custom creatures and custom
/// art. With changes of its own not yet sent, a row keeps the later edit (a corrected note first); otherwise the
/// incoming one is saved.
extension RemoteApplication {
    mutating func applyNote(_ payload: NotePayload, _ incoming: IncomingRecord) throws {
        guard let entry = try ArtRows.entryID(answeringTo: payload.entry, in: database) else {
            try park(incoming)
            return
        }
        let key = entry.uuidString
        let local = try ArtRows.notes(in: database, where: "entry = ?", [.text(key)])[entry]
        let localModified = try modified(in: .notes, key: key) ?? 0
        let note = ArtNote(userName: payload.userName, tags: payload.tags, tagModel: payload.tagModel,
                           suggestedName: payload.suggestedName, isCorrected: payload.corrected)
        let keepsLocal = try local.map { try hasUnsentChanges(.note, rowKey: key)
            && Self.keepsNote($0, modified: localModified, over: payload) } ?? false
        if !keepsLocal && !(local == note && localModified == payload.modified) {
            try writer.upsert(note, for: entry, modified: SharedLibrary.date(payload.modified))
        }
        try settle(incoming, rowKey: payload.entry.uuidString)
        countApplied()
    }

    mutating func applyCreatureArt(_ payload: CreatureArtPayload, _ incoming: IncomingRecord) throws {
        let subject = payload.subject
        if try !keepsLocal(.creatureArt, key: subject, over: payload.modified) {
            let modified = SharedLibrary.date(payload.modified)
            if let entry = payload.entry {
                let known = try ArtRows.entryID(answeringTo: entry, in: database) ?? entry
                try writer.upsert(.library(known), for: subject, modified: modified)
            } else if let custom = payload.customArt {
                try writer.upsert(.custom(custom), for: subject, modified: modified)
            } else {
                try writer.delete(from: .creatureArt, where: "subject = ?", [.text(subject)])
            }
        }
        try settle(incoming, rowKey: subject)
        countApplied()
    }

    mutating func applyCustomCreature(_ payload: CustomCreaturePayload, _ incoming: IncomingRecord) throws {
        let key = payload.id.uuidString
        if try !keepsLocal(.customCreature, key: key, over: payload.modified) {
            try writer.upsert(CustomCreatureRecord(id: payload.id, campaignID: payload.campaign,
                                                   sharedVersion: payload.sharedVersion.map(SharedLibrary.date),
                                                   record: payload.record),
                              modified: SharedLibrary.date(payload.modified))
        }
        try settle(incoming, rowKey: key)
        countApplied()
    }

    mutating func applyCustomArt(_ payload: CustomArtPayload, _ incoming: IncomingRecord) throws {
        let key = payload.id.uuidString
        if try !keepsLocal(.customArt, key: key, over: payload.modified) {
            try stageImage(of: incoming.record, as: payload.file)
            try writer.upsert(CustomArtRecord(id: payload.id, fileName: payload.file,
                                              sharedVersion: payload.sharedVersion.map(SharedLibrary.date),
                                              record: payload.record),
                              modified: SharedLibrary.date(payload.modified))
        }
        try settle(incoming, rowKey: key)
        countApplied()
    }

    /// A record deleted elsewhere. A row with changes not yet sent stays, and is sent again; any other goes.
    mutating func applyDeleted(_ id: SyncRecordID) throws {
        try database.run("DELETE FROM parkedRecords WHERE name = ?", [.text(id.name)])
        if id.kind == .source { return try removeSource(id) }
        let known = try library.cloudRecord(named: id.name, in: database)
        try database.run("DELETE FROM cloudRecords WHERE zone = ? AND name = ?",
                         [.text(SyncZone.library), .text(id.name)])
        guard let rowKey = known?.rowKey ?? SyncRecordName.rowKey(of: id),
              let table = Self.table(of: id.kind) else { return }
        let hasUnsent = try hasUnsentChanges(id.kind, rowKey: rowKey, knownRecord: known)
        if !hasUnsent { try deleteRow(of: id.kind, in: table, key: rowKey) }
        countApplied()
    }

    // MARK: Helpers

    private static func table(of kind: SyncKind) -> LibraryTable? {
        switch kind {
        case .source: nil
        case .note: .notes
        case .creatureArt: .creatureArt
        case .customCreature: .customCreatures
        case .customArt: .customArt
        }
    }

    /// True when the local note stays over `incoming`: a corrected note beats an uncorrected one, and otherwise the
    /// later edit wins.
    private static func keepsNote(_ local: ArtNote, modified: Double, over incoming: NotePayload) -> Bool {
        local.isCorrected == incoming.corrected ? modified > incoming.modified : local.isCorrected
    }

    /// True when the row has changes not yet sent that are later than `incoming`, so the incoming record doesn't
    /// replace it.
    private func keepsLocal(_ kind: SyncKind, key: String, over incoming: Double) throws -> Bool {
        guard let table = Self.table(of: kind), let local = try modified(in: table, key: key),
              try hasUnsentChanges(kind, rowKey: key) else { return false }
        return local > incoming
    }

    /// Like `hasUnsentChanges(_:rowKey:)` for a record whose cloud row has been forgotten already: a row the cloud
    /// no longer holds is sent again.
    private func hasUnsentChanges(_ kind: SyncKind, rowKey: String, knownRecord: CloudRecord?) throws -> Bool {
        guard let changed = try library.syncCounter(of: kind, rowKey: rowKey, in: database) else { return false }
        return knownRecord?.isInStep(at: changed) != true
    }

    /// Deletes the row; custom art's image goes once the transaction has committed.
    private mutating func deleteRow(of kind: SyncKind, in table: LibraryTable, key: String) throws {
        if kind == .customArt, let file = try database.rows("SELECT file FROM customArt WHERE id = ?", [.text(key)])
            .first?.text("file") {
            addCustomImageToDelete(file)
        }
        try writer.delete(from: table, where: "\(table.keyColumns[0]) = ?", [.text(key)])
    }

    /// Copies custom art's image in under a staged name; `finish` puts it in place once the transaction has
    /// committed, so a failed batch leaves the image the row had.
    private mutating func stageImage(of record: SyncRecord, as fileName: String) throws {
        guard let source = record.file else { return }
        let staged = library.stagedCustomFile(fileName)
        do {
            try? FileManager.default.removeItem(at: staged)
            try FileManager.default.copyItem(at: source, to: staged)
        } catch {
            throw SharedLibraryError(operation: "Saving \(fileName)", detail: error.localizedDescription)
        }
        addStagedImage(fileName)
    }

    /// Keeps a note aside until the art it is about arrives.
    private mutating func park(_ incoming: IncomingRecord) throws {
        try database.run("INSERT OR REPLACE INTO parkedRecords (name, kind, payload, systemFields) "
                         + "VALUES (?, ?, ?, ?)", [.text(incoming.id.name), .text(incoming.id.kind.rawValue),
                                                    .blob(incoming.record.payload), .blob(incoming.fields)])
        countParked()
    }
}
