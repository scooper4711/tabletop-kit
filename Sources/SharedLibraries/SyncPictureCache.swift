import Foundation

/// The pictures this device downloaded from iCloud: a cache the user can clear and a policy can limit
/// (library sync design, "The cache limit"). Pictures the device drew from its own PDFs aren't in it, so they are
/// never removed. None of this goes through `write`: it counts no change and tells no app.
extension SharedLibrary {
    /// The device's policy; `.onDemand(limit: nil)` until one is set.
    public func picturePolicy() throws -> PicturePolicy {
        try syncValue(forKey: "picturePolicy").flatMap { try? JSONDecoder().decode(PicturePolicy.self, from: $0) }
            ?? .onDemand(limit: nil)
    }

    /// Sets the policy, removing pictures at once when a limit is lowered below what the cache holds.
    public func setPicturePolicy(_ policy: PicturePolicy) throws {
        try setSyncValue(try JSONEncoder().encode(policy), forKey: "picturePolicy")
        try evictFetchedPictures()
    }

    /// Takes a picture downloaded to `file` into `Pictures` and the cache, remembering that iCloud holds it so it
    /// isn't uploaded back. A picture the device has already stays as it is.
    public func storeFetchedPicture(named name: String, from file: URL) throws {
        let destination = pictureFile(name)
        if hasPicture(name) {
            try? FileManager.default.removeItem(at: file)
        } else {
            do {
                try FileManager.default.moveItem(at: file, to: destination)
            } catch {
                throw SharedLibraryError(operation: "Saving \(name)", detail: error.localizedDescription)
            }
            let bytes = (try? FileManager.default.attributesOfItem(atPath: destination.path)[.size] as? Int) ?? 0
            try connection().run("INSERT OR REPLACE INTO fetchedPictures (name, bytes, shown) VALUES (?, ?, ?)",
                                 [.text(name), .integer(Int64(bytes)), .real(Date().timeIntervalSinceReferenceDate)])
        }
        try markPicturesUploaded([name])
        try evictFetchedPictures()
    }

    /// The size of the downloaded pictures, in bytes.
    public func fetchedPicturesByteCount() throws -> Int {
        Int(try connection().rows("SELECT COALESCE(SUM(bytes), 0) AS total FROM fetchedPictures").first?
            .integer("total") ?? 0)
    }

    /// Removes the downloaded pictures from the disk. iCloud still holds them, so each comes back when shown.
    public func clearFetchedPictures() throws {
        let database = try connection()
        for row in try database.rows("SELECT name FROM fetchedPictures") {
            if let name = row.text("name") { try? FileManager.default.removeItem(at: pictureFile(name)) }
        }
        try database.run("DELETE FROM fetchedPictures")
    }

    /// Notes that pictures were shown, for the cache's order of removal. A picture noted in the last half hour is
    /// left as it is, which spares the disk and still keeps a picture in use inside the hour `evictFetchedPictures`
    /// spares. Only a downloaded picture whose time is stale is written, so showing art takes no write lock.
    public func markPicturesShown(_ names: [String]) throws {
        let now = Date()
        let stale = now.addingTimeInterval(-Self.pictureGrace / 2)
        for name in names where picturesNotedShown[name, default: .distantPast] < stale {
            picturesNotedShown[name] = now
            let database = try connection()
            let shown = try database.rows("SELECT shown FROM fetchedPictures WHERE name = ?", [.text(name)]).first?
                .real("shown")
            guard let shown, shown < stale.timeIntervalSinceReferenceDate else { continue }
            try database.run("UPDATE fetchedPictures SET shown = ? WHERE name = ?",
                             [.real(now.timeIntervalSinceReferenceDate), .text(name)])
        }
    }

    // MARK: Helpers

    /// With a limit, removes the least recently shown downloaded pictures until the cache is within it, sparing
    /// any shown in the last hour, so a sheet being looked at keeps its pictures.
    func evictFetchedPictures() throws {
        guard case .onDemand(let limit?) = try picturePolicy() else { return }
        var total = try fetchedPicturesByteCount()
        guard total > limit else { return }
        let database = try connection()
        let cutoff = Date().addingTimeInterval(-Self.pictureGrace).timeIntervalSinceReferenceDate
        for row in try database.rows("SELECT name, bytes FROM fetchedPictures WHERE shown < ? ORDER BY shown, name",
                                     [.real(cutoff)]) where total > limit {
            guard let name = row.text("name") else { continue }
            try? FileManager.default.removeItem(at: pictureFile(name))
            try database.run("DELETE FROM fetchedPictures WHERE name = ?", [.text(name)])
            total -= Int(row.integer("bytes") ?? 0)
        }
    }
}
