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
        let deck = CardDeck.containing(url)
        let file = deck?.artFile ?? url
        let size = (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int) ?? 0
        return PreparedArt(file: file, title: deck?.title ?? ProductTitle.fromFileName(url.lastPathComponent),
                           digest: try digest(of: file), byteCount: size,
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
        let file = CardDeck.containing(url)?.artFile ?? url
        let size = (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int) ?? -1
        if sources.contains(where: { $0.byteCount == size && Self.path(of: $0) == file.path }) { return true }
        return (try? Self.digest(of: file)).map { digest in sources.contains { $0.id == digest } } ?? false
    }

    // MARK: Watched folders

    /// Watches a folder, such as Scrollkeeper's downloads: its PDFs of art are added by reference.
    public func watch(_ folder: URL) throws {
        let reference = try FileReference(folder)
        watchedFolders.removeAll { $0.path == reference.path }
        watchedFolders.append(reference)
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

    static func digest(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
