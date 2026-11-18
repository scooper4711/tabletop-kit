import ArtExtraction
import Foundation

/// A source's record: its whole reading.
extension SharedLibrary {
    func sourceRecord(_ id: SyncRecordID, in database: SQLiteDatabase) throws -> SyncRecord? {
        guard let sourceID = SyncRecordName.rowKey(of: id),
              let reading = try sourceReading(id: sourceID, in: database) else { return nil }
        return SyncRecord(id: id, payload: try SyncPayloads.encode(reading), title: reading.title)
    }

    /// The reading of the PDF `sourceID`: the art its prints belong to, with every key of that art and its aliases.
    func sourceReading(id sourceID: String, in database: SQLiteDatabase) throws -> SourceReading? {
        guard let row = try database.rows("SELECT * FROM sources WHERE id = ?", [.text(sourceID)]).first,
              let title = row.text("title"), let game = row.text("game").flatMap(GameSystem.init(rawValue:)) else {
            return nil
        }
        let own = "id IN (SELECT entry FROM prints WHERE source = ?)"
        let entries = try ArtRows.entries(in: database, where: own, [.text(sourceID)])
        let aliases = try readingAliases(ofArtPrintedBy: sourceID, in: database)
        let groups = entries.map { entry in
            Self.readingGroup(of: entry, source: sourceID, aliases: aliases[entry.id] ?? [])
        }
        return SourceReading(id: sourceID, title: title, game: game, byteCount: Int(row.integer("byteCount") ?? 0),
                             readerVersion: Int(row.integer("readerVersion") ?? 0),
                             artFound: Int(row.integer("artFound") ?? 0),
                             groups: groups.sorted { $0.entry.uuidString < $1.entry.uuidString })
    }

    // MARK: Helpers

    /// The aliases of the art the PDF prints, by art. An alias that is also art's ID or a print's key is left out:
    /// it finds its art without the alias, and a device that has that print wouldn't keep it.
    private func readingAliases(ofArtPrintedBy sourceID: String,
                                in database: SQLiteDatabase) throws -> [UUID: [ReadingAlias]] {
        var aliases: [UUID: [ReadingAlias]] = [:]
        let rows = try database.rows("SELECT oldID, app, entry FROM aliases WHERE entry IN "
                                     + "(SELECT entry FROM prints WHERE source = ?) AND oldID NOT IN "
                                     + "(SELECT id FROM art) AND oldID NOT IN (SELECT key FROM prints) "
                                     + "ORDER BY oldID", [.text(sourceID)])
        for row in rows {
            guard let oldID = row.uuid("oldID"), let entry = row.uuid("entry"),
                  let app = row.text("app").flatMap(TablesideApp.init(rawValue:)) else { continue }
            aliases[entry, default: []].append(ReadingAlias(oldID: oldID, app: app))
        }
        return aliases.mapValues { $0.sorted { $0.oldID.uuidString < $1.oldID.uuidString } }
    }

    private static func readingGroup(of entry: SharedArtEntry, source: String,
                                     aliases: [ReadingAlias]) -> ReadingGroup {
        let prints = entry.prints.filter { $0.print.sourceID == source }.map(readingPrint)
        return ReadingGroup(entry: entry.id, name: entry.name, game: entry.game, size: entry.size,
                            traits: entry.traits, fingerprint: entry.fingerprint, palette: entry.palette,
                            picture: entry.picture, picturePixels: entry.picture == nil ? 0 : entry.picturePixels,
                            needsName: entry.needsName,
                            keys: entry.prints.map(\.key).sorted { $0.uuidString < $1.uuidString },
                            prints: prints.sorted { $0.key.uuidString < $1.key.uuidString }, aliases: aliases)
    }

    private static func readingPrint(_ print: SharedPrint) -> ReadingPrint {
        ReadingPrint(key: print.key, kind: print.print.kind, front: print.print.face, back: print.back,
                     imageIndex: print.print.imageIndex, picture: print.print.tokenFile,
                     backPicture: print.backPicture, copies: print.print.copies)
    }
}
