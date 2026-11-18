import CloudKit
import Foundation

/// The CloudKit side of the engine: starting `CKSyncEngine` and handing its events to the actor's entry points. Unit
/// tests can't reach this (a container without the entitlement stops the process, and engine events have no public
/// initializers); the end-to-end check in docs/specs/library-sync covers it.
extension SyncEngine {
    /// Starts syncing `database`. Each app keeps a subscription of its own, by `subscriptionID`.
    func attach(to database: CKDatabase, subscriptionID: String) async {
        let saved = await savedState().flatMap {
            try? PropertyListDecoder().decode(CKSyncEngine.State.Serialization.self, from: $0)
        }
        var configuration = CKSyncEngine.Configuration(database: database, stateSerialization: saved, delegate: self)
        configuration.subscriptionID = subscriptionID
        let engine = CKSyncEngine(configuration)
        self.engine = engine
        use(EngineQueue(engine: engine))
        if saved == nil {
            await uploadEverything()
        } else {
            await handlersChanged()
        }
    }
}

extension SyncEngine: CKSyncEngineDelegate {
    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        switch event {
        case .stateUpdate(let update):
            guard let state = try? PropertyListEncoder().encode(update.stateSerialization) else { return }
            await saveState(state)
        case .accountChange(let change):
            await accountChanged(change.changeType)
        case .fetchedDatabaseChanges(let changes):
            await zonesDeleted(changes.deletions.map { (zoneID: $0.zoneID, reason: $0.reason) })
        case .fetchedRecordZoneChanges(let changes):
            let deletions = changes.deletions.map {
                FetchedChanges.Deletion(recordID: $0.recordID, recordType: $0.recordType)
            }
            await receive(FetchedChanges(modifications: changes.modifications.map(\.record), deletions: deletions))
        case .sentRecordZoneChanges(let sent):
            let refused = sent.failedRecordSaves.map { (record: $0.record, error: $0.error) }
            await self.sent(SentChanges(saved: sent.savedRecords, failedSaves: refused,
                                        deleted: sent.deletedRecordIDs, failedDeletes: sent.failedRecordDeletes))
        default:
            if let phase = SyncPhase(event) { await phaseChanged(phase) }
        }
    }

    func nextRecordZoneChangeBatch(_ context: CKSyncEngine.SendChangesContext,
                                   syncEngine: CKSyncEngine) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let changes = syncEngine.state.pendingRecordZoneChanges.filter { context.options.scope.contains($0) }
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: changes) { recordID in
            await self.record(for: recordID)
        }
    }

    func nextFetchChangesOptions(_ context: CKSyncEngine.FetchChangesContext,
                                 syncEngine: CKSyncEngine) async -> CKSyncEngine.FetchChangesOptions {
        CKSyncEngine.FetchChangesOptions(scope: .allExcluding(await unfetchedZones()))
    }
}

extension SyncPhase {
    /// The phase an engine event starts or ends; nil for any other event.
    init?(_ event: CKSyncEngine.Event) {
        switch event {
        case .willFetchChanges: self = .willFetch
        case .didFetchChanges: self = .didFetch
        case .willSendChanges: self = .willSend
        case .didSendChanges: self = .didSend
        default: return nil
        }
    }
}

/// Queues changes in a sync engine's state.
struct EngineQueue: SyncChangeQueue {
    let engine: CKSyncEngine

    func saveZones(_ zoneIDs: [CKRecordZone.ID]) {
        engine.state.add(pendingDatabaseChanges: zoneIDs.map { .saveZone(CKRecordZone(zoneID: $0)) })
    }

    func add(_ changes: [SyncChange]) {
        engine.state.add(pendingRecordZoneChanges: changes.map(\.pending))
    }

    func remove(_ changes: [SyncChange]) {
        engine.state.remove(pendingRecordZoneChanges: changes.map(\.pending))
    }
}

extension SyncChange {
    fileprivate var pending: CKSyncEngine.PendingRecordZoneChange {
        switch self {
        case .save(let recordID): .saveRecord(recordID)
        case .delete(let recordID): .deleteRecord(recordID)
        }
    }
}
