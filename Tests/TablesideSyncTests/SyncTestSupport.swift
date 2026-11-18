import ArtExtractionTestSupport
import CloudKit
import CoreGraphics
import Foundation
import os
import SharedLibraries
@testable import TablesideSync

/// A device for the sync tests: a library folder of its own and a drawn PDF to read.
struct TestDevice {
    let root = temporaryFolder()

    var folder: URL { root.appending(path: "Tableside") }
    /// The library folder of another device, which reads the same PDF.
    var otherFolder: URL { root.appending(path: "Other device") }

    func library(_ app: TablesideApp = .turnkeeper) throws -> SharedLibrary {
        try SharedLibrary(folder: folder, app: app)
    }

    func otherLibrary() throws -> SharedLibrary {
        try SharedLibrary(folder: otherFolder, app: .fieldGuide)
    }

    /// Sends everything `library` has to send, and gives the records as the server then holds them.
    func serverRecords(of library: SharedLibrary) throws -> [CKRecord] {
        let coder = LibraryRecordCoder(outgoingFolder: root.appending(path: "Server"))
        return try library.syncCandidates().saves.compactMap { id in
            guard let outgoing = try library.outgoingRecord(id) else { return nil }
            let record = try coder.record(for: outgoing)
            try library.markSent(outgoing, systemFields: LibraryRecordCoder.systemFields(of: record))
            return record
        }
    }

    /// A pawn box PDF of a goblin and an ogre in this device's root folder. Asking again gives the same file, as
    /// drawing it again gives different bytes.
    func pawnBox() throws -> URL {
        let name = "Pathfinder Test Pawn Box PDF.pdf"
        let file = root.appending(path: name)
        if FileManager.default.fileExists(atPath: file.path) { return file }
        let pawns = [("GOBLIN WARRIOR", 20), ("OGRE", 120)].enumerated().map { index, pawn in
            DrawnPawn(rect: CGRect(x: pawn.1, y: 600, width: 81, height: 138), art: creatureArt(variant: index),
                      name: pawn.0)
        }
        return try writePawnPDF(pawns, named: name, in: root)
    }

    /// Reads the pawn box into the library, and adds one row of every other kind that syncs.
    @discardableResult
    func fillWithEveryKind(_ library: SharedLibrary) throws -> UUID {
        try library.add(pawnBox(), keeping: false)
        let art = try library.artEntries().map(\.id).sorted { $0.uuidString < $1.uuidString }[0]
        _ = try library.setNote(ArtNote(tags: ["club"]), forArt: art)
        try library.setCreatureArt(.library(art), for: "bestiary.goblin warrior")
        try library.save(CustomCreatureRecord(id: UUID(), campaignID: nil, sharedVersion: nil,
                                              record: Data("Gremlin".utf8)))
        try library.save(CustomArtRecord(id: UUID(), fileName: "gremlin.png", sharedVersion: nil, record: Data()),
                         image: Data([1, 2, 3]))
        return art
    }
}

extension CKRecord.ID {
    /// The ID of a record of the library's zone.
    static func library(_ name: String) -> CKRecord.ID {
        CKRecord.ID(recordName: name, zoneID: LibraryRecordCoder.libraryZone)
    }
}

/// The saved record a change holds; nil for a deletion.
func savedRecord(_ change: RemoteChange?) -> SyncRecord? {
    if case .saved(let record, _) = change { record } else { nil }
}

/// Records what the engine queues to send.
final class RecordingQueue: SyncChangeQueue {
    private struct Queued {
        var zones: [CKRecordZone.ID] = []
        var added: [SyncChange] = []
        var removed: [SyncChange] = []
    }

    private let queued = OSAllocatedUnfairLock(initialState: Queued())

    var zones: [CKRecordZone.ID] { queued.withLock { $0.zones } }
    var added: [SyncChange] { queued.withLock { $0.added } }
    var removed: [SyncChange] { queued.withLock { $0.removed } }

    func saveZones(_ zoneIDs: [CKRecordZone.ID]) { queued.withLock { $0.zones += zoneIDs } }
    func add(_ changes: [SyncChange]) { queued.withLock { $0.added += changes } }
    func remove(_ changes: [SyncChange]) { queued.withLock { $0.removed += changes } }

    /// Forgets what was queued so far, to tell what a later step queues.
    func clear() { queued.withLock { $0 = Queued() } }
}

/// Keeps the engine's state in memory.
actor MemoryStateStore: SyncStateStore {
    private(set) var state: Data?

    func load() -> Data? { state }
    func save(_ state: Data) { self.state = state }
}

/// A `serverRecordChanged` refusal, with the record the server holds.
func conflict(with server: CKRecord) -> CKError {
    CKError(.serverRecordChanged, userInfo: [CKRecordChangedErrorServerRecordKey: server])
}

/// A device that syncs: its library's handler on an engine that records what it queues.
struct SyncingDevice {
    let device = TestDevice()
    let queue = RecordingQueue()
    let sync: LibrarySync
    let engine: SyncEngine

    init() async throws {
        sync = try LibrarySync(folder: device.folder, app: .turnkeeper, changeDelay: .milliseconds(20))
        await sync.prepare()
        engine = SyncEngine(handlers: [sync], store: sync)
        await sync.use(engine)
        await engine.begin(with: queue, isFirstStart: true)
    }

    /// Hands the engine every record the handler has to save, as though the server took them all.
    @discardableResult
    func sendEverything() async -> [CKRecord] {
        var records: [CKRecord] = []
        for change in await sync.pendingChanges() {
            guard case .save(let recordID) = change, let record = await engine.record(for: recordID) else { continue }
            records.append(record)
        }
        await engine.sent(SentChanges(saved: records))
        return records
    }
}

/// Waits up to two seconds for `condition`; false when it never held.
func eventually(_ condition: @Sendable () async -> Bool) async -> Bool {
    for _ in 0..<200 {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return false
}

/// A stand-in for the zone `Pictures`, which records what it is asked.
actor FakePictureStore: PictureStore {
    private(set) var held: [String: Data] = [:]
    private(set) var asked: [[String]] = []
    private(set) var uploads: [[String]] = []
    private(set) var downloads: [[String]] = []
    private(set) var deletions: [[String]] = []
    private var failure: CKError.Code?
    private var isHolding = false
    private let folder = temporaryFolder()

    func hold(_ data: Data, as name: String) { held[name] = data }
    /// Makes every request fail with `code` until it is nil again.
    func fail(with code: CKError.Code?) { failure = code }
    /// Keeps `existing` from answering while true, so a run stays under way.
    func keepWaiting(_ waits: Bool) { isHolding = waits }

    func existing(_ names: [String]) async throws -> Set<String> {
        asked.append(names)
        while isHolding { try await Task.sleep(for: .milliseconds(5)) }
        try check()
        return Set(names.filter { held[$0] != nil })
    }

    func upload(_ files: [String: URL]) throws {
        try check()
        uploads.append(files.keys.sorted())
        for (name, file) in files { held[name] = try Data(contentsOf: file) }
    }

    func download(_ names: [String]) throws -> [String: URL] {
        try check()
        downloads.append(names)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var files: [String: URL] = [:]
        for name in names {
            guard let data = held[name] else { continue }
            let file = folder.appending(path: UUID().uuidString)
            try data.write(to: file)
            files[name] = file
        }
        return files
    }

    func delete(_ names: [String]) throws {
        try check()
        deletions.append(names)
        for name in names { held[name] = nil }
    }

    private func check() throws {
        if let failure { throw CKError(failure) }
    }
}

extension TestDevice {
    /// Makes this device's library thin: it holds the art another device read and none of its pictures, which
    /// `store` holds. Returns the library and the pictures' names.
    func thinLibrary(with store: FakePictureStore) async throws -> (SharedLibrary, [String]) {
        let other = try otherLibrary()
        try other.add(pawnBox(), keeping: false)
        let names = try other.picturesToUpload(limit: 100)
        for name in names {
            await store.hold(try Data(contentsOf: other.pictureFile(name)), as: name)
        }
        let library = try library()
        try library.applyRemote(try serverRecords(of: other).compactMap(LibraryRecordCoder.remoteChange(from:)))
        return (library, names)
    }
}
