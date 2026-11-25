import Foundation
@testable import SourceAttribution
import Testing

struct SourceCatalogTests {
    @Test func titlesMatchWhateverTheirSpacingCaseAndPunctuation() throws {
        let catalog = try SourceCatalog(entries: [quoted("Pathfinder Treasure Vault (Remastered)", .orc)])
        #expect(catalog.entry(for: " pathfinder treasure vault remastered")?.title
            == "Pathfinder Treasure Vault (Remastered)")
        #expect(catalog.entry(for: "Pathfinder Treasure Vault") == nil)
    }

    @Test func ampersandsCurlyQuotesAndAccentsDontCount() {
        #expect(SourceTitle.key("Guns & Gears") == SourceTitle.key("Guns and Gears"))
        #expect(SourceTitle.key("Destroyer’s Doom") == SourceTitle.key("Destroyer's Doom"))
        #expect(SourceTitle.key("Café") == "cafe")
    }

    @Test func aliasesFindTheirEntry() throws {
        var entry = quoted("Pathfinder Adventure Path #145: Hellknight Hill", .ogl)
        entry.aliases = ["Pathfinder #145: Hellknight Hill"]
        let catalog = try SourceCatalog(entries: [entry])
        #expect(catalog.entry(for: "Pathfinder #145: Hellknight Hill") == entry)
    }

    @Test func aTitleListedTwiceIsRefused() {
        var second = quoted("Other Book", .orc)
        second.aliases = ["monster core"]
        #expect(throws: AttributionError.duplicateTitles(["monster core"])) {
            try SourceCatalog(entries: [quoted("Monster Core", .orc), second])
        }
    }

    @Test func anUnreadableCatalogSaysWhich() throws {
        let folder = temporaryFolder()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appending(path: "broken.json")
        try Data("{".utf8).write(to: file)
        #expect {
            try SourceCatalog(contentsOf: file)
        } throws: { error in
            guard case .unreadableCatalog(let name, _) = error as? AttributionError else { return false }
            return name == "broken.json"
        }
    }

    @Test func theBundledCatalogLoads() throws {
        #expect(try SourceCatalog.bundled().entries.count > 300)
    }

    @Test func everyBundledEntryIsWellFormed() throws {
        for entry in try SourceCatalog.bundled().entries {
            #expect(["pf2e", "sf2e", ""].contains(entry.game), "\(entry.title): unknown game \(entry.game)")
            if entry.missingFacts.isEmpty {
                #expect(entry.reference?.isEmpty == false, "\(entry.title): complete but says nowhere where from")
            }
            if entry.license == SourceLicense.none {
                #expect(entry.note?.isEmpty == false, "\(entry.title): covered by neither license, with no note")
            }
        }
    }
}
