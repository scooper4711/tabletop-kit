import ArtExtraction
import Foundation

/// Art printed without a name (shared libraries R2.3a): kept under a stand-in name, named by the same picture
/// printed with a name in another product.
extension StoreMerger {
    /// The entry nameless `found` joins, or a new one needing a name, counted in `report`.
    mutating func placedNameless(_ found: ExtractedPawn, print: SharedPrint,
                                 into report: inout ArtImportReport) throws -> SharedArtEntry {
        if NamelessProducts.contains(title: source.title), let named = try namedArt(sameAs: found) {
            report.namedFromOtherProducts += 1
            return joined(print, of: found, to: named)
        }
        if let waiting = try artNeedingName(size: found.size, where: { $0.fingerprint.matches(found.fingerprint) }) {
            report.alreadyKnown += 1
            return joined(print, of: found, to: waiting)
        }
        report.added += 1
        report.needingNames += 1
        var entry = newEntry(found, print: print)
        entry.name = NamelessProducts.standInName(forTitle: source.title)
        entry.needsName = true
        return entry
    }

    /// Art from a product that prints no names, still needing one, that is the same art as named `found`.
    mutating func waitingForName(sameArtAs found: ExtractedPawn) throws -> SharedArtEntry? {
        let nameless = try namelessSourceIDs()
        guard !nameless.isEmpty else { return nil }
        return try artNeedingName(size: found.size) { entry in
            entry.fingerprint.isSameArt(as: found.fingerprint)
                && entry.prints.contains { nameless.contains($0.print.sourceID) }
        }
    }

    // MARK: Helpers

    /// The named creature art of this game and `found`'s size closest to `found`'s picture, as it is now.
    private mutating func namedArt(sameAs found: ExtractedPawn) throws -> SharedArtEntry? {
        if namedCreatures == nil {
            namedCreatures = try ArtRows.entries(in: writer.database, where: "needsName = 0 AND game = ?",
                                                 [.text(source.game.rawValue)])
                .filter { !$0.artEntry.isItem }
        }
        let matches = (namedCreatures ?? []).filter { candidate in
            candidate.size == found.size && candidate.fingerprint.isSameArt(as: found.fingerprint)
        }
        let closest = matches.min { first, second in
            let firstDistance = first.fingerprint.namingDistance(from: found.fingerprint)
            let secondDistance = second.fingerprint.namingDistance(from: found.fingerprint)
            return firstDistance == secondDistance ? first.id.uuidString < second.id.uuidString
                                                   : firstDistance < secondDistance
        }
        // Read it again by a print's key: this PDF's earlier prints may have joined it since.
        guard let key = closest?.prints.first?.key else { return nil }
        return try entry(withKey: key)
    }

    /// The first art of this game and `size` still needing a name, by ID, that `isMatch` accepts.
    private func artNeedingName(size: PawnSize, where isMatch: (SharedArtEntry) -> Bool) throws -> SharedArtEntry? {
        try ArtRows.entries(in: writer.database, where: "needsName = 1 AND game = ? AND size = ?",
                            [.text(source.game.rawValue), .text(size.rawValue)])
            .sorted { $0.id.uuidString < $1.id.uuidString }
            .first(where: isMatch)
    }

    private mutating func namelessSourceIDs() throws -> Set<String> {
        if let namelessSources { return namelessSources }
        let ids = Set(try ArtRows.sources(in: writer.database)
            .filter { NamelessProducts.contains(title: $0.title) }.map(\.id))
        namelessSources = ids
        return ids
    }
}
