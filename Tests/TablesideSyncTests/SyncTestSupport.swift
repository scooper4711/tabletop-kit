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

    func library(_ app: TablesideApp = .turnkeeper) throws -> SharedLibrary {
        try SharedLibrary(folder: folder, app: app)
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
