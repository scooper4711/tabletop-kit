import Foundation
import SharedLibraries

/// The library's pictures (library sync design, "Pictures in iCloud"): what an app asks of them, and when their
/// upkeep runs.
extension LibrarySync {
    /// Downloads those of `names` this device lacks, and notes all of them as shown. An app calls it with
    /// `SharedLibrary.missingPictures(of:)` when `picture(of:)` gives none (R4.2). Returns those downloaded. It
    /// doesn't wait for whatever else syncing is doing.
    public nonisolated func fetchPictures(named names: [String]) async -> Set<String> {
        await pictures?.fetchPictures(named: names) ?? []
    }

    /// The size of the pictures downloaded from iCloud, in bytes (R4.3).
    public func fetchedPicturesByteCount() throws -> Int {
        try library.use { library in try library.fetchedPicturesByteCount() }
    }

    /// Removes the downloaded pictures from this device; each comes back from iCloud when next shown (R4.3).
    public func clearFetchedPictures() throws {
        try library.use { library in try library.clearFetchedPictures() }
    }

    public func picturePolicy() throws -> PicturePolicy {
        try library.use { library in try library.picturePolicy() }
    }

    /// Sets how this device keeps pictures (R4.7, R4.9). Keeping everything starts downloading what is missing.
    public func setPicturePolicy(_ policy: PicturePolicy) throws {
        try library.use { library in try library.setPicturePolicy(policy) }
        startPictureRun()
    }

    /// Notes that pictures were shown, for an app that reads their files itself.
    public func markPicturesShown(_ names: [String]) {
        library.use { library in try? library.markPicturesShown(names) }
    }

    /// Draws the pictures the art lacks, then sends what was held back for them and starts the pictures' upkeep.
    func drawPictures() async {
        await pictures?.drawMissingPictures()
        isDrawing = false
        await sendChanges()
        await syncPictures()
    }

    /// Runs the pictures' upkeep to its end, and shows how it went. When a run is under way, that one carries on
    /// for this call too.
    func syncPictures() async {
        guard let pictures, !isDrawing else { return }
        tracker.begin(.pictures)
        guard let outcome = await pictures.run() else { return }
        tracker.end(.pictures)
        switch outcome {
        case .storageFull: tracker.report(.storageFull)
        case .finished: if !isStorageFull { tracker.clear(.storageFull) }
        case .stopped: break
        }
    }

    /// Starts the pictures' upkeep without waiting for it.
    func startPictureRun() {
        guard pictures != nil else { return }
        Task { await self.syncPictures() }
    }

    /// A fetch has ended. When it brought every zone's changes and they are merged in, it is known which pictures
    /// art still uses, so the others can go; when it didn't, none may go until a fetch does.
    func fetchEnded() {
        guard let pictures else { return }
        let isWhole = !hasFetchFailed && !hasStopped
        Task {
            if isWhole {
                await pictures.fetchFinished()
            } else {
                await pictures.fetchFailed()
            }
            await self.syncPictures()
        }
    }
}
