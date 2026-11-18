import CloudKit
import Foundation

/// A change to send to the cloud: a record to save, or one to delete.
public enum SyncChange: Hashable, Sendable {
    case save(CKRecord.ID)
    case delete(CKRecord.ID)

    var recordID: CKRecord.ID {
        switch self {
        case .save(let recordID), .delete(let recordID): recordID
        }
    }
}

/// What a fetch brought: the records other devices saved and those they deleted.
public struct FetchedChanges: Sendable {
    public struct Deletion: Sendable {
        public var recordID: CKRecord.ID
        public var recordType: CKRecord.RecordType

        public init(recordID: CKRecord.ID, recordType: CKRecord.RecordType) {
            self.recordID = recordID
            self.recordType = recordType
        }
    }

    public var modifications: [CKRecord]
    public var deletions: [Deletion]

    public init(modifications: [CKRecord] = [], deletions: [Deletion] = []) {
        self.modifications = modifications
        self.deletions = deletions
    }

    var isEmpty: Bool { modifications.isEmpty && deletions.isEmpty }

    /// The changes to records of `zones`.
    func within(_ zones: Set<CKRecordZone.ID>) -> FetchedChanges {
        FetchedChanges(modifications: modifications.filter { zones.contains($0.recordID.zoneID) },
                       deletions: deletions.filter { zones.contains($0.recordID.zoneID) })
    }
}

/// A save the server refused, with the reason.
public typealias FailedSave = (record: CKRecord, error: CKError)

/// Where the engine is in a round of syncing, for a handler that shows it or waits for it.
public enum SyncPhase: Sendable {
    case willFetch, didFetch, willSend, didSend
    /// A zone's changes couldn't be fetched, in the fetch under way: `didFetch` still follows.
    case fetchFailed
}

/// What the owner of one or more zones does for the engine that syncs them (library sync design, "The engine"). The
/// library is one owner; Turnkeeper's campaigns and Pawn Shop's custom pawns become others, on the same engine.
public protocol SyncZoneHandler: Sendable {
    /// The zones the handler's records live in; the engine creates them.
    func zones() async -> [CKRecordZone.ID]
    /// Zones of its own the engine must never fetch, such as pictures fetched on demand.
    func unfetchedZones() async -> [CKRecordZone.ID]
    /// What the handler has to send now. The engine asks at each start, after it hands the handler anything, and
    /// whenever it is told the handlers changed.
    func pendingChanges() async -> [SyncChange]
    /// The record to save; nil when there is nothing to save after all, and the engine then forgets the save.
    func record(for recordID: CKRecord.ID) async -> CKRecord?
    func received(_ changes: FetchedChanges) async
    /// The server took these: `deleted` includes records it turned out not to have.
    func sent(saved: [CKRecord], deleted: [CKRecord.ID]) async
    /// Settles refused saves; returns true when the handler's zones must be saved again.
    func settle(_ failures: [FailedSave]) async -> Bool
    /// The iCloud account the engine now syncs with, as CloudKit names its user; nil once signed out. The engine
    /// tells this at its first start too, so a handler forgets the server only when the account isn't the one it
    /// knew.
    func accountChanged(to user: String?) async
    /// A zone was deleted; every handler hears of it. Returns true when its zones must be saved again, with
    /// everything it has.
    func zoneDeleted(_ zoneID: CKRecordZone.ID, reason: CKDatabase.DatabaseChange.Deletion.Reason) async -> Bool
    func phaseChanged(_ phase: SyncPhase) async
}

extension SyncZoneHandler {
    public func unfetchedZones() async -> [CKRecordZone.ID] { [] }
    public func phaseChanged(_ phase: SyncPhase) async {}
}

/// Where the engine queues changes to send: `CKSyncEngine`'s state, or a recorder in tests.
protocol SyncChangeQueue: Sendable {
    func saveZones(_ zoneIDs: [CKRecordZone.ID])
    func add(_ changes: [SyncChange])
    func remove(_ changes: [SyncChange])
}

/// Where the engine's state is kept between launches.
protocol SyncStateStore: Sendable {
    func load() async -> Data?
    func save(_ state: Data) async
}

/// What a send did, as `CKSyncEngine` reports it.
struct SentChanges: Sendable {
    var saved: [CKRecord] = []
    var failedSaves: [FailedSave] = []
    var deleted: [CKRecord.ID] = []
    var failedDeletes: [CKRecord.ID: CKError] = [:]

    var isEmpty: Bool { saved.isEmpty && failedSaves.isEmpty && deleted.isEmpty && failedDeletes.isEmpty }
    var hasFailures: Bool { !failedSaves.isEmpty || !failedDeletes.isEmpty }

    /// The records the server no longer holds: those it deleted, and those it never had.
    var gone: [CKRecord.ID] {
        deleted + failedDeletes.filter { $0.value.code == .unknownItem }.map(\.key)
    }

    /// The outcome for records of `zones`.
    func within(_ zones: Set<CKRecordZone.ID>) -> SentChanges {
        SentChanges(saved: saved.filter { zones.contains($0.recordID.zoneID) },
                    failedSaves: failedSaves.filter { zones.contains($0.record.recordID.zoneID) },
                    deleted: deleted.filter { zones.contains($0.zoneID) },
                    failedDeletes: failedDeletes.filter { zones.contains($0.key.zoneID) })
    }
}
