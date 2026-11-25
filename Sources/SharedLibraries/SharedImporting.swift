import ArtExtraction
import Foundation

/// Reading PDFs into the shared art library (R1.3): each PDF once, by whichever app sees it first.
extension SharedLibrary {
    /// Adds a PDF this app has access to: a copy kept in the library, or else a reference to it where it is.
    @discardableResult
    public func add(_ url: URL, keeping: Bool) throws -> ArtImportReport {
        let file = ArtLibrary.libraryFile(for: url)
        if let known = try knownSource(digest: ArtLibrary.digest(of: file)),
           known.readerVersion >= PawnExtractor.version(of: file) {
            return try recordAccess(to: known, file: file, keeping: keeping)
        }
        let prepared = try ArtLibrary.prepare(url)
        return try commit(prepared, location: keeping ? .kept : .referenced(FileReference(prepared.file)))
    }

    /// Adds a prepared PDF's art, merging art the library has already (`StoreMerger`), then draws the new art's
    /// pictures. A PDF the current reader has read only gains this app's access to it; one read by an older
    /// reader is read afresh. A PDF another app is reading is skipped (`isReadByAnotherApp`).
    @discardableResult
    public func commit(_ prepared: PreparedArt, location: SourceLocation) throws -> ArtImportReport {
        var report = ArtImportReport(sourceTitle: prepared.title, unreadablePages: prepared.extraction.unreadablePages)
        let known = try knownSource(digest: prepared.digest)
        let readerVersion = PawnExtractor.version(of: prepared.file)
        if let known, known.readerVersion >= readerVersion {
            return try recordAccess(to: known, file: prepared.file, keeping: location == .kept)
        }
        guard try claim(sourceID: prepared.digest) else {
            report.isReadByAnotherApp = true
            return report
        }
        defer { try? releaseClaim(sourceID: prepared.digest) }
        if location == .kept { try keep(prepared.file, digest: prepared.digest) }
        let source = ArtSource(id: prepared.digest, title: prepared.title, game: GameSystem(title: prepared.title),
                               location: location, byteCount: prepared.byteCount, readerVersion: readerVersion,
                               artFound: prepared.extraction.pawns.count)
        let pictures = try write { writer in
            let older = try writer.takeOutPrints(of: source.id)
            try writer.add(source, for: app)
            var merger = StoreMerger(writer: writer, library: self, source: source, file: prepared.file)
            try merger.merge(prepared.extraction.pawns, into: &report)
            try writer.retire(older, app: app)
            return merger.pictures
        }
        if let failure = try drawPictures(pictures, from: prepared.file).failure { throw failure }
        return report
    }

    /// True when the PDF at `url` is in the library: recognized by its size and this app's path to it, or else
    /// its contents.
    public func contains(_ url: URL) -> Bool {
        knownSource(of: url) != nil
    }

    /// The library's source for the PDF at `url`, recognized as `contains` does.
    func knownSource(of url: URL) -> SharedSource? {
        let file = ArtLibrary.libraryFile(for: url)
        guard let sources = try? sources() else { return nil }
        let byteCount = (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int) ?? -1
        if let known = sources.first(where: { $0.byteCount == byteCount && Self.path(of: $0, for: app) == file.path }) {
            return known
        }
        return (try? ArtLibrary.digest(of: file)).flatMap { digest in sources.first { $0.id == digest } }
    }

    /// Takes a PDF out of the library for every app, with the art no other PDF prints and its pictures.
    public func remove(sourceID: String) throws {
        let pictures = try write { writer in try writer.remove(sourceID: sourceID) }
        removePictures(noLongerNamedAmong: pictures)
        try? FileManager.default.removeItem(at: keptFile(sourceID: sourceID))
    }

    // MARK: Helpers

    private func knownSource(digest: String) throws -> SharedSource? {
        try sources().first { $0.id == digest }
    }

    /// Records how this app reaches a PDF the library has read already.
    private func recordAccess(to known: SharedSource, file: URL, keeping: Bool) throws -> ArtImportReport {
        var report = ArtImportReport(sourceTitle: known.title)
        report.wasImported = true
        guard known.artSource(for: app) == nil || (keeping && !known.isKept) else { return report }
        if keeping { try keep(file, digest: known.id) }
        try writeAccess(to: known, location: keeping ? .kept : .referenced(try FileReference(file)))
        return report
    }

    /// Writes how this app reaches a PDF the library has.
    func writeAccess(to known: SharedSource, location: SourceLocation) throws {
        let source = ArtSource(id: known.id, title: known.title, game: known.game, location: location,
                               byteCount: known.byteCount, readerVersion: known.readerVersion, artFound: known.artFound)
        try write { writer in try writer.add(source, for: app) }
    }

    private func keep(_ file: URL, digest: String) throws {
        let destination = keptFile(sourceID: digest)
        guard !FileManager.default.fileExists(atPath: destination.path) else { return }
        do {
            try FileManager.default.copyItem(at: file.resolvingSymlinksInPath(), to: destination)
        } catch {
            throw SharedLibraryError(operation: "Keeping \(file.lastPathComponent)", detail: error.localizedDescription)
        }
    }

    /// Where `app` last saw a referenced PDF; nil for a kept one.
    static func path(of source: SharedSource, for app: TablesideApp) -> String? {
        switch source.access[app] {
        case .referenced(let reference): reference.path
        case .inFolder(let folder, let relativePath): (folder.path as NSString).appendingPathComponent(relativePath)
        case .kept, nil: nil
        }
    }
}
