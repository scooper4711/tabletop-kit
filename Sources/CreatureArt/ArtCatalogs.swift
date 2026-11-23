import ArtExtraction
import Bestiary
import Foundation
import SharedLibraries

/// The catalog of each kind of library.
extension CreatureArtStore {
    static func catalog(of library: ArtLibrary) -> ArtCatalog {
        library.refreshStatuses()
        let titles = Dictionary(uniqueKeysWithValues: library.sources.map { ($0.id, $0.title) })
        let art = library.entries.map { entry in
            libraryArt(entry, titles: titles, isAvailable: library.isAvailable(entry))
        }
        let sources = library.sources.map { source in
            ArtSourceSummary(id: source.id, title: source.title, place: place(of: source.location),
                             isMissing: library.status(of: source) == .missing,
                             hasLostArt: library.entries(from: source).contains { !library.isAvailable($0) },
                             artCount: library.entries(from: source).count)
        }
        return ArtCatalog(art: art, sources: sorted(sources), watchedFolders: library.watchedFolders.map(\.path))
    }

    static func catalog(of library: SharedLibrary) -> ArtCatalog {
        let sharedSources = (try? library.sources()) ?? []
        let entries = (try? library.artEntries()) ?? []
        let titles = Dictionary(uniqueKeysWithValues: sharedSources.map { ($0.id, $0.title) })
        let available = Set(sharedSources.filter { library.status(of: $0) == .available }.map(\.id))
        let art = entries.map { entry in
            // A named picture is here or in iCloud, where showing the art fetches it (library sync R4.2).
            let isAvailable = entry.picture != nil || entry.prints.contains { available.contains($0.print.sourceID) }
            return libraryArt(entry.artEntry, titles: titles, isAvailable: isAvailable)
        }
        var artCounts: [String: Int] = [:]
        var sourcesWithLostArt: Set<String> = []
        for entry in entries {
            let entrySources = Set(entry.prints.map(\.print.sourceID))
            for source in entrySources { artCounts[source, default: 0] += 1 }
            let canShow = entry.picture != nil || !entrySources.isDisjoint(with: available)
            if !canShow { sourcesWithLostArt.formUnion(entrySources) }
        }
        let sources = sharedSources.map { source in
            ArtSourceSummary(id: source.id, title: source.title, place: place(of: source, for: library.app),
                             isMissing: !available.contains(source.id),
                             hasLostArt: sourcesWithLostArt.contains(source.id),
                             artCount: artCounts[source.id] ?? 0)
        }
        let watched = ((try? library.watchedFolders()) ?? []).map(\.path)
        return ArtCatalog(art: art, sources: sorted(sources), watchedFolders: watched)
    }

    // MARK: Helpers

    private static func libraryArt(_ entry: ArtEntry, titles: [String: String], isAvailable: Bool) -> LibraryArt {
        let sourceTitles = Set(entry.prints.compactMap { titles[$0.sourceID] }).sorted()
        let game: Game = entry.game == .starfinder ? .starfinder : .pathfinder
        return LibraryArt(id: entry.id, name: entry.name, game: game,
                          isRemastered: sourceTitles.contains { title in
                              remasteredProducts.contains { title.localizedCaseInsensitiveContains($0) }
                          },
                          isToken: entry.prints.first?.kind == .token, isAvailable: isAvailable,
                          sourceTitles: sourceTitles, isItem: entry.isItem)
    }

    private static func sorted(_ sources: [ArtSourceSummary]) -> [ArtSourceSummary] {
        sources.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    private static func place(of location: SourceLocation) -> String {
        switch location {
        case .kept: "Kept in the app"
        case .referenced(let reference): reference.path
        case .inFolder(let folder, let relativePath): (folder.path as NSString).appendingPathComponent(relativePath)
        }
    }

    /// Where a shared PDF is for `app`, or which apps reach it when `app` can't (R3.6).
    private static func place(of source: SharedSource, for app: TablesideApp) -> String {
        if let artSource = source.artSource(for: app) { return place(of: artSource.location) }
        let readers = source.access.keys.map(\.rawValue).sorted()
        return readers.isEmpty ? "Not reachable" : "Read by \(readers.joined(separator: " and "))"
    }
}
