import Foundation

/// What a device keeps about its sync that isn't about one record: whether it is paused, and the engine's saved
/// state. In the library's database, so a restored backup carries a state that matches its rows.
extension SharedLibrary {
    /// True after the user deleted the library's iCloud data, until the app turns syncing on again.
    public var isSyncPaused: Bool {
        get throws { try syncValue(forKey: "paused") != nil }
    }

    public func setSyncPaused(_ paused: Bool) throws {
        try setSyncValue(paused ? Data([1]) : nil, forKey: "paused")
    }

    /// The engine's saved state for this app.
    public func engineState() throws -> Data? {
        try syncValue(forKey: engineStateKey)
    }

    public func setEngineState(_ state: Data?) throws {
        try setSyncValue(state, forKey: engineStateKey)
    }

    // MARK: Helpers

    var engineStateKey: String { "engine.\(app.rawValue)" }

    func syncValue(forKey key: String) throws -> Data? {
        try connection().rows("SELECT value FROM syncState WHERE key = ?", [.text(key)]).first?.blob("value")
    }

    func setSyncValue(_ value: Data?, forKey key: String) throws {
        let database = try connection()
        guard let value else { return try database.run("DELETE FROM syncState WHERE key = ?", [.text(key)]) }
        try database.run("INSERT OR REPLACE INTO syncState (key, value) VALUES (?, ?)", [.text(key), .blob(value)])
    }
}
