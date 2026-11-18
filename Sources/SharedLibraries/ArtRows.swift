import ArtExtraction
import Foundation

/// Reading the art library's rows.
enum ArtRows {
    static func sources(in database: SQLiteDatabase) throws -> [SharedSource] {
        var access: [String: [TablesideApp: SourceLocation]] = [:]
        for row in try database.rows("SELECT * FROM sourceAccess") {
            guard let source = row.text("source"), let app = row.text("app").flatMap(TablesideApp.init(rawValue:)),
                  let location = try decoded(SourceLocation.self, row.blob("location")) else { continue }
            access[source, default: [:]][app] = location
        }
        return try database.rows("SELECT * FROM sources ORDER BY title").compactMap { row in
            guard let id = row.text("id"), let title = row.text("title"),
                  let game = row.text("game").flatMap(GameSystem.init(rawValue:)) else { return nil }
            return SharedSource(id: id, title: title, game: game, byteCount: Int(row.integer("byteCount") ?? 0),
                                readerVersion: Int(row.integer("readerVersion") ?? 0),
                                artFound: Int(row.integer("artFound") ?? 0), isKept: row.integer("kept") == 1,
                                access: access[id] ?? [:])
        }
    }

    /// The entries matching `condition`, each with all its prints.
    static func entries(in database: SQLiteDatabase, where condition: String,
                        _ values: [SQLValue]) throws -> [SharedArtEntry] {
        let prints = try database.rows("SELECT * FROM prints WHERE entry IN (SELECT id FROM art WHERE \(condition)) "
                                       + "ORDER BY key", values)
        var printsByEntry: [String: [SharedPrint]] = [:]
        for row in prints {
            guard let entry = row.text("entry"), let print = try print(from: row) else { continue }
            printsByEntry[entry, default: []].append(print)
        }
        return try database.rows("SELECT * FROM art WHERE \(condition)", values).compactMap { row in
            try entry(from: row, prints: printsByEntry[row.text("id") ?? ""] ?? [])
        }
    }

    /// The ID of the entry that has the ID, print key or alias `id`.
    static func entryID(answeringTo id: UUID, in database: SQLiteDatabase) throws -> UUID? {
        let value = SQLValue.text(id.uuidString)
        let rows = try database.rows("SELECT id AS entry FROM art WHERE id = ? UNION ALL "
                                     + "SELECT entry FROM prints WHERE key = ? UNION ALL "
                                     + "SELECT entry FROM aliases WHERE oldID = ?", [value, value, value])
        return rows.first?.uuid("entry")
    }

    static func encoded(_ value: some Encodable) throws -> SQLValue {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return .blob(try encoder.encode(value))
    }

    // MARK: Helpers

    private static func entry(from row: SQLRow, prints: [SharedPrint]) throws -> SharedArtEntry? {
        guard let id = row.uuid("id"), let name = row.text("name"),
              let game = row.text("game").flatMap(GameSystem.init(rawValue:)),
              let size = row.text("size").flatMap(PawnSize.init(rawValue:)),
              let fingerprint = try decoded(ArtFingerprint.self, row.blob("fingerprint")) else { return nil }
        let entry = ArtEntry(id: id, name: name, game: game, size: size,
                             traits: try decoded([String].self, row.blob("traits")) ?? [], fingerprint: fingerprint,
                             prints: [], palette: try decoded([Double].self, row.blob("palette")) ?? [])
        var shared = SharedArtEntry(entry, keys: [])
        shared.prints = prints
        shared.sortPrints()
        shared.picture = row.text("picture")
        shared.picturePixels = Int(row.integer("picturePixels") ?? 0)
        shared.needsName = row.integer("needsName") == 1
        return shared
    }

    private static func print(from row: SQLRow) throws -> SharedPrint? {
        guard let key = row.uuid("key"), let source = row.text("source"),
              let kind = row.text("kind").flatMap(ArtKind.init(rawValue:)),
              let front = try decoded(PawnFace.self, row.blob("front")) else { return nil }
        let print = ArtPrint(sourceID: source, kind: kind, face: front,
                             imageIndex: row.integer("imageIndex").map(Int.init), tokenFile: row.text("picture"),
                             copies: Int(row.integer("copies") ?? 1))
        return SharedPrint(key: key, print: print, back: try decoded(PawnFace.self, row.blob("back")),
                           backPicture: row.text("backPicture"))
    }

    private static func decoded<Value: Decodable>(_ type: Value.Type, _ data: Data?) throws -> Value? {
        guard let data else { return nil }
        return try JSONDecoder().decode(type, from: data)
    }
}
