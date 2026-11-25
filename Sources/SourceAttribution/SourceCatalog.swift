import Foundation

/// The source books the toolkit apps may ship game text from, looked up by title.
///
/// The bundled catalog is `Resources/source-catalog.json`, kept by hand: a pf2e or sf2e update that brings a new
/// source fails the import that uses it until the source is added.
public struct SourceCatalog: Sendable {
    public let entries: [CatalogEntry]
    private let index: [String: Int]

    public init(entries: [CatalogEntry]) throws {
        var index: [String: Int] = [:]
        var duplicates: [String] = []
        for (position, entry) in entries.enumerated() {
            for title in [entry.title] + entry.aliases {
                let key = SourceTitle.key(title)
                if index.updateValue(position, forKey: key) != nil { duplicates.append(title) }
            }
        }
        guard duplicates.isEmpty else { throw AttributionError.duplicateTitles(duplicates) }
        self.entries = entries
        self.index = index
    }

    public init(contentsOf url: URL) throws {
        let entries: [CatalogEntry]
        do {
            entries = try JSONDecoder().decode([CatalogEntry].self, from: Data(contentsOf: url))
        } catch {
            throw AttributionError.unreadableCatalog(url.lastPathComponent, String(describing: error))
        }
        try self.init(entries: entries)
    }

    /// The catalog that ships with Tabletop Kit.
    public static func bundled() throws -> SourceCatalog {
        guard let url = Bundle.module.url(forResource: "source-catalog", withExtension: "json") else {
            throw AttributionError.unreadableCatalog("source-catalog.json", "not in the bundle")
        }
        return try SourceCatalog(contentsOf: url)
    }

    /// The entry with this title or alias, compared as `SourceTitle.key` does.
    public func entry(for title: String) -> CatalogEntry? {
        index[SourceTitle.key(title)].map { entries[$0] }
    }
}

/// How source titles are compared: case, accents, punctuation and spacing don't count, and "&" is "and", so the
/// data's `" Pathfinder Treasure Vault (Remastered)"` finds `Pathfinder Treasure Vault (Remastered)`.
public enum SourceTitle {
    public static func key(_ title: String) -> String {
        let folded = title.replacingOccurrences(of: "&", with: " and ")
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
        return String(String.UnicodeScalarView(folded.unicodeScalars.filter(CharacterSet.alphanumerics.contains)))
    }
}
