import CloudKit
import Foundation
import SharedLibraries

/// What the library's zones need of the engine (library sync design, "The library's handler").
extension LibrarySync: SyncZoneHandler {
    public func zones() -> [CKRecordZone.ID] {
        [LibraryRecordCoder.libraryZone, LibraryRecordCoder.picturesZone]
    }

    /// Pictures are fetched one by one when shown, never by the engine.
    public func unfetchedZones() -> [CKRecordZone.ID] {
        [LibraryRecordCoder.picturesZone]
    }

    /// The records the store has to save and to delete; none once syncing stopped, while iCloud is full, or
    /// until the pictures are drawn.
    public func pendingChanges() -> [SyncChange] {
        guard !hasStopped, !isStorageFull, !isDrawing,
              let candidates = library.use({ library in try? library.syncCandidates() }) else { return [] }
        return candidates.saves.map { .save(LibraryRecordCoder.recordID(of: $0)) }
            + candidates.deletions.map { .delete(LibraryRecordCoder.recordID(of: $0)) }
    }

    /// The record to save, remembered until the server takes it; nil when its row is gone, when the cloud holds
    /// this content already, while syncing is paused or stopped, or until the pictures are drawn.
    public func record(for recordID: CKRecord.ID) -> CKRecord? {
        guard !hasStopped, !isDrawing, let id = LibraryRecordCoder.syncID(of: recordID) else { return nil }
        let built = library.use { library -> (OutgoingRecord, CKRecord)? in
            guard (try? library.isSyncPaused) == false, let outgoing = try? library.outgoingRecord(id),
                  let record = try? coder.record(for: outgoing) else { return nil }
            return (outgoing, record)
        }
        guard let built else { return nil }
        outgoing[id.name] = built.0
        return built.1
    }

    public func received(_ changes: FetchedChanges) {
        isStorageFull = false
        let deletions = changes.deletions.compactMap { LibraryRecordCoder.syncID(of: $0.recordID) }
        apply(changes.modifications.compactMap(LibraryRecordCoder.remoteChange(from:))
            + deletions.map(RemoteChange.deleted))
    }

    public func sent(saved: [CKRecord], deleted: [CKRecord.ID]) {
        library.use { library in
            for record in saved {
                coder.removeOutgoingFile(of: record.recordID)
                guard let sent = outgoing.removeValue(forKey: record.recordID.recordName) else { continue }
                try? library.markSent(sent, systemFields: LibraryRecordCoder.systemFields(of: record))
            }
            for id in deleted.compactMap(LibraryRecordCoder.syncID(of:)) {
                try? library.markDeleted(id)
            }
        }
        if !saved.isEmpty { tracker.clear(.storageFull) }
    }

    /// Settles refused saves. A record the server holds in another version is merged in as a fetched one is, and
    /// the store then says whether the result still has to be sent. A zone the server lacks holds none of the
    /// records, so the server is forgotten and everything goes up with the zones. Anything not named here the
    /// engine retries.
    public func settle(_ failures: [FailedSave]) -> Bool {
        var savesZones = false
        var conflicts: [RemoteChange] = []
        for failure in failures {
            switch failure.error.code {
            case .serverRecordChanged:
                let server = failure.error.serverRecord.flatMap(LibraryRecordCoder.remoteChange(from:))
                if let server { conflicts.append(server) }
            case .unknownItem:
                forgetSystemFields(of: failure.record.recordID)
            case .zoneNotFound:
                savesZones = true
            case .userDeletedZone:
                pause()
            case .quotaExceeded:
                isStorageFull = true
                tracker.report(.storageFull)
            default:
                break
            }
        }
        if savesZones { forgetServer() }
        if !conflicts.isEmpty { apply(conflicts) }
        return savesZones
    }

    /// Forgets the server when the account isn't the one the library last synced with (R5.1). The engine tells
    /// the account at an app's first start too, and then the library keeps what another app on the device learned.
    public func accountChanged(to user: String?) {
        guard let user else { return tracker.report(.unavailable) }
        tracker.clear(.unavailable)
        let isKnown = library.use { library in (try? library.syncAccount()) == user }
        guard !isKnown else { return }
        forgetServer()
        library.use { library in try? library.setSyncAccount(user) }
    }

    /// iCloud data the user deleted pauses syncing (R5.3); a zone deleted any other way is uploaded again (R5.2).
    public func zoneDeleted(_ zoneID: CKRecordZone.ID, reason: CKDatabase.DatabaseChange.Deletion.Reason) -> Bool {
        guard zones().contains(zoneID) else { return false }
        if reason == .purged {
            pause()
            return false
        }
        forgetServer()
        return true
    }

    public func phaseChanged(_ phase: SyncPhase) {
        switch phase {
        case .willFetch: tracker.begin(.fetching)
        case .didFetch:
            tracker.end(.fetching)
            fetchFinished()
        case .willSend:
            tracker.begin(.sending)
        case .didSend:
            // The first send makes the zones, so a run of pictures that found none can carry on.
            tracker.end(.sending)
            startPictureRun()
        }
    }

    private func forgetSystemFields(of recordID: CKRecord.ID) {
        guard let id = LibraryRecordCoder.syncID(of: recordID) else { return }
        library.use { library in try? library.forgetSystemFields(of: id) }
    }
}

/// The engine's state is kept with the library, so a restored backup carries a state that matches its rows.
extension LibrarySync: SyncStateStore {
    func load() -> Data? {
        library.use { library in try? library.engineState() }
    }

    /// Keeps the state, unless syncing stopped: the state was dropped then, and stays dropped.
    func save(_ state: Data) {
        guard !hasStopped else { return }
        library.use { library in try? library.setEngineState(state) }
    }
}
