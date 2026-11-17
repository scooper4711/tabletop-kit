import Foundation

/// What a device does about the pictures it doesn't hold (library sync design, "Pictures"): which are on the
/// device's disk but not in iCloud, which in iCloud but not on the disk, and how many it keeps from iCloud.
public enum PicturePolicy: Codable, Equatable, Sendable {
    /// A picture downloads when first shown; past `limit` bytes the least recently shown are removed.
    case onDemand(limit: Int?)
    /// Every picture downloads ahead of time, and none is removed.
    case everything
}

/// Zone `Pictures` rows in `cloudRecords` have the kind `picture`, and the file's name for name and `rowKey`.
extension SharedLibrary {
    /// How long a picture counts as in use after it was shown, and how long a new file is left alone.
    static let pictureGrace: TimeInterval = 3_600

    /// Up to `limit` of the pictures art names whose files are here and that iCloud isn't known to hold.
    public func picturesToUpload(limit: Int) throws -> [String] {
        let names = try connection().rows("SELECT name FROM (\(Self.referencedPictures)) WHERE name NOT IN "
                                          + "(SELECT name FROM cloudRecords WHERE zone = ?) ORDER BY name",
                                          [.text(SyncZone.pictures)]).compactMap { $0.text("name") }
        return Array(names.filter { hasPicture($0) }.prefix(limit))
    }

    /// Remembers that iCloud holds the pictures.
    public func markPicturesUploaded(_ names: [String]) throws {
        let database = try connection()
        try database.transaction {
            for name in names {
                try database.run("INSERT OR REPLACE INTO cloudRecords (zone, name, kind, rowKey, systemFields, "
                                 + "sentChanged, digest) VALUES (?, ?, 'picture', ?, NULL, 0, '')",
                                 [.text(SyncZone.pictures), .text(name), .text(name)])
            }
        }
    }

    /// The pictures in iCloud that no art or print names any more.
    public func picturesToDelete() throws -> [String] {
        try connection().rows("SELECT name FROM cloudRecords WHERE zone = ? AND name NOT IN "
                              + "(\(Self.referencedPictures)) ORDER BY name", [.text(SyncZone.pictures)])
            .compactMap { $0.text("name") }
    }

    /// Remembers that iCloud no longer holds the pictures.
    public func markPicturesDeleted(_ names: [String]) throws {
        let database = try connection()
        try database.transaction {
            for name in names {
                try database.run("DELETE FROM cloudRecords WHERE zone = ? AND name = ?",
                                 [.text(SyncZone.pictures), .text(name)])
            }
        }
    }

    /// The pictures the art names that this device doesn't have, to fetch from iCloud.
    public func missingPictures(of entry: SharedArtEntry) -> [String] {
        let names = [entry.picture] + entry.prints.flatMap { [$0.print.tokenFile, $0.backPicture] }
        var seen: Set<String> = []
        return names.compactMap { $0 }.filter { seen.insert($0).inserted && !hasPicture($0) }
    }

    /// Up to `limit` pictures any art or print names that this device doesn't have, for a device keeping every
    /// picture (`PicturePolicy.everything`).
    public func missingPictureNames(limit: Int) throws -> [String] {
        let names = try connection().rows("SELECT name FROM (\(Self.referencedPictures)) ORDER BY name")
            .compactMap { $0.text("name") }
        return Array(names.filter { !hasPicture($0) }.prefix(limit))
    }

    /// Removes the files in `Pictures` that nothing names, except those written in the last hour, which an import
    /// writes before the row that names them. Returns how many it removed.
    @discardableResult
    public func removeUnreferencedPictures() throws -> Int {
        let database = try connection()
        let referenced = Set(try database.rows(Self.referencedPictures).compactMap { $0.text("name") })
        let cutoff = Date().addingTimeInterval(-Self.pictureGrace)
        var removed = 0
        for file in picturesInFolder() where !referenced.contains(file.name) && file.modified < cutoff {
            try? FileManager.default.removeItem(at: pictureFile(file.name))
            try database.run("DELETE FROM fetchedPictures WHERE name = ?", [.text(file.name)])
            removed += 1
        }
        return removed
    }

    // MARK: Helpers

    /// The names art and prints give pictures, from `art.picture`, `prints.picture` and `prints.backPicture`.
    static let referencedPictures = "SELECT picture AS name FROM art WHERE picture IS NOT NULL "
        + "UNION SELECT picture FROM prints WHERE picture IS NOT NULL "
        + "UNION SELECT backPicture FROM prints WHERE backPicture IS NOT NULL"

    func hasPicture(_ name: String) -> Bool {
        FileManager.default.fileExists(atPath: pictureFile(name).path)
    }

    private func picturesInFolder() -> [(name: String, modified: Date)] {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isDirectoryKey]
        let files = (try? FileManager.default.contentsOfDirectory(at: picturesFolder, includingPropertiesForKeys: keys))
        return (files ?? []).compactMap { file in
            guard let values = try? file.resourceValues(forKeys: Set(keys)), values.isDirectory != true,
                  let modified = values.contentModificationDate else { return nil }
            return (file.lastPathComponent, modified)
        }
    }
}
