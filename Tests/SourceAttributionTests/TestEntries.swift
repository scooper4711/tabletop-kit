import Foundation
@testable import SourceAttribution

/// A complete entry that quotes its notice.
func quoted(_ title: String, _ license: SourceLicense, includes: [String] = []) -> CatalogEntry {
    var entry = CatalogEntry(title: title)
    entry.license = license
    entry.notice = "\(title) © 2024, Paizo Inc.; Author: Someone."
    entry.includes = includes
    return entry
}

func tally(_ titles: String...) -> SourceTally {
    var tally = SourceTally()
    for title in titles { tally.add(title) }
    return tally
}

func temporaryFolder() -> URL {
    FileManager.default.temporaryDirectory.appending(path: "SourceAttributionTests-\(UUID().uuidString)")
}
