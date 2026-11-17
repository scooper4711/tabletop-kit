import ArtExtraction
import CoreGraphics
import Foundation

/// A print taken out when its PDF is read again or removed.
struct RemovedPrint {
    var key: UUID
    var entryID: UUID
    var sourceID: String
    var face: PawnFace
}

/// Taking a PDF's prints out of the library: to read it again with a newer reader, or to remove it.
extension LibraryWriter {
    /// How far apart, in points, the centers of an old and a new print of one face can be.
    static let samePlaceDistance: CGFloat = 15

    /// Takes out the prints of the PDF `sourceID`, returning them.
    func takeOutPrints(of sourceID: String) throws -> [RemovedPrint] {
        let removed = try prints(of: sourceID)
        try delete(from: .prints, where: "source = ?", [.text(sourceID)])
        return removed
    }

    /// After a PDF is read again: each old print the new reader found in the same place answers, with its old
    /// entry, to the new print's art (R2.7); art left without prints goes. Returns the pictures to delete.
    @discardableResult
    func retire(_ older: [RemovedPrint], app: TablesideApp) throws -> [String] {
        let newer = try older.first.map { try prints(of: $0.sourceID) } ?? []
        for old in older where try ArtRows.entryID(answeringTo: old.key, in: database) == nil {
            guard let match = newer.first(where: { Self.isSamePlace($0.face, old.face) }) else { continue }
            try addAlias(old.key, app: app, entry: match.entryID)
            guard try ArtRows.entryID(answeringTo: old.entryID, in: database) == nil else { continue }
            try addAlias(old.entryID, app: app, entry: match.entryID)
            try repoint(old.entryID, to: match.entryID)
        }
        return try dropArtWithoutPrints()
    }

    /// Takes a PDF out: its prints, how apps reach it, and the art no other PDF prints. Returns the pictures to
    /// delete.
    func remove(sourceID: String) throws -> [String] {
        try delete(from: .prints, where: "source = ?", [.text(sourceID)])
        try delete(from: .sourceAccess, where: "source = ?", [.text(sourceID)])
        try delete(from: .sources, where: "id = ?", [.text(sourceID)])
        return try dropArtWithoutPrints()
    }

    // MARK: Helpers

    private func prints(of sourceID: String) throws -> [RemovedPrint] {
        try database.rows("SELECT key, entry, front FROM prints WHERE source = ?", [.text(sourceID)])
            .compactMap { row -> RemovedPrint? in
                guard let key = row.uuid("key"), let entry = row.uuid("entry"), let data = row.blob("front"),
                      let face = try? JSONDecoder().decode(PawnFace.self, from: data) else { return nil }
                return RemovedPrint(key: key, entryID: entry, sourceID: sourceID, face: face)
            }
    }

    private static func isSamePlace(_ first: PawnFace, _ second: PawnFace) -> Bool {
        first.pageIndex == second.pageIndex
            && hypot(first.rect.midX - second.rect.midX, first.rect.midY - second.rect.midY) <= samePlaceDistance
    }

    /// Deletes art without prints and what points at it, returning its pictures.
    private func dropArtWithoutPrints() throws -> [String] {
        let orphans = "SELECT id FROM art WHERE id NOT IN (SELECT entry FROM prints)"
        let pictures = try database.rows("SELECT picture FROM art WHERE id IN (\(orphans))")
            .compactMap { $0.text("picture") }
        try delete(from: .aliases, where: "entry IN (\(orphans))", [])
        try delete(from: .creatureArt, where: "entry IN (\(orphans))", [])
        try delete(from: .art, where: "id IN (\(orphans))", [])
        return pictures
    }
}
