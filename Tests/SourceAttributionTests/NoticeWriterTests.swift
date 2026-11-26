import Foundation
@testable import SourceAttribution
import Testing

struct NoticeWriterTests {
    private let horror = "Mite from the Tome of Horrors Complete © 2011, Necromancer Games, Inc."
    private var catalog: SourceCatalog {
        get throws {
            var gap = CatalogEntry(title: "New Book")
            gap.game = "sf2e"
            var neither = quoted("Foundry Only", .none)
            neither.note = "Paizo–Foundry agreement"
            return try SourceCatalog(entries: [
                quoted("Monster Core", .orc), quoted("Tech Core", .orc),
                quoted("Bestiary", .ogl, includes: [horror]), quoted("Bestiary 2", .ogl, includes: [horror]),
                gap, neither
            ])
        }
    }

    @Test func orcSourcesAreListedInTheAttributionNoticeInOrder() throws {
        let files = try NoticeWriter.notices(for: tally("Tech Core", "Monster Core"), catalog: catalog)
        #expect(files.map(\.name) == ["ORC License.md"])
        let text = try #require(files.first?.text)
        #expect(text.hasPrefix("1. ORC NOTICE\n"))
        #expect(text.contains("""
            2. ATTRIBUTION NOTICE
            * Monster Core © 2024, Paizo Inc.; Author: Someone.
            * Tech Core © 2024, Paizo Inc.; Author: Someone.

            3. RESERVED MATERIAL
            """))
        #expect(!text.contains("static/licenses") && !text.contains("{{"))
    }

    @Test func oglSourcesFollowTheOglsOwnNoticeWithTheirIncludesOnce() throws {
        let files = try NoticeWriter.notices(for: tally("Bestiary 2", "Bestiary"), catalog: catalog)
        #expect(files.map(\.name) == ["Open Game License.md"])
        let text = try #require(files.first?.text)
        #expect(text.hasPrefix("OPEN GAME LICENSE Version 1.0a\n"))
        #expect(text.hasSuffix("""
            15. COPYRIGHT NOTICE
            * Open Game License v 1.0 Copyright 2000, Wizards of the Coast, Inc.
            * Bestiary © 2024, Paizo Inc.; Author: Someone.
            * Bestiary 2 © 2024, Paizo Inc.; Author: Someone.
            * \(horror)

            """))
    }

    @Test func sourcesUnderBothLicensesGetBothNotices() throws {
        let files = try NoticeWriter.notices(for: tally("Bestiary", "Monster Core"), catalog: catalog)
        #expect(files.map(\.name) == ["ORC License.md", "Open Game License.md"])
    }

    @Test func everySourceThatCantBeAttributedIsListedAtOnce() throws {
        let sources = tally("Monster Core", "Unknown Book", "New Book", "Foundry Only")
        #expect(throws: AttributionError.unattributedSources([
            .init(title: "Foundry Only",
                  reason: "covered by neither the ORC License nor the OGL (Paizo–Foundry agreement)"),
            .init(title: "New Book", reason: "the catalog lacks its license, year, publisher, credits"),
            .init(title: "Unknown Book", reason: "not in the catalog")
        ])) {
            try NoticeWriter.notices(for: sources, catalog: catalog)
        }
    }

    @Test func writingReplacesANoticeTheSourcesNoLongerNeed() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try NoticeWriter.write(for: tally("Bestiary"), catalog: catalog, to: folder)
        let written = try NoticeWriter.write(for: tally("Monster Core"), catalog: catalog, to: folder)
        #expect(written.map(\.lastPathComponent) == ["ORC License.md"])
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        #expect(names == ["ORC License.md"])
    }

    @Test func errorsDescribeTheOperationAndEveryProblem() {
        let error = AttributionError.unattributedSources([.init(title: "New Book", reason: "not in the catalog")])
        #expect(error.description.hasPrefix("Writing the attribution notices failed: 1 sources"))
        #expect(error.description.hasSuffix("\n  New Book: not in the catalog"))
        #expect(AttributionError.duplicateTitles(["A", "B"]).description.hasSuffix("twice: A; B"))
        #expect(AttributionError.unreadableCatalog("x.json", "bad").description
            == "Reading the source catalog x.json failed: bad")
        #expect(AttributionError.malformedTally(line: 3, "z").description.contains("line 3"))
    }
}

struct CollectionTests {
    private func blog() -> CatalogEntry {
        var blog = CatalogEntry(title: "Pathfinder Blog")
        blog.license = .orc
        blog.includes = ["Redpitch Alchemy © 2020, Paizo Inc.; Author: Ron Lundeen.", "Apex of Power © 2023, Paizo Inc."]
        return blog
    }

    @Test func aCollectionNeedsOnlyALicense() {
        #expect(blog().isCollection && blog().missingFacts.isEmpty)
        var unlicensed = blog()
        unlicensed.license = nil
        #expect(unlicensed.missingFacts == ["license"])
    }

    @Test func aCollectionIsAttributedByItsPartsAlone() throws {
        let catalog = try SourceCatalog(entries: [blog(), quoted("Monster Core", .orc)])
        let text = try #require(try NoticeWriter.notices(for: tally("Pathfinder Blog", "Monster Core"), catalog: catalog)
            .first?.text)
        #expect(text.contains("""
            * Monster Core © 2024, Paizo Inc.; Author: Someone.
            * Apex of Power © 2023, Paizo Inc.
            * Redpitch Alchemy © 2020, Paizo Inc.; Author: Ron Lundeen.
            """))
        #expect(!text.contains("Pathfinder Blog"))
    }
}
