import Foundation

/// Claims on PDFs being read (shared libraries R5.3): an app claims a PDF before reading it, so another app skips
/// it and picks up its art when the change arrives. Claims don't sync and don't notify.
extension SharedLibrary {
    /// How long a claim lasts unless released: long enough to read the largest PDF.
    public static let claimDuration: TimeInterval = 600

    /// Claims the PDF with SHA-256 `sourceID` for this app until `now + claimDuration`; false when another app's
    /// claim on it hasn't run out.
    public func claim(sourceID: String, now: Date = Date()) throws -> Bool {
        let database = try connection()
        return try database.transaction {
            let held = try database.rows("SELECT app FROM claims WHERE source = ? AND until > ?",
                                         [.text(sourceID), .real(now.timeIntervalSinceReferenceDate)])
            if let holder = held.first?.text("app"), holder != app.rawValue { return false }
            try database.run("INSERT OR REPLACE INTO claims (source, app, until) VALUES (?, ?, ?)",
                             [.text(sourceID), .text(app.rawValue),
                              .real(now.addingTimeInterval(Self.claimDuration).timeIntervalSinceReferenceDate)])
            return true
        }
    }

    /// Gives up this app's claim on a PDF, once its art is added or reading it failed.
    public func releaseClaim(sourceID: String) throws {
        try connection().run("DELETE FROM claims WHERE source = ? AND app = ?", [.text(sourceID), .text(app.rawValue)])
    }
}
