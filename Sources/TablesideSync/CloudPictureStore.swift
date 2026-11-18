import CloudKit
import Foundation
import SharedLibraries

/// The zone `Pictures` of the user's private database: one record of the type `Picture` per picture, named by its
/// file, with the image as an asset. Unit tests can't reach this; the end-to-end check in docs/specs/library-sync
/// covers it.
struct CloudPictureStore: PictureStore {
    static let recordType = "Picture"
    let database: CKDatabase

    func existing(_ names: [String]) async throws -> Set<String> {
        let found = try await database.records(for: names.map(Self.recordID), desiredKeys: [])
        return Set(found.filter { (try? $0.value.get()) != nil }.map(\.key.recordName))
    }

    func upload(_ files: [String: URL]) async throws {
        let records = files.map { name, file in
            let record = CKRecord(recordType: Self.recordType, recordID: Self.recordID(name))
            record["image"] = CKAsset(fileURL: file)
            return record
        }
        let results = try await database.modifyRecords(saving: records, deleting: [], atomically: false)
        for result in results.saveResults.values {
            // A picture never changes, so one that is there already is the same one.
            if case .failure(let error) = result, (error as? CKError)?.code != .serverRecordChanged { throw error }
        }
    }

    /// Copies each asset out of CloudKit's cache, which doesn't keep it.
    func download(_ names: [String]) async throws -> [String: URL] {
        let found = try await database.records(for: names.map(Self.recordID))
        var files: [String: URL] = [:]
        for (recordID, result) in found {
            guard let asset = (try? result.get())?["image"] as? CKAsset, let source = asset.fileURL else { continue }
            let copy = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            try FileManager.default.copyItem(at: source, to: copy)
            files[recordID.recordName] = copy
        }
        return files
    }

    func delete(_ names: [String]) async throws {
        let results = try await database.modifyRecords(saving: [], deleting: names.map(Self.recordID),
                                                       atomically: false)
        for result in results.deleteResults.values {
            if case .failure(let error) = result, (error as? CKError)?.code != .unknownItem { throw error }
        }
    }

    private static func recordID(_ name: String) -> CKRecord.ID {
        CKRecord.ID(recordName: name, zoneID: LibraryRecordCoder.picturesZone)
    }
}
