import CloudKit
import Foundation
import SharedLibraries

/// Where pictures are kept in the cloud: CloudKit's zone `Pictures`, or a stand-in in tests.
protocol PictureStore: Sendable {
    /// Those of `names` the cloud holds, found without downloading any.
    func existing(_ names: [String]) async throws -> Set<String>
    /// Saves the files as pictures, by name. A picture the cloud turns out to hold already is no failure.
    func upload(_ files: [String: URL]) async throws
    /// Downloads those of `names` the cloud holds, each to a file the caller takes over.
    func download(_ names: [String]) async throws -> [String: URL]
    func delete(_ names: [String]) async throws
}

/// How a run of the pictures' upkeep ended.
enum PictureRunOutcome: Equatable, Sendable {
    case finished
    /// iCloud had no room for a picture.
    case storageFull
    /// Something failed, as without a network: the next run carries on from there.
    case stopped
}

/// Keeps the library's pictures in step with iCloud (library sync design, "Pictures in iCloud"): uploads those this
/// device has, downloads them when they are shown or, for a device that keeps everything, ahead of time, and deletes
/// those no art uses any more. It has a library of its own, so that drawing and transfers keep nothing else waiting.
actor PictureCloud {
    /// How many pictures go in one request.
    static let batchSize = 25
    /// How many pictures are drawn at a time.
    static let drawingBatchSize = 100

    private let library: LibraryHandle
    private let store: any PictureStore
    private var isRunning = false
    private var runsAgain = false
    private var hasFetched = false
    /// The pictures iCloud didn't have when asked: no device has uploaded them yet. They aren't asked for again
    /// until the app next starts.
    private var absent: Set<String> = []

    init(folder: URL, app: TablesideApp, store: any PictureStore) throws {
        library = try LibraryHandle(folder: folder, app: app)
        self.store = store
    }

    /// Draws the pictures art lacks from the PDFs this app can reach, so they can be uploaded (R4.8): a library
    /// moved in from an app's old one has none. It stops for now when one can't be drawn or saved and nothing
    /// else could be, as with a full disk.
    func drawMissingPictures() async {
        while drawBatch() > 0 { await Task.yield() }
    }

    /// Uploads the pictures iCloud lacks, downloads the missing ones for a device that keeps everything, and,
    /// once a fetch has finished, deletes those nothing uses. Nil when a run is under way: that one then goes
    /// round again, so nothing this call was for is missed.
    func run() async -> PictureRunOutcome? {
        guard !isRunning else {
            runsAgain = true
            return nil
        }
        isRunning = true
        defer { isRunning = false }
        var outcome = PictureRunOutcome.finished
        repeat {
            runsAgain = false
            outcome = await runOnce()
        } while runsAgain && outcome == .finished
        return outcome
    }

    /// Downloads those of `names` this device lacks, and notes all of them as shown. Returns those downloaded.
    func fetchPictures(named names: [String]) async -> Set<String> {
        let missing = library.use { library in
            names.filter { !FileManager.default.fileExists(atPath: library.pictureFile($0).path) }
        }
        let fetched = missing.isEmpty ? [] : (try? await fetch(missing)) ?? []
        library.use { library in try? library.markPicturesShown(names) }
        return fetched
    }

    /// Notes that a fetch has finished in this run of the app: only then is it known what art still uses.
    func fetchFinished() {
        hasFetched = true
    }

    func close() {
        library.close()
    }

    func open() {
        library.open()
    }

    // MARK: Helpers

    private func drawBatch() -> Int {
        (try? library.use { library in try library.drawMissingPictures(limit: Self.drawingBatchSize) }) ?? 0
    }

    private func runOnce() async -> PictureRunOutcome {
        do {
            guard try library.use({ library in try !library.isSyncPaused }) else { return .finished }
            try await uploadPictures()
            try await downloadEverything()
            try await deleteUnusedPictures()
            return .finished
        } catch let error as CKError where error.code == .quotaExceeded {
            return .storageFull
        } catch {
            return .stopped
        }
    }

    /// Uploads a batch at a time until none is left. Those iCloud holds already are only noted.
    private func uploadPictures() async throws {
        while true {
            let names = try library.use { library in try library.picturesToUpload(limit: Self.batchSize) }
            guard !names.isEmpty else { return }
            let held = try await store.existing(names)
            let files = library.use { library in
                Dictionary(uniqueKeysWithValues: names.filter { !held.contains($0) }
                    .map { ($0, library.pictureFile($0)) })
            }
            if !files.isEmpty { try await store.upload(files) }
            try library.use { library in try library.markPicturesUploaded(names) }
        }
    }

    /// For a device that keeps every picture (R4.9): downloads the missing ones a batch at a time, until none is
    /// missing or a batch brings nothing.
    private func downloadEverything() async throws {
        guard try library.use({ library in try library.picturePolicy() }) == .everything else { return }
        while true {
            let names = try library.use { library in
                try library.missingPictureNames(limit: Self.batchSize + absent.count)
            }.filter { !absent.contains($0) }.prefix(Self.batchSize)
            guard !names.isEmpty else { return }
            let fetched = try await fetch(Array(names))
            absent.formUnion(Set(names).subtracting(fetched))
            guard !fetched.isEmpty else { return }
        }
    }

    /// Deletes from iCloud the pictures no art names any more, then their files here (R4.4).
    private func deleteUnusedPictures() async throws {
        guard hasFetched else { return }
        var names = try library.use { library in try library.picturesToDelete() }[...]
        while !names.isEmpty {
            let batch = Array(names.prefix(Self.batchSize))
            names = names.dropFirst(batch.count)
            try await store.delete(batch)
            try library.use { library in try library.markPicturesDeleted(batch) }
        }
        try library.use { library in _ = try library.removeUnreferencedPictures() }
    }

    private func fetch(_ names: [String]) async throws -> Set<String> {
        let files = try await store.download(names)
        try library.use { library in
            for (name, file) in files { try library.storeFetchedPicture(named: name, from: file) }
        }
        return Set(files.keys)
    }
}
