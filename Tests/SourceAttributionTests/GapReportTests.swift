import Foundation
@testable import SourceAttribution
import Testing

struct GapReportTests {
    private var catalog: SourceCatalog {
        get throws {
            var gap = CatalogEntry(title: "Tech Core")
            gap.game = "sf2e"
            var unchecked = quoted("Player Core", .orc)
            unchecked.game = "sf2e"
            unchecked.verified = false
            unchecked.reference = "Scrollkeeper metadata, SKU PZO1"
            var aliased = quoted("Pathfinder Adventure Path #145: Hellknight Hill", .ogl)
            aliased.aliases = ["Pathfinder #145: Hellknight Hill"]
            return try SourceCatalog(entries: [gap, unchecked, aliased, quoted("Monster Core", .orc)])
        }
    }

    private func report() throws -> String {
        try GapReport.markdown(catalog: catalog, usage: [
            "turnkeeper": tally("Monster Core", "Orphan Book", "Player Core"),
            "pawn-shop": tally("Orphan Book", "Pathfinder #145: Hellknight Hill")
        ])
    }

    @Test func listsSourcesTheCatalogLacks() throws {
        #expect(try report().contains("""
            ## Not in the catalog (1)

            - [ ] Orphan Book — used by pawn-shop, turnkeeper
            """))
    }

    @Test func listsEntriesMissingFactsEvenWhenNoAppUsesThemYet() throws {
        #expect(try report().contains("""
            ## Missing facts (1)

            - [ ] Tech Core (sf2e) — lacks license, year, publisher, credits — not used by any app yet
            """))
    }

    @Test func listsUncheckedEntriesWithWhereTheirFactsCameFrom() throws {
        #expect(try report().contains("""
            ## To check against the book's notice (1)

            - [ ] Player Core (sf2e) — Scrollkeeper metadata, SKU PZO1 — used by turnkeeper
            """))
    }

    @Test func anEmptySectionSaysNone() throws {
        let report = GapReport.markdown(catalog: try SourceCatalog(entries: []), usage: [:])
        #expect(report.contains("## Missing facts (0)\n\nNone.\n"))
    }

    /// `docs/source-attribution-gaps.md` must match the catalog and the source lists: regenerate it with
    /// `swift run SourceAttributionTool gaps docs/source-usage docs/source-attribution-gaps.md`.
    @Test func theCommittedGapListIsCurrent() throws {
        let docs = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appending(path: "docs")
        let lists = try FileManager.default.contentsOfDirectory(at: docs.appending(path: "source-usage"),
                                                                includingPropertiesForKeys: nil)
        var usage: [String: SourceTally] = [:]
        for list in lists where list.pathExtension == "txt" {
            let text = try String(contentsOf: list, encoding: .utf8)
            usage[list.deletingPathExtension().lastPathComponent] = try SourceTally(text: text)
        }
        let committed = try String(contentsOf: docs.appending(path: "source-attribution-gaps.md"), encoding: .utf8)
        #expect(committed == GapReport.markdown(catalog: try SourceCatalog.bundled(), usage: usage))
    }
}
