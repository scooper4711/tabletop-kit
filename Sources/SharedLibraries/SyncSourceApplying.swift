import ArtExtraction
import Foundation

/// Applying a source's record: its whole reading, or its removal.
extension RemoteApplication {
    /// A reading by the same or a newer reader is merged in; one by an older reader than this device's own leaves
    /// the local reading, which is then sent over it.
    mutating func applySource(_ reading: SourceReading, _ incoming: IncomingRecord) throws {
        let known = try database.rows("SELECT readerVersion, kept FROM sources WHERE id = ?", [.text(reading.id)]).first
        let knownVersion = known?.integer("readerVersion").map(Int.init)
        if let knownVersion, knownVersion > reading.readerVersion {
            try store(incoming, rowKey: reading.id, sentChanged: -1)
            countApplied()
            return
        }
        let older = knownVersion.map { $0 < reading.readerVersion } == true
            ? try writer.takeOutPrints(of: reading.id) : []
        try upsert(reading, kept: known?.integer("kept") ?? 0)
        for group in reading.groups { try merge(group, source: reading.id) }
        if !older.isEmpty { addPicturesToDelete(try writer.retire(older, app: library.app)) }
        addAppliedSource(incoming)
        countApplied()
    }

    /// A PDF removed on another device is removed here, with its art, pictures and kept copy. A removal wins.
    mutating func removeSource(_ id: SyncRecordID) throws {
        try database.run("DELETE FROM cloudRecords WHERE zone = ? AND name = ?",
                         [.text(SyncZone.library), .text(id.name)])
        guard let sourceID = SyncRecordName.rowKey(of: id) else { return }
        addPicturesToDelete(try writer.remove(sourceID: sourceID))
        addRemovedSource(sourceID)
        countApplied()
    }

    // MARK: Helpers

    private func upsert(_ reading: SourceReading, kept: Int64) throws {
        try writer.upsert(.sources, [("id", .text(reading.id)), ("title", .text(reading.title)),
                                     ("game", .text(reading.game.rawValue)),
                                     ("byteCount", .integer(Int64(reading.byteCount))),
                                     ("readerVersion", .integer(Int64(reading.readerVersion))),
                                     ("artFound", .integer(Int64(reading.artFound))), ("kept", .integer(kept))])
    }

    /// Merges one piece of art, with the other art it is printed as, and adds the IDs it was known by.
    private func merge(_ group: ReadingGroup, source: String) throws {
        let art = ArtEntry(id: group.entry, name: group.name, game: group.game, size: group.size,
                           traits: group.traits, fingerprint: group.fingerprint, prints: [], palette: group.palette)
        var entry = SharedArtEntry(art, prints: group.prints.map { Self.print($0, source: source) },
                                   picture: group.picture)
        entry.needsName = group.needsName
        let merged = try writer.merge(entry, joining: group.keys)
        for alias in group.aliases where try ArtRows.entryID(answeringTo: alias.oldID, in: database) == nil {
            try writer.addAlias(alias.oldID, app: alias.app, entry: merged)
        }
    }

    private static func print(_ print: ReadingPrint, source: String) -> SharedPrint {
        SharedPrint(key: print.key, print: ArtPrint(sourceID: source, kind: print.kind, face: print.front,
                                                    imageIndex: print.imageIndex, tokenFile: print.picture,
                                                    copies: print.copies),
                    back: print.back, backPicture: print.backPicture)
    }
}
