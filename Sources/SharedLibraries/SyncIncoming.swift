import Foundation

/// Merging in what other devices sent (library sync design, "Merging in a record from another device"). A record
/// the server holds is merged exactly as one fetched is, so there is no separate rule for conflicts.
extension SharedLibrary {
    /// Merges `changes` into the library in one transaction, and tells what it did. A change the library holds
    /// already is only noted, outside the transaction, so a second app on the device fetching the same records
    /// changes nothing and tells nobody. Throws, with the library as it was, when a record can't be applied.
    @discardableResult
    public func applyRemote(_ changes: [RemoteChange]) throws -> RemoteApplyReport {
        var report = RemoteApplyReport()
        var pending: [RemoteChange] = []
        for change in changes {
            if try holdsAlready(change) { report.unchanged += 1 } else { pending.append(change) }
        }
        guard !pending.isEmpty else { return report }
        let application = try write { writer in
            var application = RemoteApplication(writer: writer, library: self)
            try application.apply(Self.inApplyingOrder(pending))
            return application
        }
        application.finish()
        report.applied = application.applied
        report.parked = application.parked
        return report
    }

    // MARK: Helpers

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

    /// True when a change needs nothing from the library but a note of the server's fields: the record is the one
    /// this device last saw, or its content is what the library holds. A deletion of what isn't here is held too.
    private func holdsAlready(_ change: RemoteChange) throws -> Bool {
        let database = try connection()
        switch change {
        case .deleted(let id):
            return try cloudRecords(inZone: SyncZone.library, in: database)[id.name] == nil
                && syncRow(of: id, in: database) == nil
        case .saved(let record, let fields):
            let digest = try SyncPayloads.digest(ofIncoming: record.payload, kind: record.id.kind)
            guard let row = try syncRow(of: record.id, in: database) else { return false }
            let known = try cloudRecords(inZone: SyncZone.library, in: database)[record.id.name]
            if known?.digest == digest {
                try database.run("UPDATE cloudRecords SET systemFields = ? WHERE zone = ? AND name = ?",
                                 [.blob(fields), .text(SyncZone.library), .text(record.id.name)])
                return true
            }
            guard let local = try syncRecord(record.id, rowKey: row.rowKey, in: database),
                  SyncDigest.hex(of: local.payload) == digest else { return false }
            try storeCloudRecord(CloudRecord(name: record.id.name, kind: record.id.kind.rawValue,
                                             rowKey: row.rowKey, systemFields: fields, sentChanged: row.changed,
                                             digest: digest), in: database)
            return true
        }
    }
}
