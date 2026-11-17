import ArtExtraction
import Foundation

/// The folders each app watches for new PDFs, such as Scrollkeeper's downloads. A folder's bookmark works only for
/// the app that made it, so each app keeps its own.
extension SharedLibrary {
    /// The folders this app watches.
    public func watchedFolders() throws -> [FileReference] {
        try connection().rows("SELECT reference FROM watchedFolders WHERE app = ? ORDER BY path", [.text(app.rawValue)])
            .compactMap { row in
                row.blob("reference").flatMap { try? JSONDecoder().decode(FileReference.self, from: $0) }
            }
    }

    /// Watches a folder: its PDFs of art are added by reference, and this app reaches the PDFs it last saw inside
    /// it through it from now on.
    public func watch(_ folder: URL) throws {
        let reference = try FileReference(folder)
        let root = reference.path.hasSuffix("/") ? reference.path : reference.path + "/"
        let relinked = try sources().compactMap { source -> ArtSource? in
            guard let path = Self.path(of: source, for: app), path.hasPrefix(root),
                  var artSource = source.artSource(for: app) else { return nil }
            artSource.location = .inFolder(reference, relativePath: String(path.dropFirst(root.count)))
            return artSource
        }
        try write { writer in
            try writer.addWatchedFolder(reference, for: app)
            for source in relinked { try writer.add(source, for: app) }
        }
    }

    /// Stops watching the folder at `path`.
    public func unwatch(path: String) throws {
        try write { writer in
            try writer.delete(from: .watchedFolders, where: "app = ? AND path = ?", [.text(app.rawValue), .text(path)])
        }
    }

    /// Adds the PDFs of art in this app's watched folders that the library doesn't have, by reference; `progress` is
    /// told each file's name as it is read. A PDF another device read, which this app can't reach yet, is linked
    /// without reading its art (library sync R3.9). A file iCloud Drive hasn't downloaded is left for a later
    /// scan: reading it would make the system download it.
    @discardableResult
    public func addNewFiles(progress: (String) -> Void = { _ in }) -> [Result<ArtImportReport, Error>] {
        var results: [Result<ArtImportReport, Error>] = []
        for folder in (try? watchedFolders()) ?? [] {
            _ = folder.withAccess { root in
                for file in ProductScanner.artPDFs(in: root) where Self.isDownloaded(file) {
                    let location = SourceLocation.inFolder(folder, relativePath: Self.relativePath(of: file, in: root))
                    if let known = knownSource(of: file) {
                        if let linked = link(known, at: location) { results.append(linked) }
                        continue
                    }
                    progress(file.lastPathComponent)
                    results.append(Result { try commit(ArtLibrary.prepare(file), location: location) })
                }
            }
        }
        return results
    }

    /// True when a file's contents are on the device: it isn't in iCloud Drive (no status), or it is up to date.
    static func isDownloaded(_ status: URLUbiquitousItemDownloadingStatus?) -> Bool {
        status == nil || status == .current
    }

    // MARK: Helpers

    private static func isDownloaded(_ file: URL) -> Bool {
        let status = try? file.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
            .ubiquitousItemDownloadingStatus
        return isDownloaded(status)
    }

    private static func relativePath(of file: URL, in root: URL) -> String {
        String(file.standardizedFileURL.path.dropFirst(root.standardizedFileURL.path.count))
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    /// Records how this app reaches a PDF another device read, when this app has no way to it yet. Nil when there
    /// is nothing to do. A PDF an older reader read is linked too, like any the library has: it is then read
    /// again as the others are, and isn't hashed at every scan.
    private func link(_ known: SharedSource, at location: SourceLocation) -> Result<ArtImportReport, Error>? {
        guard known.artSource(for: app) == nil else { return nil }
        return Result {
            var report = ArtImportReport(sourceTitle: known.title)
            report.wasImported = true
            try writeAccess(to: known, location: location)
            return report
        }
    }
}
