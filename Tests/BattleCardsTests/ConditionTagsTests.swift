import Bestiary
import Foundation
import SwiftUI
import Testing
@testable import BattleCards

@Suite("Conditions and immunities on the card")
@MainActor
struct ConditionTagsTests {
    let style = CardTextStyle(body: FontName.condensed, bold: FontName.condensedBold, italic: FontName.condensedItalic,
                              size: 15, ink: .black, paper: .white, worse: .red, better: .green)

    /// A bestiary folder with no creatures and the frightened condition.
    func bestiaryWithFrightened() throws -> (BestiaryStore, URL) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Conditions-\(UUID())")
        let bestiary = folder.appendingPathComponent("Bestiary")
        try FileManager.default.createDirectory(at: bestiary, withIntermediateDirectories: true)
        try JSONEncoder().encode(BestiaryIndex(sourceRevision: "", entries: []))
            .write(to: bestiary.appendingPathComponent("index.json"))
        let frightened = ConditionDefinition(slug: "frightened", name: "Frightened", games: [.pathfinder],
                                             isValued: true, text: RulesText("You're gripped by fear."))
        try JSONEncoder().encode([frightened]).write(to: bestiary.appendingPathComponent("conditions.json"))
        return (try BestiaryStore(generatedDirectory: folder), folder)
    }

    @Test("Labels read as on the strips", arguments: [
        (AppliedCondition(slug: "frightened", value: 2), "Frightened 2"),
        (AppliedCondition(slug: "off-guard"), "Off Guard"),
        (AppliedCondition.persistent(DamagePart(formula: "1d6", type: "bleed")), "Bleed 1d6"),
        (AppliedCondition.reminder("Shield up", at: .startOfTurn), "⏰ Shield up")
    ])
    func labels(condition: AppliedCondition, label: String) {
        #expect(ConditionLabel.short(condition) == label)
    }

    @Test("Colors by kind", arguments: [
        ("sickened", Color(hex: 0x8E1B1B)), ("stunned", Color(hex: 0x5B2A86)), ("quickened", Color(hex: 0x1F6E3A)),
        ("dying", Color.black), ("dazzled", Color(hex: 0x4A4A4A))
    ])
    func colors(slug: String, color: Color) {
        #expect(ConditionLabel.color(AppliedCondition(slug: slug)) == color)
    }

    @Test("A defined condition opens its rules text, two deep at most")
    func conditionEntry() throws {
        let (bestiary, folder) = try bestiaryWithFrightened()
        defer { try? FileManager.default.removeItem(at: folder) }
        let context = GlossaryContext(bestiary: bestiary)
        let entry = try #require(context.conditionEntry("frightened"))
        #expect(entry.name == "Frightened")
        #expect(entry.category == "Condition")
        #expect(context.conditionEntry("custom-reminder") == nil)
        #expect(context.deeper.deeper.conditionEntry("frightened") == nil)
    }

    @Test("Tags draw, with and without a definition")
    func drawsTags() throws {
        let (bestiary, folder) = try bestiaryWithFrightened()
        defer { try? FileManager.default.removeItem(at: folder) }
        let tags = ConditionTags(conditions: [AppliedCondition(slug: "frightened", value: 1),
                                              AppliedCondition(slug: "prone")], style: style)
            .environment(\.glossary, GlossaryContext(bestiary: bestiary))
            .frame(width: 300)
        #expect(ImageRenderer(content: tags).cgImage != nil)
    }

    @Test("The card carries the conditions and the construct's immunities")
    func content() {
        var construct = Creature(key: "test.nodocite", name: "Nodocite Experimenter", game: .starfinder)
        construct.traits = TraitLine(rarity: "uncommon", size: "Medium", traits: ["construct", "robot"])
        construct.defenses.immunities = ["mental"]
        let frightened = AppliedCondition(slug: "frightened", value: 1)
        let content = CardContent(presenter: StatBlockPresenter(creature: construct, conditions: [frightened]))
        #expect(content.conditions == [frightened])
        let immunities = content.defensive.first?.segments.compactMap { segment -> String? in
            if case let .text(text) = segment { return text }
            return nil
        }
        #expect(immunities?.first?.hasPrefix("mental, bleed, death effects") == true)
    }
}
