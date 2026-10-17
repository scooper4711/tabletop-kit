import CryptoKit
import Foundation

/// A PDF read and ready to add to the art library.
public struct PreparedArt: Sendable {
    /// The PDF the library keeps or references: for a two-file deck of Battle Cards, the one with the art.
    public let file: URL
    public let title: String
    public let digest: String
    public let byteCount: Int
    public let extraction: ExtractionResult
}

/// Adding PDFs to the art library: kept, referenced where they are, or found in watched folders.
extension ArtLibrary {
    /// Reads a PDF's art. It touches nothing in the library, so it can run off the main thread; the caller needs
    /// access to the file.
    public static func prepare(_ url: URL) throws -> PreparedArt {
        let file = libraryFile(for: url)
        let title = ImageDeck.containing(url)?.title ?? CardDeck.containing(url)?.title
            ?? ProductTitle.fromFileName(url.lastPathComponent)
        return PreparedArt(file: file, title: title, digest: try digest(of: file), byteCount: byteCount(of: file),
                           extraction: try PawnExtractor.extract(from: file))
    }

    /// Adds a PDF the app has access to: a copy kept in the library, or else a reference to it where it is.
    @discardableResult
    public func add(_ url: URL, keeping: Bool) throws -> ArtImportReport {
        let prepared = try Self.prepare(url)
        return try commit(prepared, location: keeping ? .kept : .referenced(FileReference(prepared.file)))
    }

    /// Adds a prepared PDF's art, merging art the library has already, and saves. A PDF read by the current
    /// reader changes nothing; one read by an older reader is read afresh.
    @discardableResult
    public func commit(_ prepared: PreparedArt, location: SourceLocation) throws -> ArtImportReport {
        var report = ArtImportReport(sourceTitle: prepared.title,
                                     unreadablePages: prepared.extraction.unreadablePages)
        if let known = source(id: prepared.digest) {
            guard known.readerVersion < PawnExtractor.version else {
                report.wasImported = true
                return report
            }
            try remove(known)
        }
        if case .kept = location { try keep(prepared) }
        let source = ArtSource(id: prepared.digest, title: prepared.title, game: GameSystem(title: prepared.title),
                               location: location, byteCount: prepared.byteCount,
                               readerVersion: PawnExtractor.version, artFound: prepared.extraction.pawns.count)
        sources.append(source)
        var merger = ArtMerger(library: self, prepared: prepared, source: source)
        for found in prepared.extraction.pawns {
            try merger.merge(found, into: &report)
        }
        try save()
        return report
    }

    /// True when the PDF at `url` is in the library: recognized by its place and size, or else its contents.
    public func contains(_ url: URL) -> Bool {
        let file = Self.libraryFile(for: url)
        let size = Self.byteCount(of: file)
        if sources.contains(where: { $0.byteCount == size && Self.path(of: $0) == file.path }) { return true }
        return (try? Self.digest(of: file)).map { digest in sources.contains { $0.id == digest } } ?? false
    }

    // MARK: Watched folders

    /// Watches a folder, such as Scrollkeeper's downloads: its PDFs of art are added by reference. The PDFs last
    /// seen inside it are reached through it from now on, so choosing a folder again restores access to them, as
    /// after the app moved into the App Sandbox, where bookmarks made outside it don't grant access.
    public func watch(_ folder: URL) throws {
        let reference = try FileReference(folder)
        watchedFolders.removeAll { $0.path == reference.path }
        watchedFolders.append(reference)
        relink(to: reference)
        try save()
    }

    public func unwatch(_ reference: FileReference) throws {
        watchedFolders.removeAll { $0 == reference }
        try save()
    }

    /// Adds the PDFs of art in the watched folders that the library doesn't have, by reference; `progress` is
    /// told each file's name as it is read.
    @discardableResult
    public func addNewFiles(progress: (String) -> Void = { _ in }) -> [Result<ArtImportReport, Error>] {
        var results: [Result<ArtImportReport, Error>] = []
        for folder in watchedFolders {
            _ = folder.withAccess { root in
                for file in ProductScanner.artPDFs(in: root) where !contains(file) {
                    progress(file.lastPathComponent)
                    let relative = String(file.standardizedFileURL.path.dropFirst(root.standardizedFileURL.path.count))
                        .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                    results.append(Result {
                        try commit(Self.prepare(file), location: .inFolder(folder, relativePath: relative))
                    })
                }
            }
        }
        return results
    }

    // MARK: Helpers

    private func relink(to folder: FileReference) {
        let root = folder.path.hasSuffix("/") ? folder.path : folder.path + "/"
        for index in sources.indices {
            guard let path = Self.path(of: sources[index]), path.hasPrefix(root) else { continue }
            sources[index].location = .inFolder(folder, relativePath: String(path.dropFirst(root.count)))
        }
        refreshStatuses()
    }

    private func keep(_ prepared: PreparedArt) throws {
        let destination = keptFile(id: prepared.digest)
        guard !FileManager.default.fileExists(atPath: destination.path) else { return }
        do {
            try FileManager.default.copyItem(at: prepared.file.resolvingSymlinksInPath(), to: destination)
        } catch {
            let file = prepared.file.lastPathComponent
            throw ArtLibraryError.saveFailed("copying \(file): \(error.localizedDescription)")
        }
    }

    /// Where a referenced PDF was last seen; nil for a kept one.
    static func path(of source: ArtSource) -> String? {
        switch source.location {
        case .kept: nil
        case .referenced(let reference): reference.path
        case .inFolder(let folder, let relativePath): (folder.path as NSString).appendingPathComponent(relativePath)
        }
    }

    /// The file the library keeps for `url`: a deck's art PDF, the folder of a deck printed as pictures, or the
    /// PDF itself.
    static func libraryFile(for url: URL) -> URL {
        ImageDeck.containing(url)?.folder ?? CardDeck.containing(url)?.artFile ?? url
    }

    /// A file's size, or the total size of a folder's files; 0 when it can't be read.
    static func byteCount(of url: URL) -> Int {
        let files = folderFiles(url) ?? [url]
        return files.reduce(0) { total, file in
            total + ((try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int) ?? 0)
        }
    }

    /// The files in `url` sorted by name, or nil when it isn't a folder.
    private static func folderFiles(_ url: URL) -> [URL]? {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue,
              let names = try? FileManager.default.contentsOfDirectory(atPath: url.path) else { return nil }
        return names.filter { !$0.hasPrefix(".") }.sorted().map(url.appendingPathComponent)
    }

    /// SHA-256 of a file; of a folder, of its files' names and sizes, which a deck of pictures doesn't change.
    static func digest(of url: URL) throws -> String {
        if let files = folderFiles(url) {
            let listing = files.map { "\($0.lastPathComponent):\(byteCount(of: $0))" }.joined(separator: "\n")
            return SHA256.hash(data: Data(listing.utf8)).map { String(format: "%02x", $0) }.joined()
        }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
