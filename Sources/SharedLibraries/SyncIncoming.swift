import Foundation

/// Merging in what other devices sent (library sync design, "Merging in a record from another device"). A record
/// the server holds is merged exactly as one fetched is, so there is no separate rule for conflicts.
extension SharedLibrary {
    /// Merges `changes` into the library in one transaction, and tells what it did. A change the library holds
    /// already is only noted, outside the transaction, so a second app on the device fetching the same records
    /// changes nothing and tells nobody. A record this version can't read is kept aside for one that can, and the
    /// rest is applied. Throws, with the library as it was, when a record can't be applied.
    @discardableResult
    public func applyRemote(_ changes: [RemoteChange]) throws -> RemoteApplyReport {
        var report = RemoteApplyReport()
        var pending: [RemoteChange] = []
        for change in try parkedNowReadable(besides: changes) + changes {
            switch try standing(of: change) {
            case .unreadable: report.parked += 1
            case .held: report.unchanged += 1
            case .pending: pending.append(change)
            }
        }
        guard !pending.isEmpty else { return report }
        let application = try applied(pending)
        application.finish()
        report.applied = application.applied
        report.parked += application.parked
        return report
    }

    // MARK: Helpers

    /// What a change needs of the library.
    private enum Standing {
        /// This version can't read it: it is kept aside.
        case unreadable
        /// The library holds it already.
        case held
        /// It is to be merged in.
        case pending
    }

    /// Applies `pending` in one transaction; a failure leaves every file as it was.
    private func applied(_ pending: [RemoteChange]) throws -> RemoteApplication {
        do {
            return try write { writer in
                var application = RemoteApplication(writer: writer, library: self)
                try application.apply(Self.inApplyingOrder(pending))
                return application
            }
        } catch {
            removeStagedImages()
            throw error
        }
    }

    /// Deletions of a kind come before its saves, and the kinds in the order of `SyncKind`.
    private static func inApplyingOrder(_ changes: [RemoteChange]) -> [RemoteChange] {
        func rank(_ change: RemoteChange) -> Int {
            switch change {
            case .deleted(let id): (SyncKind.allCases.firstIndex(of: id.kind) ?? 0) * 2
            case .saved(let record, _): (SyncKind.allCases.firstIndex(of: record.id.kind) ?? 0) * 2 + 1
            }
        }
        return changes.enumerated().sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }
            .map(\.element)
    }

    /// Sorts a change, noting what needs no transaction: a record this version can't read is kept aside, and one
    /// the library holds has the server's fields noted. What was kept aside under the name of a change the library
    /// holds is older than it, and goes: a note waiting for its art, deleted since, would otherwise come back.
    private func standing(of change: RemoteChange) throws -> Standing {
        let database = try connection()
        let isHeld: Bool
        switch change {
        case .deleted(let id):
            isHeld = try cloudRecord(named: id.name, in: database) == nil && syncRow(of: id, in: database) == nil
        case .saved(let record, let fields):
            guard let digest = try? SyncPayloads.digest(ofIncoming: record.payload, kind: record.id.kind) else {
                try parkUnreadable(record, fields: fields, in: database)
                return .unreadable
            }
            isHeld = try holds(IncomingRecord(record: record, fields: fields, digest: digest), in: database)
        }
        guard isHeld else { return .pending }
        try database.run("DELETE FROM parkedRecords WHERE name = ?", [.text(change.id.name)])
        return .held
    }

    /// True when a saved record needs nothing from the library but a note of the server's fields: it is the one
    /// this device last saw, or its content is what the library holds. The one last seen is held even with its row
    /// gone: the row was deleted here since, and merging the record in again would undo a deletion still to send.
    private func holds(_ incoming: IncomingRecord, in database: SQLiteDatabase) throws -> Bool {
        let name = incoming.id.name
        if try cloudRecord(named: name, in: database)?.digest == incoming.digest {
            try database.run("UPDATE cloudRecords SET systemFields = ? WHERE zone = ? AND name = ?",
                             [.blob(incoming.fields), .text(SyncZone.library), .text(name)])
            return true
        }
        guard let row = try syncRow(of: incoming.id, in: database),
              let local = try syncRecord(incoming.id, rowKey: row.rowKey, in: database),
              SyncDigest.hex(of: local.payload) == incoming.digest else { return false }
        try storeCloudRecord(CloudRecord(name: name, kind: incoming.id.kind.rawValue, rowKey: row.rowKey,
                                         systemFields: incoming.fields, sentChanged: row.changed,
                                         digest: incoming.digest), in: database)
        return true
    }
}
