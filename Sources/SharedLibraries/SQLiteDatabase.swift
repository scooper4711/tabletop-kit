import Foundation
import SQLite3

/// What went wrong in the shared library: the operation and why.
public struct SharedLibraryError: Error, Equatable, CustomStringConvertible {
    public let operation: String
    public let detail: String

    public init(operation: String, detail: String) {
        self.operation = operation
        self.detail = detail
    }

    public var description: String { "\(operation) failed: \(detail)" }
}

/// A value bound to or read from an SQL statement.
enum SQLValue: Equatable {
    case null
    case integer(Int64)
    case real(Double)
    case text(String)
    case blob(Data)
}

/// A row read from a query, by column name.
struct SQLRow {
    let values: [String: SQLValue]

    func text(_ column: String) -> String? {
        if case .text(let text) = values[column] { return text }
        return nil
    }

    func integer(_ column: String) -> Int64? {
        if case .integer(let value) = values[column] { return value }
        return nil
    }

    func real(_ column: String) -> Double? {
        switch values[column] {
        case .real(let value): value
        case .integer(let value): Double(value)
        default: nil
        }
    }

    func blob(_ column: String) -> Data? {
        if case .blob(let data) = values[column] { return data }
        return nil
    }

    func uuid(_ column: String) -> UUID? { text(column).flatMap(UUID.init(uuidString:)) }
}

/// One connection to an SQLite database file, through the system's SQLite. It isn't safe to use from more than one
/// thread at a time.
final class SQLiteDatabase {
    private let handle: OpaquePointer
    /// Tells SQLite to copy bound text and data, which Swift may free before the statement runs.
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    /// Opens the file, created when missing, in WAL mode and waiting up to `busyTimeout` for another app's writes.
    init(path: String, busyTimeout: TimeInterval = 5) throws {
        var opened: OpaquePointer?
        let status = sqlite3_open_v2(path, &opened, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil)
        guard status == SQLITE_OK, let opened else {
            let detail = opened.map { String(cString: sqlite3_errmsg($0)) } ?? "status \(status)"
            sqlite3_close_v2(opened)
            throw SharedLibraryError(operation: "Opening \(path)", detail: detail)
        }
        handle = opened
        sqlite3_busy_timeout(handle, Int32(busyTimeout * 1000))
        try execute("PRAGMA journal_mode = WAL")
    }

    deinit {
        sqlite3_close_v2(handle)
    }

    /// Runs one or more statements that take no values, ignoring any rows.
    func execute(_ sql: String) throws {
        var message: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(handle, sql, nil, nil, &message) == SQLITE_OK else {
            let detail = message.map { String(cString: $0) } ?? errorMessage
            sqlite3_free(message)
            throw SharedLibraryError(operation: "Running \(sql.prefix(60))", detail: detail)
        }
    }

    /// Runs a statement with `values` bound in order.
    func run(_ sql: String, _ values: [SQLValue] = []) throws {
        _ = try rows(sql, values)
    }

    /// The rows a query returns, with `values` bound in order.
    func rows(_ sql: String, _ values: [SQLValue] = []) throws -> [SQLRow] {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        for (index, value) in values.enumerated() { bind(value, at: Int32(index + 1), in: statement) }
        var rows: [SQLRow] = []
        while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW: rows.append(row(of: statement))
            case SQLITE_DONE: return rows
            default: throw SharedLibraryError(operation: "Running \(sql.prefix(60))", detail: errorMessage)
            }
        }
    }

    /// Runs `body` in one `BEGIN IMMEDIATE` transaction, which takes the write lock at once so that two apps
    /// writing never fail halfway through; rolled back when `body` throws.
    func transaction<Result>(_ body: () throws -> Result) throws -> Result {
        try execute("BEGIN IMMEDIATE")
        do {
            let result = try body()
            try execute("COMMIT")
            return result
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    // MARK: Helpers

    private var errorMessage: String { String(cString: sqlite3_errmsg(handle)) }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw SharedLibraryError(operation: "Preparing \(sql.prefix(60))", detail: errorMessage)
        }
        return statement
    }

    private func bind(_ value: SQLValue, at index: Int32, in statement: OpaquePointer) {
        switch value {
        case .null: sqlite3_bind_null(statement, index)
        case .integer(let number): sqlite3_bind_int64(statement, index, number)
        case .real(let number): sqlite3_bind_double(statement, index, number)
        case .text(let text): sqlite3_bind_text(statement, index, text, -1, Self.transient)
        case .blob(let data):
            _ = data.withUnsafeBytes { bytes in
                sqlite3_bind_blob(statement, index, bytes.baseAddress, Int32(bytes.count), Self.transient)
            }
        }
    }

    private func row(of statement: OpaquePointer) -> SQLRow {
        var values: [String: SQLValue] = [:]
        for column in 0..<sqlite3_column_count(statement) {
            values[String(cString: sqlite3_column_name(statement, column))] = value(at: column, in: statement)
        }
        return SQLRow(values: values)
    }

    private func value(at column: Int32, in statement: OpaquePointer) -> SQLValue {
        switch sqlite3_column_type(statement, column) {
        case SQLITE_INTEGER: return .integer(sqlite3_column_int64(statement, column))
        case SQLITE_FLOAT: return .real(sqlite3_column_double(statement, column))
        case SQLITE_TEXT: return .text(String(cString: sqlite3_column_text(statement, column)))
        case SQLITE_BLOB:
            let count = Int(sqlite3_column_bytes(statement, column))
            guard count > 0, let bytes = sqlite3_column_blob(statement, column) else { return .blob(Data()) }
            return .blob(Data(bytes: bytes, count: count))
        default: return .null
        }
    }
}
