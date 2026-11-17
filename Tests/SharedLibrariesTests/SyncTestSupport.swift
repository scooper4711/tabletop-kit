import ArtExtraction
import ArtExtractionTestSupport
import CoreGraphics
import Foundation
@testable import SharedLibraries

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
