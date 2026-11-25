import Foundation
@testable import SourceAttribution
import Testing

struct CatalogEntryTests {
    private func built(_ names: [String]...) -> CatalogEntry {
        var entry = CatalogEntry(title: "Tech Core")
        entry.license = .orc
        entry.year = 2025
        entry.publisher = "Paizo Inc."
        entry.credits = zip(["Authors", "Designers"], names).map { CatalogEntry.Credit(role: $0, names: $1) }
        return entry
    }

    @Test func aQuotedNoticeIsListedAsItIs() {
        #expect(quoted("Monster Core", .orc).noticeLine == "Monster Core © 2024, Paizo Inc.; Author: Someone.")
    }

    @Test func aBuiltNoticeJoinsNamesThePaizoWay() {
        #expect(built(["A"]).noticeLine == "Tech Core © 2025, Paizo Inc.; Authors: A.")
        #expect(built(["A", "B"]).noticeLine == "Tech Core © 2025, Paizo Inc.; Authors: A and B.")
        #expect(built(["A", "B", "C"]).noticeLine == "Tech Core © 2025, Paizo Inc.; Authors: A, B, and C.")
    }

    @Test func aBuiltNoticeListsEveryRoleAndSkipsEmptyOnes() {
        #expect(built(["A"], ["D"]).noticeLine == "Tech Core © 2025, Paizo Inc.; Authors: A; Designers: D.")
        #expect(built(["A"], []).noticeLine == "Tech Core © 2025, Paizo Inc.; Authors: A.")
    }

    @Test func aCompleteEntryLacksNothing() {
        #expect(built(["A"]).missingFacts.isEmpty)
        #expect(quoted("Monster Core", .ogl).missingFacts.isEmpty)
    }

    @Test func aBareEntryLacksEveryFact() {
        #expect(CatalogEntry(title: "New Book").missingFacts == ["license", "year", "publisher", "credits"])
    }

    @Test func aQuotedNoticeStillNeedsALicense() {
        var entry = quoted("Monster Core", .orc)
        entry.license = nil
        #expect(entry.missingFacts == ["license"])
    }

    @Test func creditsWithoutNamesCountAsMissing() {
        #expect(built([]).missingFacts == ["credits"])
    }

    @Test func decodingFillsInWhatTheJSONLeavesOut() throws {
        let json = #"[{"title": "Tech Core", "license": "orc", "year": 2025}]"#
        let entry = try #require(try JSONDecoder().decode([CatalogEntry].self, from: Data(json.utf8)).first)
        #expect(entry.aliases.isEmpty && entry.credits.isEmpty && entry.includes.isEmpty)
        #expect(entry.verified && entry.license == .orc && entry.year == 2025 && entry.notice == nil)
    }
}
