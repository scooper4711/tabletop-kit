import Foundation

public enum ArtLibraryError: Error, Equatable, CustomStringConvertible {
    case saveFailed(String)

    public var description: String {
        switch self {
        case .saveFailed(let detail): "Saving the art library failed: \(detail)"
        }
    }
}

/// The creature art in the user's Paizo PDFs (R2): the PDFs, kept or referenced where they are, and each piece
/// of art with every product that prints it. It isn't safe to use from more than one thread at a time.
public final class ArtLibrary {
    /// The library's folder: `art-library.json`, kept PDFs in `Sources`, tokens' art in `Tokens`.
    public let folder: URL
    public internal(set) var sources: [ArtSource] = []
    public internal(set) var entries: [ArtEntry] = []
    /// Folders whose new PDFs are added by reference (`addNewFiles`), such as Scrollkeeper's downloads.
    public internal(set) var watchedFolders: [FileReference] = []
    private var statuses: [String: SourceStatus] = [:]

    /// The library stored in `folder`, created empty when there is none.
    public init(folder: URL) throws {
        self.folder = folder
        for subfolder in [sourcesFolder, tokensFolder] {
            try FileManager.default.createDirectory(at: subfolder, withIntermediateDirectories: true)
        }
        guard let data = try? Data(contentsOf: storeFile) else { return }
        let stored = try JSONDecoder().decode(StoredArtLibrary.self, from: data)
        sources = stored.sources
        entries = stored.entries
        watchedFolders = stored.watchedFolders
    }

    public func source(id: String) -> ArtSource? { sources.first { $0.id == id } }

    /// Whether a PDF's art can be drawn; checked once, until `refreshStatuses`.
    public func status(of source: ArtSource) -> SourceStatus {
        if let known = statuses[source.id] { return known }
        let status: SourceStatus = withFile(of: source) { _ in true } == true ? .available : .missing
        statuses[source.id] = status
        return status
    }

    /// Checks again whether each PDF is where it was, as after the user moved or restored files.
    public func refreshStatuses() {
        statuses.removeAll()
    }

    /// The PDFs that have gone missing.
    public var missingSources: [ArtSource] { sources.filter { status(of: $0) == .missing } }

    /// True when some product printing the art can be drawn from: its PDF is available, or the art was kept.
    public func isAvailable(_ entry: ArtEntry) -> Bool {
        entry.prints.contains { print in
            print.tokenFile != nil || source(id: print.sourceID).map { status(of: $0) == .available } == true
        }
    }

    /// The art printed by a PDF.
    public func entries(from source: ArtSource) -> [ArtEntry] {
        entries.filter { $0.prints.contains { $0.sourceID == source.id } }
    }

    /// Takes a PDF out of the library, with the art no other product prints.
    public func remove(_ source: ArtSource) throws {
        for index in entries.indices.reversed() {
            for print in entries[index].prints where print.sourceID == source.id {
                if let file = print.tokenFile { try? FileManager.default.removeItem(at: tokenURL(file)) }
            }
            entries[index].prints.removeAll { $0.sourceID == source.id }
            if entries[index].prints.isEmpty { entries.remove(at: index) }
        }
        sources.removeAll { $0.id == source.id }
        statuses[source.id] = nil
        try? FileManager.default.removeItem(at: keptFile(id: source.id))
        try save()
    }

    /// Runs `body` with the PDF's file and access to it; nil when it is missing.
    func withFile<Result>(of source: ArtSource, _ body: (URL) throws -> Result) rethrows -> Result? {
        switch source.location {
        case .kept:
            let url = keptFile(id: source.id)
            return FileManager.default.fileExists(atPath: url.path) ? try body(url) : nil
        case .referenced(let reference):
            return try reference.withAccess(body)
        case .inFolder(let reference, let relativePath):
            let found = try reference.withAccess { folder -> Result? in
                let url = folder.appendingPathComponent(relativePath)
                return FileManager.default.isReadableFile(atPath: url.path) ? try body(url) : nil
            }
            return found ?? nil
        }
    }

    func save() throws {
        let stored = StoredArtLibrary(sources: sources, entries: entries, watchedFolders: watchedFolders)
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            try encoder.encode(stored).write(to: storeFile, options: .atomic)
        } catch {
            throw ArtLibraryError.saveFailed(error.localizedDescription)
        }
    }

    var storeFile: URL { folder.appendingPathComponent("art-library.json") }
    var sourcesFolder: URL { folder.appendingPathComponent("Sources", isDirectory: true) }
    var tokensFolder: URL { folder.appendingPathComponent("Tokens", isDirectory: true) }
    func keptFile(id: String) -> URL { sourcesFolder.appendingPathComponent("\(id).pdf") }
    func tokenURL(_ file: String) -> URL { tokensFolder.appendingPathComponent(file) }
}

/// The library as saved.
struct StoredArtLibrary: Codable {
    var version = 1
    var sources: [ArtSource]
    var entries: [ArtEntry]
    var watchedFolders: [FileReference]
}
