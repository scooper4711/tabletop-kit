import ArtExtraction

/// The shared library's tables, by schema version (`PRAGMA user_version`). Every table whose rows sync has a
/// `changed` column: the change counter's value when the row last changed.
///
/// The apps update one at a time, so an app can open a library a newer app has changed. A new version therefore
/// only adds: tables, and columns with defaults, which an older app leaves alone when it writes (`upsert` updates
/// only the columns it names). A version that changes what existing rows mean also raises
/// `compatibility.oldestWriter` to itself, and older apps then only read the library until they are updated.
enum LibrarySchema {
    /// Each version's statements, applied in order to a database at an older version.
    static let versions: [String] = [version1, version2, version3, version4]

    private static let version1 = """
        CREATE TABLE counter (id INTEGER PRIMARY KEY CHECK (id = 1), value INTEGER NOT NULL);
        INSERT INTO counter VALUES (1, 0);
        CREATE TABLE deletions (tableName TEXT NOT NULL, rowKey TEXT NOT NULL, changed INTEGER NOT NULL,
            PRIMARY KEY (tableName, rowKey));
        CREATE TABLE sources (id TEXT PRIMARY KEY, title TEXT NOT NULL, game TEXT NOT NULL,
            byteCount INTEGER NOT NULL, readerVersion INTEGER NOT NULL, artFound INTEGER NOT NULL,
            kept INTEGER NOT NULL, changed INTEGER NOT NULL);
        CREATE TABLE sourceAccess (source TEXT NOT NULL, app TEXT NOT NULL, location BLOB NOT NULL,
            changed INTEGER NOT NULL, PRIMARY KEY (source, app));
        CREATE TABLE watchedFolders (app TEXT NOT NULL, path TEXT NOT NULL, reference BLOB NOT NULL,
            changed INTEGER NOT NULL, PRIMARY KEY (app, path));
        CREATE TABLE art (id TEXT PRIMARY KEY, name TEXT NOT NULL, game TEXT NOT NULL, size TEXT NOT NULL,
            traits BLOB NOT NULL, fingerprint BLOB NOT NULL, palette BLOB NOT NULL, picture TEXT,
            changed INTEGER NOT NULL);
        CREATE TABLE prints (key TEXT PRIMARY KEY, entry TEXT NOT NULL, source TEXT NOT NULL, kind TEXT NOT NULL,
            front BLOB NOT NULL, back BLOB, imageIndex INTEGER, picture TEXT, copies INTEGER NOT NULL,
            changed INTEGER NOT NULL);
        CREATE INDEX printsByEntry ON prints (entry);
        CREATE TABLE aliases (oldID TEXT PRIMARY KEY, app TEXT NOT NULL, entry TEXT NOT NULL,
            changed INTEGER NOT NULL);
        CREATE TABLE creatureArt (subject TEXT PRIMARY KEY, entry TEXT, customArt TEXT, changed INTEGER NOT NULL);
        CREATE TABLE customCreatures (id TEXT PRIMARY KEY, campaign TEXT, sharedVersion REAL, record BLOB NOT NULL,
            changed INTEGER NOT NULL);
        CREATE TABLE customArt (id TEXT PRIMARY KEY, file TEXT NOT NULL, sharedVersion REAL, record BLOB NOT NULL,
            changed INTEGER NOT NULL);
        CREATE TABLE claims (source TEXT PRIMARY KEY, app TEXT NOT NULL, until REAL NOT NULL);
        CREATE TABLE moves (app TEXT PRIMARY KEY, stage TEXT NOT NULL, changed INTEGER NOT NULL);
        """

    /// Art found by its folded name (`ArtKey.foldedName`), for merging art printed without the same picture.
    private static let version2 = """
        ALTER TABLE art ADD COLUMN foldedName TEXT NOT NULL DEFAULT '';
        CREATE INDEX artByName ON art (foldedName, game);
        """

    /// What is learned about art (R3.3): the user's name for it, its tags, and whether the user corrected them.
    private static let version3 = """
        CREATE TABLE notes (entry TEXT PRIMARY KEY, userName TEXT, tags BLOB NOT NULL, tagModel TEXT NOT NULL,
            suggestedName TEXT NOT NULL, corrected INTEGER NOT NULL, changed INTEGER NOT NULL);
        """

    /// The oldest schema version that may still write the library.
    private static let version4 = """
        CREATE TABLE compatibility (id INTEGER PRIMARY KEY CHECK (id = 1), oldestWriter INTEGER NOT NULL);
        INSERT INTO compatibility VALUES (1, 1);
        """

    /// Brings `database` up to this app's version, in one transaction, and tells whether this app may write it:
    /// a library a newer app has changed stays at its version, writable unless that version said otherwise.
    static func migrate(_ database: SQLiteDatabase) throws -> Bool {
        try database.transaction {
            let current = Int(try database.rows("PRAGMA user_version").first?.integer("user_version") ?? 0)
            guard current <= versions.count else {
                let oldest = try database.rows("SELECT oldestWriter FROM compatibility").first?.integer("oldestWriter")
                return Int(oldest ?? 1) <= versions.count
            }
            for version in versions.indices where version >= current {
                try database.execute(versions[version])
            }
            if current < 2 { try foldNames(in: database) }
            try database.execute("PRAGMA user_version = \(versions.count)")
            return true
        }
    }
}

extension LibrarySchema {
    /// Fills in `art.foldedName` for art written before version 2.
    static func foldNames(in database: SQLiteDatabase) throws {
        for row in try database.rows("SELECT id, name FROM art") {
            guard let id = row.text("id"), let name = row.text("name") else { continue }
            try database.run("UPDATE art SET foldedName = ? WHERE id = ?", [.text(ArtKey.foldedName(name)), .text(id)])
        }
    }
}

/// A table whose rows sync, and how its rows are named in `deletions` and `LibraryChanges`.
public enum LibraryTable: String, CaseIterable, Sendable {
    case sources, sourceAccess, watchedFolders, art, prints, aliases, creatureArt, customCreatures, customArt, moves,
         notes

    /// The columns of a row's primary key.
    var keyColumns: [String] {
        switch self {
        case .sources, .art, .customCreatures, .customArt: ["id"]
        case .sourceAccess: ["source", "app"]
        case .watchedFolders: ["app", "path"]
        case .prints: ["key"]
        case .aliases: ["oldID"]
        case .creatureArt: ["subject"]
        case .notes: ["entry"]
        case .moves: ["app"]
        }
    }

    /// The SQL naming a row: its key, or its keys joined with `|`.
    var keyExpression: String { keyColumns.joined(separator: " || '|' || ") }
}
