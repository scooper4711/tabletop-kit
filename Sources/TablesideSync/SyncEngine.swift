import CloudKit
import Foundation

/// A deleted zone and why, as a fetch reports it.
typealias ZoneDeletion = (zoneID: CKRecordZone.ID, reason: CKDatabase.DatabaseChange.Deletion.Reason)

/// One `CKSyncEngine` for an app's private database, shared by the owners of its zones (library sync design, "The
/// engine"): it routes what is fetched and sent to the handler whose zone it is in, and queues what each handler
/// has to send. The CloudKit side is in `SyncEngineCloudKit`; everything here takes plain values, so tests reach it.
actor SyncEngine {
    private let handlers: [any SyncZoneHandler]
    private let store: any SyncStateStore
    private var queue: (any SyncChangeQueue)?
    /// The CloudKit engine, kept alive for as long as this one is.
    var engine: CKSyncEngine?

    init(handlers: [any SyncZoneHandler], store: any SyncStateStore) {
        self.handlers = handlers
        self.store = store
    }

    /// Sends changes to `queue` from now on. A start then queues what there is to send: `uploadEverything()` the
    /// first time, `handlersChanged()` every time after.
    func use(_ queue: any SyncChangeQueue) {
        self.queue = queue
    }

    /// Queues what every handler has to send now, as at every start but the first.
    func handlersChanged() async {
        for handler in handlers { await queueChanges(of: handler) }
    }

    /// Queues every handler's zones and what it has to send, as at a first start.
    func uploadEverything() async {
        for handler in handlers { await upload(handler) }
    }

    /// The record to save, from the handler whose zone it is in. With none to save, the save is forgotten: the
    /// engine would otherwise keep it pending forever.
    func record(for recordID: CKRecord.ID) async -> CKRecord? {
        guard let handler = await handler(owning: recordID.zoneID),
              let record = await handler.record(for: recordID) else {
            queue?.remove([.save(recordID)])
            return nil
        }
        return record
    }

    /// The zones no fetch may bring.
    func unfetchedZones() async -> [CKRecordZone.ID] {
        var zones: [CKRecordZone.ID] = []
        for handler in handlers { zones += await handler.unfetchedZones() }
        return zones
    }

    /// Hands fetched changes to the handlers whose zones they are in. Merging them can leave something to send.
    func receive(_ changes: FetchedChanges) async {
        for handler in handlers {
            let own = changes.within(Set(await handler.zones()))
            guard !own.isEmpty else { continue }
            await handler.received(own)
            await queueChanges(of: handler)
        }
    }

    /// Tells the handlers what the server took and what it refused, and queues again what settling left to send.
    func sent(_ changes: SentChanges) async {
        for handler in handlers {
            let own = changes.within(Set(await handler.zones()))
            guard !own.isEmpty else { continue }
            await handler.sent(saved: own.saved, deleted: own.gone)
            guard own.hasFailures else { continue }
            if await handler.settle(own.failedSaves) {
                await upload(handler)
            } else {
                await queueChanges(of: handler)
            }
        }
    }

    /// Tells the handlers whose iCloud this is now, and after a sign-in sends what they then have to send.
    func accountChanged(_ change: CKSyncEngine.Event.AccountChange.ChangeType) async {
        switch change {
        case .signIn(let user): await signedIn(as: user)
        case .switchAccounts(_, let user): await signedIn(as: user)
        case .signOut: for handler in handlers { await handler.accountChanged(to: nil) }
        @unknown default: break
        }
    }

    /// Tells every handler of the deleted zones, and uploads again for those that ask.
    func zonesDeleted(_ deletions: [ZoneDeletion]) async {
        for handler in handlers {
            var uploadsAgain = false
            for deletion in deletions {
                let asks = await handler.zoneDeleted(deletion.zoneID, reason: deletion.reason)
                uploadsAgain = uploadsAgain || asks
            }
            if uploadsAgain { await upload(handler) }
        }
    }

    func phaseChanged(_ phase: SyncPhase) async {
        for handler in handlers { await handler.phaseChanged(phase) }
    }

    func savedState() async -> Data? {
        await store.load()
    }

    func saveState(_ state: Data) async {
        await store.save(state)
    }

    // MARK: Helpers

    private func signedIn(as user: CKRecord.ID) async {
        for handler in handlers { await handler.accountChanged(to: user.recordName) }
        await uploadEverything()
    }

    private func upload(_ handler: any SyncZoneHandler) async {
        queue?.saveZones(await handler.zones())
        await queueChanges(of: handler)
    }

    private func queueChanges(of handler: any SyncZoneHandler) async {
        let changes = await handler.pendingChanges()
        if !changes.isEmpty { queue?.add(changes) }
    }

    private func handler(owning zoneID: CKRecordZone.ID) async -> (any SyncZoneHandler)? {
        for handler in handlers where await handler.zones().contains(zoneID) { return handler }
        return nil
    }
}
