import CloudKit
import Foundation
import SharedLibraries

/// Syncs the shared library through the user's private CloudKit database (docs/specs/library-sync): the owner of the
/// zones `Library` and `Pictures` on the app's `SyncEngine`. The store decides what to send and how a record from
/// another device is merged in; this hands records between it and the engine. It opens the library itself, as
/// `SharedLibrary` isn't safe to share.
public actor LibrarySync {
    let library: LibraryHandle
    let coder: LibraryRecordCoder
    /// The pictures' side of syncing; none in tests that leave pictures out.
    let pictures: PictureCloud?
    /// The records handed to the engine, by name, until the server takes them.
    var outgoing: [String: OutgoingRecord] = [:]
    var tracker = SyncStatusTracker()
    /// True once fetched records couldn't be merged in: nothing more is sent, and the engine's state is dropped,
    /// so the next launch fetches everything again.
    var hasStopped = false
    /// True from a save iCloud had no room for until something gives a reason to try again.
    var isStorageFull = false
    /// True from the start until the pictures art lacks are drawn. Nothing is sent meanwhile: each picture drawn
    /// changes its PDF's reading, and a library moved in from an app's old one would send every reading over and
    /// over.
    var isDrawing = false
    /// True when the fetch under way couldn't bring a zone's changes.
    var hasFetchFailed = false
    private var engine: SyncEngine?
    private var notice: Task<Void, Never>?
    private let changeDelay: Duration
    /// Kept so that the app hears of the library's changes for as long as it syncs.
    var observer: AnyObject?

    /// Syncing for the library in `folder`, with its pictures in `pictureStore`. Local changes are sent
    /// `changeDelay` after the last one, so a run of them goes up together.
    init(folder: URL, app: TablesideApp, changeDelay: Duration = .seconds(2),
         pictureStore: (any PictureStore)? = nil) throws {
        library = try LibraryHandle(folder: folder, app: app)
        pictures = try pictureStore.map { try PictureCloud(folder: folder, app: app, store: $0) }
        let outgoingFolder = folder.appending(path: "Sync/Outgoing/\(app.rawValue)", directoryHint: .isDirectory)
        coder = LibraryRecordCoder(outgoingFolder: outgoingFolder)
        self.changeDelay = changeDelay
    }

    /// Whether the library syncs.
    public var status: SyncStatus { tracker.status }

    /// The status now and after each change.
    public func statusUpdates() -> AsyncStream<SyncStatus> {
        tracker.updates()
    }

    /// Tells syncing the library changed, here or in another app on the device. What there is to send is queued
    /// once the changes stop coming. The pictures' run is started and not waited for: the next change cancels
    /// the wait, and must not cancel a transfer with it.
    public func libraryChanged() {
        notice?.cancel()
        notice = Task { [changeDelay] in
            try? await Task.sleep(for: changeDelay)
            guard !Task.isCancelled else { return }
            await self.sendChanges()
            self.startPictureRun()
        }
    }

    /// Turns syncing on again after the user deleted the library's iCloud data: everything is uploaded anew (R5.3).
    public func resume() async {
        library.use { library in try? library.setSyncPaused(false) }
        forgetServer()
        tracker.clear(.paused)
        await engine?.uploadEverything()
        startPictureRun()
    }

    /// Closes the library's database, as when the app goes to the background on the iPad; whatever syncing still
    /// does closes it again when done, until `open()`.
    public func close() async {
        library.close()
        await pictures?.close()
    }

    public func open() async {
        library.open()
        await pictures?.open()
    }

    /// Gets the library ready before the engine starts: clears what an earlier run left of its uploads, applies
    /// the records kept aside that this version can now read, measures the pictures saved before sizes were kept,
    /// so two devices settle on the sharper one, and shows a pause that is still on. With pictures to look after,
    /// nothing is sent until `drawPictures()` has drawn those the art lacks.
    func prepare() {
        isDrawing = pictures != nil
        coder.removeOutgoingFiles()
        apply([])
        library.use { library in
            _ = try? library.measurePictures()
            if (try? library.isSyncPaused) == true { tracker.report(.paused) }
        }
    }

    /// The engine that sends what this has to send.
    func use(_ engine: SyncEngine) {
        self.engine = engine
    }

    /// Queues what there is to send now.
    func sendChanges() async {
        isStorageFull = false
        await engine?.handlersChanged()
    }

    /// Merges changes from the server into the library, trying once more when that fails. When it fails again,
    /// syncing stops for this run.
    func apply(_ changes: [RemoteChange]) {
        var failure: Error?
        for _ in 1...2 {
            do {
                try library.use { library in _ = try library.applyRemote(changes) }
                return
            } catch {
                failure = error
            }
        }
        if let failure { stop(after: failure) }
    }

    /// Stops syncing after the user deleted the library's iCloud data, until `resume()`.
    func pause() {
        library.use { library in
            try? library.setSyncPaused(true)
            try? library.forgetServer()
        }
        outgoing = [:]
        tracker.report(.paused)
    }

    /// Forgets what the server held: every record is then sent again, and merged with what is there. An iCloud
    /// that was full is tried again, as what the server holds now isn't what filled it.
    func forgetServer() {
        library.use { library in try? library.forgetServer() }
        outgoing = [:]
        isStorageFull = false
    }

    // MARK: Helpers

    private func stop(after error: Error) {
        hasStopped = true
        tracker.report(.failed("\(error)"))
        library.use { library in try? library.setEngineState(nil) }
    }
}
