import ArtExtraction
import Foundation

/// Writing the art library's rows.
extension LibraryWriter {
    /// Adds a PDF, or updates what is known about it: a newer reader's findings, and keeping it once any app
    /// keeps it. `location` is how `app` reaches it.
    func add(_ source: ArtSource, for app: TablesideApp) throws {
        let known = try ArtRows.sources(in: database).first { $0.id == source.id }
        let isKept = known?.isKept == true || source.location == .kept
        let latest = known.flatMap { $0.readerVersion >= source.readerVersion ? $0 : nil }
        let reading = latest.map { (version: $0.readerVersion, found: $0.artFound) }
            ?? (version: source.readerVersion, found: source.artFound)
        try upsert(.sources, [("id", .text(source.id)), ("title", .text(known?.title ?? source.title)),
                              ("game", .text(source.game.rawValue)), ("byteCount", .integer(Int64(source.byteCount))),
                              ("readerVersion", .integer(Int64(reading.version))),
                              ("artFound", .integer(Int64(reading.found))),
                              ("kept", .integer(isKept ? 1 : 0))])
        guard source.location != .kept else { return }
        try upsert(.sourceAccess, [("source", .text(source.id)), ("app", .text(app.rawValue)),
                                   ("location", try ArtRows.encoded(source.location))])
    }

    /// Remembers a folder `app` watches for new PDFs.
    func addWatchedFolder(_ folder: FileReference, for app: TablesideApp) throws {
        try upsert(.watchedFolders, [("app", .text(app.rawValue)), ("path", .text(folder.path)),
                                     ("reference", try ArtRows.encoded(folder))])
    }

    /// Adds a piece of art, merging it by key (R2.5): a print whose key the library has joins that entry, with every
    /// print of both, and `incoming`'s name, size and prints over the entry's; a name the entry has wins over a
    /// stand-in (R2.3a). The merged entry takes the ID its prints give it, and what pointed at an entry it replaces
    /// points at it. Returns its ID.
    @discardableResult
    func merge(_ incoming: SharedArtEntry) throws -> UUID {
        try merge(incoming, with: try entries(printedAs: incoming.prints.map(\.key)))
    }

    /// Merges `incoming` with `known`, the art it joins: that of `entries(printedAs:)` for its prints' keys and
    /// any others naming art to join, as when a synced reading says its art is also printed elsewhere.
    @discardableResult
    func merge(_ incoming: SharedArtEntry, with known: [SharedArtEntry]) throws -> UUID {
        var merged = incoming
        for other in known {
            if merged.palette.isEmpty { merged.palette = other.palette }
            if merged.picture == nil { merged.artPicture = other.artPicture }
            merged.traits += other.traits.filter { !merged.traits.contains($0) }
            let known = Set(merged.prints.map(\.id))
            merged.prints += other.prints.filter { !known.contains($0.id) }
        }
        if merged.needsName, let named = known.first(where: { !$0.needsName }) {
            merged.name = named.name
            merged.needsName = false
        }
        merged.sortPrints()
        merged.id = merged.keyedID
        for replaced in known where replaced.id != merged.id { try repoint(replaced.id, to: merged.id) }
        try upsert(entry: merged)
        return merged.id
    }

    /// Records an ID an app gave the art before (R2.7).
    func addAlias(_ oldID: UUID, app: TablesideApp, entry: UUID) throws {
        guard oldID != entry else { return }
        try upsert(.aliases, [("oldID", .text(oldID.uuidString)), ("app", .text(app.rawValue)),
                              ("entry", .text(entry.uuidString))])
    }

    // MARK: Helpers

    /// The art that has a print with one of `keys`, by ID.
    func entries(printedAs keys: [UUID]) throws -> [SharedArtEntry] {
        guard !keys.isEmpty else { return [] }
        let placeholders = Array(repeating: "?", count: keys.count).joined(separator: ", ")
        return try ArtRows.entries(in: database, where: "id IN (SELECT entry FROM prints WHERE key IN "
                                   + "(\(placeholders)))", keys.map { .text($0.uuidString) })
            .sorted { $0.id.uuidString < $1.id.uuidString }
    }

    /// Takes out entry `old`, pointing its aliases and the creatures that chose it at `new`.
    func repoint(_ old: UUID, to new: UUID) throws {
        try delete(from: .art, where: "id = ?", [.text(old.uuidString)])
        try moveNote(from: old, to: new)
        for table in [LibraryTable.aliases, .creatureArt] {
            try database.run("UPDATE \(table.rawValue) SET entry = ?, changed = ? WHERE entry = ?",
                             [.text(new.uuidString), .integer(counter), .text(old.uuidString)])
        }
    }

    func upsert(entry: SharedArtEntry) throws {
        try upsert(.art, [("id", .text(entry.id.uuidString)), ("name", .text(entry.name)),
                          ("game", .text(entry.game.rawValue)), ("size", .text(entry.size.rawValue)),
                          ("traits", try ArtRows.encoded(entry.traits)),
                          ("fingerprint", try ArtRows.encoded(entry.fingerprint)),
                          ("palette", try ArtRows.encoded(entry.palette)),
                          ("picture", entry.picture.map { .text($0) } ?? .null),
                          ("picturePixels", .integer(Int64(entry.picturePixels))),
                          ("foldedName", .text(ArtKey.foldedName(entry.name))),
                          ("nameKey", .text(CreatureName.familyKey(entry.name))),
                          ("needsName", .integer(entry.needsName ? 1 : 0))])
        for print in entry.prints {
            try upsert(.prints, [("key", .text(print.key.uuidString)), ("entry", .text(entry.id.uuidString)),
                                 ("source", .text(print.print.sourceID)), ("kind", .text(print.print.kind.rawValue)),
                                 ("front", try ArtRows.encoded(print.print.face)),
                                 ("back", try print.back.map(ArtRows.encoded) ?? .null),
                                 ("imageIndex", print.print.imageIndex.map { .integer(Int64($0)) } ?? .null),
                                 ("picture", print.print.tokenFile.map { .text($0) } ?? .null),
                                 ("backPicture", print.backPicture.map { .text($0) } ?? .null),
                                 ("copies", .integer(Int64(print.print.copies)))])
        }
    }
}
