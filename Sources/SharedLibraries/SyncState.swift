import Foundation

/// What a device keeps about its sync that isn't about one record: whether it is paused, whose iCloud it last
/// synced with, and the engine's saved state. In the library's database, so a restored backup carries a state that
/// matches its rows.
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

    /// The iCloud account `cloudRecords` describes, as CloudKit names its user; nil before the first sync. An app
    /// syncing for the first time on a device where another app already syncs finds its own account here, and
    /// keeps what that app learned of the cloud.
    public func syncAccount() throws -> String? {
        try syncValue(forKey: "account").flatMap { String(data: $0, encoding: .utf8) }
    }

    public func setSyncAccount(_ account: String?) throws {
        try setSyncValue(account.map { Data($0.utf8) }, forKey: "account")
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
