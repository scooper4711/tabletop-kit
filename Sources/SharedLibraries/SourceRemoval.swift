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
    /// entry, to the new print's art (R2.7). An old entry left without prints hands its note, aliases and creatures
    /// to that art; art left without prints goes. Returns the pictures to delete.
    @discardableResult
    func retire(_ older: [RemovedPrint], app: TablesideApp) throws -> [String] {
        try retire(older, app: app) { old, newer in newer.first { Self.isSamePlace($0.face, old.face) } }
    }

    /// After an image deck is read again: as `retire`, but an old print no new print shares a place with pairs
    /// with the new print whose art has the same folded name, since a card moved in from Pawn Shop's own library
    /// has no place (page 0). Only image decks: each card is one item, so a name there is one piece of art.
    @discardableResult
    func retireImageDeck(_ older: [RemovedPrint], app: TablesideApp) throws -> [String] {
        var byName: [String: RemovedPrint]?
        return try retire(older, app: app) { old, newer in
            try newer.first { Self.isSamePlace($0.face, old.face) } ?? namedLike(old, among: newer, byName: &byName)
        }
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

    /// Points each old print `pairing` finds a new print for at that print's art.
    private func retire(_ older: [RemovedPrint], app: TablesideApp,
                        pairing: (RemovedPrint, [RemovedPrint]) throws -> RemovedPrint?) throws -> [String] {
        let newer = try older.first.map { try prints(of: $0.sourceID) } ?? []
        let newerKeys = Set(newer.map(\.key))
        for old in older where !newerKeys.contains(old.key) {
            guard let match = try pairing(old, newer) else { continue }
            if old.entryID != match.entryID, try isLeftWithoutPrints(old.entryID) {
                try addAlias(old.entryID, app: app, entry: match.entryID)
                try repoint(old.entryID, to: match.entryID)
            }
            if try ArtRows.entryID(answeringTo: old.key, in: database) == nil {
                try addAlias(old.key, app: app, entry: match.entryID)
            }
        }
        return try dropArtWithoutPrints()
    }

    /// True when art `id` is gone, or still there with no prints.
    private func isLeftWithoutPrints(_ id: UUID) throws -> Bool {
        guard try ArtRows.entryID(answeringTo: id, in: database) != nil else { return true }
        return try database.rows("SELECT 1 FROM prints WHERE entry = ? LIMIT 1", [.text(id.uuidString)]).isEmpty
            && !(try database.rows("SELECT 1 FROM art WHERE id = ?", [.text(id.uuidString)]).isEmpty)
    }

    /// The new print whose art has the folded name of `old`'s art; `byName` holds the new prints by that name,
    /// read the first time it's needed.
    private func namedLike(_ old: RemovedPrint, among newer: [RemovedPrint],
                           byName: inout [String: RemovedPrint]?) throws -> RemovedPrint? {
        guard let name = try foldedName(ofArt: old.entryID), !name.isEmpty else { return nil }
        if byName == nil {
            var named: [String: RemovedPrint] = [:]
            for print in newer {
                if let printName = try foldedName(ofArt: print.entryID), named[printName] == nil {
                    named[printName] = print
                }
            }
            byName = named
        }
        return byName?[name]
    }

    private func foldedName(ofArt id: UUID) throws -> String? {
        try database.rows("SELECT foldedName FROM art WHERE id = ?", [.text(id.uuidString)]).first?.text("foldedName")
    }

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
        try delete(from: .notes, where: "entry IN (\(orphans))", [])
        try delete(from: .art, where: "id IN (\(orphans))", [])
        return pictures
    }
}
