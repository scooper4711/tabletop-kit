import Foundation
import TablesideShared

/// The apps that share the libraries.
public enum TablesideApp: String, Codable, CaseIterable, Sendable {
    case pawnShop = "Pawn Shop"
    case turnkeeper = "Turnkeeper"
    case fieldGuide = "Field Guide"
}

/// What changed in the library since a reader last looked (shared libraries R5.2).
public struct LibraryChanges: Equatable, Sendable {
    /// The change counter now: pass it to the next `changes(since:)`.
    public var counter: Int64
    /// The tables with rows added or changed.
    public var changedTables: Set<LibraryTable>
    /// The rows deleted, by table: their keys (`LibraryTable.keyExpression`).
    public var deletions: [LibraryTable: [String]]

    public var isEmpty: Bool { changedTables.isEmpty && deletions.isEmpty }
}

/// The art library and creature library Pawn Shop, Turnkeeper and Field Guide share (shared libraries R1): an
/// SQLite database, `Library.sqlite`, with the files it holds beside it. Each change is one short transaction, and
/// other apps hear of it through a Darwin notification (`SharedLibraryChangeObserver`). It isn't safe to use from
/// more than one thread at a time; an app keeps it in an actor.
public final class SharedLibrary {
    public static let fileName = "Library.sqlite"
    /// The folder in the App Group's container that holds the libraries.
    public static let groupFolderName = "Tableside"

    /// The folder holding the database: `Sources` for kept PDFs, `Pictures` for art drawn alone, `Custom` for
    /// images the user added.
    public let folder: URL
    /// The app using it, for what is only its own: access to PDFs, watched folders, claims.
    public let app: TablesideApp
    private var database: SQLiteDatabase?

    /// The library in `folder`, created empty when there is none.
    public init(folder: URL, app: TablesideApp) throws {
        self.folder = folder
        self.app = app
        for subfolder in [folder, sourcesFolder, picturesFolder, customFolder] {
            try FileManager.default.createDirectory(at: subfolder, withIntermediateDirectories: true)
        }
        canWrite = try LibrarySchema.migrate(try connection())
    }

    /// False when a newer version of one of the apps changed the library in a way this one can't write: it then
    /// only reads it, and the user should update this app.
    public private(set) var canWrite = true

    /// The library in the App Group's `Tableside` folder, or in `fallback` for an app outside the group, such as
    /// an ad hoc build (R1.2).
    public static func standard(app: TablesideApp, fallback: URL) throws -> SharedLibrary {
        let group = ToolkitGroup.containerURL()?.appending(path: groupFolderName, directoryHint: .isDirectory)
        return try SharedLibrary(folder: group ?? fallback, app: app)
    }

    /// Closes the database, as when the app goes to the background on the iPad, where a suspended app holding a
    /// lock on a file in the group's container is ended (R5.4). The next read or write opens it again.
    public func close() {
        database = nil
    }

    /// The change counter now.
    public func changeCounter() throws -> Int64 {
        try Self.counter(in: try connection())
    }

    /// What changed after `counter` (R5.2).
    public func changes(since counter: Int64) throws -> LibraryChanges {
        let database = try connection()
        var changes = LibraryChanges(counter: try Self.counter(in: database), changedTables: [], deletions: [:])
        for table in LibraryTable.allCases {
            let changed = try database.rows("SELECT 1 FROM \(table.rawValue) WHERE changed > ? LIMIT 1",
                                            [.integer(counter)])
            if !changed.isEmpty { changes.changedTables.insert(table) }
        }
        let deleted = try database.rows("SELECT tableName, rowKey FROM deletions WHERE changed > ?",
                                        [.integer(counter)])
        for row in deleted {
            guard let table = row.text("tableName").flatMap(LibraryTable.init(rawValue:)),
                  let key = row.text("rowKey") else { continue }
            changes.deletions[table, default: []].append(key)
        }
        return changes
    }

    var sourcesFolder: URL { folder.appending(path: "Sources", directoryHint: .isDirectory) }
    var picturesFolder: URL { folder.appending(path: "Pictures", directoryHint: .isDirectory) }
    var customFolder: URL { folder.appending(path: "Custom", directoryHint: .isDirectory) }

    /// The open connection, opened when needed.
    func connection() throws -> SQLiteDatabase {
        if let database { return database }
        let opened = try SQLiteDatabase(path: folder.appending(path: Self.fileName).path)
        database = opened
        return opened
    }

    /// Runs `body` in one transaction that takes the next change counter for every row it writes, then tells the
    /// other apps (R5.1, R5.2).
    @discardableResult
    func write<Result>(_ body: (LibraryWriter) throws -> Result) throws -> Result {
        try requireWriting()
        let database = try connection()
        let result = try database.transaction {
            try database.run("UPDATE counter SET value = value + 1")
            return try body(LibraryWriter(database: database, counter: try Self.counter(in: database)))
        }
        SharedLibraryChange.post()
        return result
    }

    /// Throws when a newer app changed the library in a way this one can't write.
    func requireWriting() throws {
        guard canWrite else {
            throw SharedLibraryError(operation: "Saving to the shared library",
                                     detail: "a newer version of a Tableside app changed it; update \(app.rawValue)")
        }
    }

    private static func counter(in database: SQLiteDatabase) throws -> Int64 {
        try database.rows("SELECT value FROM counter").first?.integer("value") ?? 0
    }
}

/// Writes rows inside `SharedLibrary.write`, each stamped with the transaction's change counter.
struct LibraryWriter {
    let database: SQLiteDatabase
    let counter: Int64

    /// Adds a row, or updates the columns named of the row with the same key, leaving any others alone: columns a
    /// newer app added keep their values when an older app writes (`LibrarySchema`).
    func upsert(_ table: LibraryTable, _ columns: [(String, SQLValue)]) throws {
        let names = columns.map(\.0) + ["changed"]
        let placeholders = Array(repeating: "?", count: names.count).joined(separator: ", ")
        let updates = names.filter { !table.keyColumns.contains($0) }.map { "\($0) = excluded.\($0)" }
        try database.run("INSERT INTO \(table.rawValue) (\(names.joined(separator: ", "))) VALUES (\(placeholders)) "
                         + "ON CONFLICT (\(table.keyColumns.joined(separator: ", "))) DO UPDATE SET "
                         + updates.joined(separator: ", "), columns.map(\.1) + [.integer(counter)])
        let key = table.keyColumns.compactMap { column -> String? in
            guard case .text(let value) = columns.first(where: { $0.0 == column })?.1 else { return nil }
            return value
        }.joined(separator: "|")
        try database.run("DELETE FROM deletions WHERE tableName = ? AND rowKey = ?",
                         [.text(table.rawValue), .text(key)])
    }

    /// Deletes the rows matching `condition`, recording each in `deletions`.
    func delete(from table: LibraryTable, where condition: String, _ values: [SQLValue]) throws {
        try database.run("INSERT OR REPLACE INTO deletions (tableName, rowKey, changed) SELECT ?, "
                         + "\(table.keyExpression), ? FROM \(table.rawValue) WHERE \(condition)",
                         [.text(table.rawValue), .integer(counter)] + values)
        try database.run("DELETE FROM \(table.rawValue) WHERE \(condition)", values)
    }
}
