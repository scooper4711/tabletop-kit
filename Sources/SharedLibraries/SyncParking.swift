import Foundation

/// Records kept aside in `parkedRecords` (library sync design, "Records kept aside"): a note that arrived before
/// its art, and a record this version of the app can't read, such as one naming a game a newer app added. The
/// second kind is marked `unreadable`, waits for a version that reads it, and is not sent over in the meantime.
extension SharedLibrary {
    /// Keeps aside a record this version can't read, in place of an older copy.
    func parkUnreadable(_ record: SyncRecord, fields: Data, in database: SQLiteDatabase) throws {
        try database.run("INSERT OR REPLACE INTO parkedRecords (name, kind, payload, systemFields, unreadable) "
                         + "VALUES (?, ?, ?, ?, 1)", [.text(record.id.name), .text(record.id.kind.rawValue),
                                                      .blob(record.payload), .blob(fields)])
    }

    /// The records kept aside as unreadable that this version can read, the app having been updated since; but
    /// those `changes` bring a later copy of.
    func parkedNowReadable(besides changes: [RemoteChange]) throws -> [RemoteChange] {
        let later = Set(changes.map(\.id.name))
        return try connection().rows("SELECT * FROM parkedRecords WHERE unreadable = 1 ORDER BY name")
            .compactMap(Self.parkedChange)
            .filter { !later.contains($0.id.name) && SyncPayloads.isReadable($0) }
    }

    /// The names of the records whose copy in the cloud this version can't read.
    func unreadableRecordNames(in database: SQLiteDatabase) throws -> Set<String> {
        Set(try database.rows("SELECT name FROM parkedRecords WHERE unreadable = 1").compactMap { $0.text("name") })
    }

    /// A row of `parkedRecords` as the change it was when it arrived.
    static func parkedChange(from row: SQLRow) -> RemoteChange? {
        guard let name = row.text("name"), let kind = row.text("kind").flatMap(SyncKind.init(rawValue:)),
              let payload = row.blob("payload"), let fields = row.blob("systemFields") else { return nil }
        return .saved(SyncRecord(id: SyncRecordID(kind: kind, name: name), payload: payload, title: name),
                      systemFields: fields)
    }
}

extension RemoteChange {
    /// The record the change is about.
    var id: SyncRecordID {
        switch self {
        case .saved(let record, _): record.id
        case .deleted(let id): id
        }
    }
}
