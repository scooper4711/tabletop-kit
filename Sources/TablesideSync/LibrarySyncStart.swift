import CloudKit
import Foundation
import SharedLibraries

/// Starting to sync in an app. Unit tests can't reach this: a container without the entitlement stops the process.
extension LibrarySync {
    /// The `Info.plist` key that names the suite's iCloud container, in builds with the entitlements only (R6.1).
    public static let containerKey = "TablesideSyncContainer"

    /// The container this build names; empty in a build without the entitlements.
    public static var bundleContainer: String {
        Bundle.main.object(forInfoDictionaryKey: containerKey) as? String ?? ""
    }

    /// Starts syncing the shared library of `app` (in `fallback` for an app outside the App Group), with the
    /// handlers of the app's own zones on the same engine. Nil when the build names no container or iCloud isn't
    /// available: the app then works on this device only (R2.4), and `SyncStatus.withoutSync` says which it is.
    /// No container is made before the name is checked, as one the build has no entitlement for stops the app.
    public static func start(app: TablesideApp, fallback: URL, containerIdentifier: String = bundleContainer,
                             handlers: [any SyncZoneHandler] = []) async -> LibrarySync? {
        guard !containerIdentifier.isEmpty else { return nil }
        let container = CKContainer(identifier: containerIdentifier)
        let database = container.privateCloudDatabase
        guard (try? await container.accountStatus()) == .available,
              let folder = try? SharedLibrary.standard(app: app, fallback: fallback).folder,
              let sync = try? LibrarySync(folder: folder, app: app, pictureStore: CloudPictureStore(database: database))
        else { return nil }
        await sync.prepare()
        if let user = try? await container.userRecordID() { await sync.accountChanged(to: user.recordName) }
        let engine = SyncEngine(handlers: [sync] + handlers, store: sync)
        await sync.use(engine)
        await sync.observeChanges()
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? app.rawValue
        await engine.attach(to: database, subscriptionID: "tableside-sync-\(bundleIdentifier)")
        Task { await sync.drawPictures() }
        return sync
    }

    /// Follows the library's changes, made here or by another app on the device.
    private func observeChanges() {
        observer = SharedLibraryChange.observe { [weak self] in
            Task { await self?.libraryChanged() }
        }
    }
}
