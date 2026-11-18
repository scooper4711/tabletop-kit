import CloudKit
import Foundation
import SharedLibraries

/// Turns the library's records into CloudKit records and back (library sync design, "Records in CloudKit"). A PDF's
/// reading travels as an asset, since it can pass a record's 1 MB limit; every other payload as bytes in the record.
struct LibraryRecordCoder: Sendable {
    /// The layout of a record's fields. A later layout this version can't read is kept aside, as an unreadable
    /// payload is, but without its bytes: the version that raises this must make each device fetch again what
    /// its earlier versions kept aside (library sync design, "Records in CloudKit").
    static let format: Int64 = 1
    static let libraryZone = CKRecordZone.ID(zoneName: SyncZone.library, ownerName: CKCurrentUserDefaultName)
    static let picturesZone = CKRecordZone.ID(zoneName: SyncZone.pictures, ownerName: CKCurrentUserDefaultName)

    /// Where a reading's JSON is written for uploading, one file per record, until the record is sent.
    let outgoingFolder: URL

    /// The record to save for `outgoing`, over the server's last known copy when there is one, so the save is a
    /// change to it and not a conflict.
    func record(for outgoing: OutgoingRecord) throws -> CKRecord {
        let content = outgoing.record
        let record = outgoing.systemFields.flatMap(Self.record(withSystemFields:))
            ?? CKRecord(recordType: Self.recordType(of: content.id.kind), recordID: Self.recordID(of: content.id))
        record["format"] = Self.format
        record["title"] = content.title
        if content.id.kind == .source {
            record["payload"] = CKAsset(fileURL: try writeOutgoing(content))
        } else {
            record["payload"] = content.payload
        }
        if let image = content.file, FileManager.default.fileExists(atPath: image.path) {
            record["image"] = CKAsset(fileURL: image)
        }
        return record
    }

    /// Deletes the file written for a record's upload, once the record is sent.
    func removeOutgoingFile(of recordID: CKRecord.ID) {
        try? FileManager.default.removeItem(at: outgoingFile(named: recordID.recordName))
    }

    /// Deletes every file written for an upload: what a run that ended early left behind.
    func removeOutgoingFiles() {
        try? FileManager.default.removeItem(at: outgoingFolder)
    }

    /// What a record from the server means to the library; nil when it isn't one of the library's records. An
    /// asset's bytes are read here, as its file doesn't outlive the event that brought it. A record whose payload
    /// can't be read comes back with an empty one, which the library keeps aside for a version that can read it.
    static func remoteChange(from record: CKRecord) -> RemoteChange? {
        guard let id = syncID(of: record.recordID), recordType(of: id.kind) == record.recordType else { return nil }
        var content = SyncRecord(id: id, payload: payload(of: record), title: record["title"] as? String ?? "")
        content.file = (record["image"] as? CKAsset)?.fileURL
        return .saved(content, systemFields: systemFields(of: record))
    }

    /// The record type of each kind, as the CloudKit schema names it.
    static func recordType(of kind: SyncKind) -> CKRecord.RecordType {
        switch kind {
        case .source: "Source"
        case .note: "Note"
        case .creatureArt: "CreatureArt"
        case .customCreature: "CustomCreature"
        case .customArt: "CustomArt"
        }
    }

    static func recordID(of id: SyncRecordID) -> CKRecord.ID {
        CKRecord.ID(recordName: id.name, zoneID: libraryZone)
    }

    /// The library's record a CloudKit record ID names; nil for a record of another zone or of no known kind.
    static func syncID(of recordID: CKRecord.ID) -> SyncRecordID? {
        recordID.zoneID == libraryZone ? SyncRecordID(recordName: recordID.recordName) : nil
    }

    /// A record's system fields, archived: its change tag, so the next save of it doesn't conflict with itself.
    static func systemFields(of record: CKRecord) -> Data {
        let archiver = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: archiver)
        archiver.finishEncoding()
        return archiver.encodedData
    }

    /// The server's copy of a record, with its system fields only; nil when `data` isn't an archive of them.
    static func record(withSystemFields data: Data) -> CKRecord? {
        guard let unarchiver = try? NSKeyedUnarchiver(forReadingFrom: data) else { return nil }
        unarchiver.requiresSecureCoding = true
        defer { unarchiver.finishDecoding() }
        return CKRecord(coder: unarchiver)
    }

    // MARK: Helpers

    private func writeOutgoing(_ content: SyncRecord) throws -> URL {
        let file = outgoingFile(named: content.id.name)
        do {
            try FileManager.default.createDirectory(at: outgoingFolder, withIntermediateDirectories: true)
            try content.payload.write(to: file, options: .atomic)
        } catch {
            throw SharedLibraryError(operation: "Preparing \(content.id.name) for iCloud",
                                     detail: error.localizedDescription)
        }
        return file
    }

    private func outgoingFile(named name: String) -> URL {
        outgoingFolder.appending(path: name, directoryHint: .notDirectory)
    }

    /// A record's payload; empty in a later layout than this version reads, or when its asset can't be read.
    private static func payload(of record: CKRecord) -> Data {
        guard record["format"] as? Int64 ?? format <= format else { return Data() }
        if let bytes = record["payload"] as? Data { return bytes }
        let file = (record["payload"] as? CKAsset)?.fileURL
        return file.flatMap { try? Data(contentsOf: $0) } ?? Data()
    }
}
