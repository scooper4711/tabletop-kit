import Foundation
@testable import TablesideShared
import UniformTypeIdentifiers

/// Stands in for `NSWorkspace`, recording what was asked of it.
@MainActor
final class FakeLauncher: ApplicationLauncher {
    var installed = true
    var takesRequests = true
    private(set) var backgroundURLs: [URL] = []
    private(set) var foregroundURLs: [URL] = []
    private(set) var launched: [String] = []

    func isInstalled(_ bundleIdentifier: String) -> Bool { installed }
    func openInBackground(_ url: URL) { backgroundURLs.append(url) }
    func openInForeground(_ url: URL) { foregroundURLs.append(url) }
    func launch(_ bundleIdentifier: String) { launched.append(bundleIdentifier) }
}

extension ScrollkeeperBridgeConfiguration {
    /// As Pluck configures the bridge: every title that may hold a PDF, PDFs only, one request at a time.
    static var reader: ScrollkeeperBridgeConfiguration {
        var configuration = ScrollkeeperBridgeConfiguration(appKey: "reader",
                                                            lists: { $0.mayHold { $0.conforms(to: .pdf) } },
                                                            opens: { $0.conforms(to: .pdf) })
        configuration.sendsOneRequestAtATime = true
        return configuration
    }

    /// As Mapsmith configures it: the maps, PDFs and images, no kind, several requests at once.
    static var mapper: ScrollkeeperBridgeConfiguration {
        var configuration = ScrollkeeperBridgeConfiguration(appKey: "mapper", lists: { $0.kind == "Maps" },
                                                            opens: { $0.conforms(to: .pdf) || $0.conforms(to: .image) })
        configuration.showsKind = false
        return configuration
    }

    /// The same, for an app that reads only the library list and never asks Scrollkeeper for it.
    static var libraryOnlyMapper: ScrollkeeperBridgeConfiguration {
        var configuration = mapper
        configuration.asksForIndex = false
        return configuration
    }
}

/// The file Scrollkeeper hands over, in a temporary directory.
enum HandedOverIndex {
    static let sevenDooms = """
        {"sku": "PZO90200E", "title": "Seven Dooms for Sandpoint", "kind": "Adventure Paths",
         "series": "Seven Dooms", "number": 200, "downloaded": true}
        """
    static let core = #"{"sku": "PZO2101E", "title": "Core Rulebook", "kind": "Rulebooks", "downloaded": false}"#

    static func write(version: Int = 1, titles: [String] = [sevenDooms, core]) throws -> URL {
        try write("""
            {"formatVersion": \(version), "generatedAt": "2026-10-18T18:00:00Z",
             "titles": [\(titles.joined(separator: ","))]}
            """)
    }

    static func write(_ text: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "\(UUID().uuidString).\(ScrollkeeperIndex.fileExtension)")
        try Data(text.utf8).write(to: url)
        return url
    }
}

enum BridgeTestError: Error {
    case notLoaded(ScrollkeeperBridge.State)
}

extension ScrollkeeperBridge {
    /// The list shown, or an error saying what the bridge shows instead.
    func loadedIndex() throws -> ScrollkeeperIndex {
        guard case let .loaded(index) = state else { throw BridgeTestError.notLoaded(state) }
        return index
    }
}
