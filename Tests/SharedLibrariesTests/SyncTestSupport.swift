import ArtExtraction
import ArtExtractionTestSupport
import CoreGraphics
import Foundation
@testable import SharedLibraries
import Testing

/// A device for the sync tests: a library folder of its own and drawn PDFs to read.
struct SyncDevice {
    let root = temporaryFolder()
    let goblin = DrawnPawn(rect: CGRect(x: 20, y: 600, width: 81, height: 138), art: creatureArt(variant: 0),
                           name: "GOBLIN WARRIOR")
    let ogre = DrawnPawn(rect: CGRect(x: 120, y: 600, width: 81, height: 138), art: creatureArt(variant: 1),
                         name: "OGRE")

    var folder: URL { root.appending(path: "Tableside") }

    func library(_ app: TablesideApp = .pawnShop) throws -> SharedLibrary {
        try SharedLibrary(folder: folder, app: app)
    }

    /// A pawn box PDF in this device's root folder, of `pawns` or the goblin and the ogre. Asking again for the
    /// same name gives the same file, as drawing it again gives different bytes.
    func pawnBox(_ pawns: [DrawnPawn]? = nil, named name: String = "Pathfinder Test Pawn Box PDF.pdf") throws -> URL {
        let file = root.appending(path: name)
        if FileManager.default.fileExists(atPath: file.path) { return file }
        return try writePawnPDF(pawns ?? [goblin, ogre], named: name, in: root)
    }
}

extension SharedLibrary {
    /// What the cloud would receive from this library now, marked sent with the fields `fields`: each save as
    /// the server would hand it to another device, each deletion too.
    @discardableResult
    func sendEverything(fields: Data = Data([1])) throws -> [RemoteChange] {
        let candidates = try syncCandidates()
        var changes: [RemoteChange] = []
        for id in candidates.saves {
            guard let outgoing = try outgoingRecord(id) else { continue }
            try markSent(outgoing, systemFields: fields)
            changes.append(.saved(outgoing.record, systemFields: fields))
        }
        for id in candidates.deletions {
            try markDeleted(id)
            changes.append(.deleted(id))
        }
        return changes
    }

    /// The art's IDs, sorted.
    func artIDs() throws -> [UUID] {
        try artEntries().map(\.id).sorted { $0.uuidString < $1.uuidString }
    }
}

extension SharedLibrary {
    /// Each record's content digest by record name, to compare two libraries that should agree.
    func syncDigests() throws -> [String: String] {
        let database = try connection()
        var digests: [String: String] = [:]
        for kind in SyncKind.allCases {
            for (rowKey, _) in try syncRows(of: kind, in: database) {
                let name = SyncRecordName.make(kind, rowKey: rowKey)
                let record = try syncRecord(SyncRecordID(kind: kind, name: name), rowKey: rowKey, in: database)
                digests[name] = record.map { SyncDigest.hex(of: $0.payload) }
            }
        }
        return digests
    }
}

/// A stand-in for the CloudKit zone: it accepts a save made against the record's current version, and answers any
/// other with the record it holds, as `serverRecordChanged` does.
final class FakeCloud {
    private enum Event {
        case saved(SyncRecord, version: Int)
        case deleted(SyncRecordID)
    }

    private var stored: [String: (record: SyncRecord, version: Int)] = [:]
    private var log: [Event] = []

    /// One device's turn: sends what it has to send, then fetches what happened since `cursor`. True when
    /// something was sent or applied.
    func sync(_ library: SharedLibrary, cursor: inout Int) throws -> Bool {
        var active = try send(from: library)
        let fetched = log[cursor...].map { event -> RemoteChange in
            switch event {
            case .saved(let record, let version): .saved(record, systemFields: Self.fields(version))
            case .deleted(let id): .deleted(id)
            }
        }
        cursor = log.count
        let report = try library.applyRemote(Array(fetched))
        active = active || report.applied > 0 || report.parked > 0
        return active
    }

    private func send(from library: SharedLibrary) throws -> Bool {
        let candidates = try library.syncCandidates()
        var sent = false
        for id in candidates.saves {
            guard let outgoing = try library.outgoingRecord(id) else { continue }
            sent = true
            try save(outgoing, from: library)
        }
        for id in candidates.deletions {
            sent = true
            stored[id.name] = nil
            log.append(.deleted(id))
            try library.markDeleted(id)
        }
        return sent
    }

    private func save(_ outgoing: OutgoingRecord, from library: SharedLibrary) throws {
        let name = outgoing.record.id.name
        let known = outgoing.systemFields.flatMap { String(data: $0, encoding: .utf8) }.flatMap(Int.init)
        if known != nil && stored[name] == nil {
            try library.forgetSystemFields(of: outgoing.record.id)
            return
        }
        if let held = stored[name], held.version != known {
            try library.applyRemote([.saved(held.record, systemFields: Self.fields(held.version))])
            return
        }
        let version = (stored[name]?.version ?? 0) + 1
        stored[name] = (outgoing.record, version)
        log.append(.saved(outgoing.record, version: version))
        try library.markSent(outgoing, systemFields: Self.fields(version))
    }

    private static func fields(_ version: Int) -> Data { Data("\(version)".utf8) }
}

/// Two devices syncing through a `FakeCloud` until neither has anything left to do.
final class SyncedDevices {
    let first = SyncDevice()
    let second = SyncDevice()
    let firstLibrary: SharedLibrary
    let secondLibrary: SharedLibrary
    let cloud = FakeCloud()
    private var cursors = (first: 0, second: 0)

    init() throws {
        firstLibrary = try first.library(.turnkeeper)
        secondLibrary = try second.library(.fieldGuide)
    }

    /// Syncs both devices in turn until a round finds nothing to send or apply, failing when that takes more than
    /// 4 rounds; then both agree on every record.
    func exchange() throws {
        for round in 1...5 {
            let firstActive = try cloud.sync(firstLibrary, cursor: &cursors.first)
            let secondActive = try cloud.sync(secondLibrary, cursor: &cursors.second)
            if !firstActive && !secondActive {
                try expectAgreement()
                return
            }
            if round == 5 { Issue.record("still busy after 4 rounds") }
        }
    }

    private func expectAgreement() throws {
        #expect(try firstLibrary.syncCandidates().isEmpty && secondLibrary.syncCandidates().isEmpty)
        #expect(try firstLibrary.syncDigests() == secondLibrary.syncDigests())
    }
}

/// Art and sources written straight to a library, for cases a drawn PDF can't set up.
enum SyncFixture {
    static let figureKey = UUID(uuidString: "00000000-0000-5000-8000-000000000001")!
    static let pawnKey = UUID(uuidString: "FFFFFFFF-0000-5000-8000-000000000002")!

    static func addSource(_ id: String, to writer: LibraryWriter) throws {
        try writer.add(ArtSource(id: id, title: id, game: .pathfinder, location: .kept, byteCount: 1,
                                 readerVersion: 4, artFound: 1), for: .turnkeeper)
    }

    /// A print of the art: its kind, its key and the PDF printing it.
    struct Print {
        let kind: ArtKind
        let key: UUID
        let source: String

        init(_ kind: ArtKind, _ key: UUID, _ source: String) {
            self.kind = kind
            self.key = key
            self.source = source
        }
    }

    /// Art "Ogre" with the prints.
    static func entry(_ prints: [Print]) -> SharedArtEntry {
        let face = PawnFace(pageIndex: 0, rect: CGRect(x: 0, y: 0, width: 80, height: 130), rotation: 0)
        let art = ArtEntry(id: prints[0].key, name: "Ogre", game: .pathfinder, size: .large, traits: [],
                           fingerprint: ArtFingerprint(imageDigests: ["ab"]), prints: [], palette: [])
        return SharedArtEntry(art, prints: prints.map { print in
            let artPrint = ArtPrint(sourceID: print.source, kind: print.kind, face: face, copies: 1)
            return SharedPrint(key: print.key, print: artPrint)
        })
    }
}

/// The saved records of one kind among `changes`.
func savedRecords(_ changes: [RemoteChange], of kind: SyncKind) -> [RemoteChange] {
    changes.filter { change in
        if case .saved(let record, _) = change { record.id.kind == kind } else { false }
    }
}
