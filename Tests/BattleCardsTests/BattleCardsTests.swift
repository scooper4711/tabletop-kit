import Bestiary
import CoreGraphics
import Foundation
import ImageIO
import SwiftUI
import Testing
import UniformTypeIdentifiers
@testable import BattleCards

@Suite("Card backdrops by trait")
struct CardBackdropTests {
    @Test("The first rule that applies picks the landscape", arguments: [
        (["skeleton", "undead"], CardBackdrop.ruins), (["fiend", "fire"], .lava),
        (["cold", "giant"], .snow), (["Dragon"], .canyon), (["animal"], .meadow), ([], .meadow),
        (["undead", "fire"], .ruins)
    ])
    func picksTheLandscape(traits: [String], backdrop: CardBackdrop) {
        #expect(CardBackdrop(traits: traits) == backdrop)
    }
}

@Suite("Drawing cards")
@MainActor
struct CardRenderingTests {
    func creature(_ game: Game) -> Creature {
        var creature = Creature(key: "test.\(game.rawValue)", name: "Test Ogre", game: game)
        creature.level = 3
        return creature
    }

    func render(_ view: some View, pieces: CardArtPieces) -> CGImage? {
        let renderer = ImageRenderer(content: view.environment(\.cardArt, pieces).frame(width: 300))
        return renderer.cgImage
    }

    func piecesFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("CardPieces-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for piece in CardArtPieces.manifest {
            try writePNG(side: 16, to: folder.appendingPathComponent(piece.name + ".png"))
        }
        return folder
    }

    @Test("Fronts and backs of both games draw with the art and without it", arguments: [Game.pathfinder, .starfinder])
    func drawsEveryCard(game: Game) throws {
        let folder = try piecesFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        for pieces in [CardArtPieces(folder: folder), CardArtPieces(folder: nil)] {
            for template in [CreatureTemplate.normal, .elite] {
                #expect(render(BattleCard(creature: creature(game), template: template, scrolls: false),
                               pieces: pieces) != nil)
            }
            let back = CardBack(name: "Test Ogre", game: game, traits: ["giant"]) { Color.red }
            #expect(render(back, pieces: pieces) != nil)
        }
    }

    /// Creatures from the bestiary: a beast with grabs, a Starfinder plant, a goblin and a lich who cast spells.
    func fixture(_ name: String) throws -> Creature {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try JSONDecoder().decode(Creature.self, from: Data(contentsOf: url))
    }

    @Test("Real stat blocks draw with templates and conditions",
          arguments: ["owlbear", "ksarik", "goblin-pyro", "lich"])
    func drawsStatBlocks(name: String) throws {
        let creature = try fixture(name)
        let conditions = [AppliedCondition(slug: "frightened", value: 2),
                          AppliedCondition(slug: "off-guard", value: nil)]
        for template in [CreatureTemplate.weak, .elite] {
            let card = BattleCard(creature: creature, template: template, conditions: conditions, scrolls: false)
            #expect(render(card, pieces: CardArtPieces(folder: nil)) != nil)
        }
    }

    @Test("A player character's sheet draws as a card")
    func drawsAPlayerCharacter() throws {
        var hero = try fixture("goblin-pyro")
        hero.player = PlayerDetails(ancestry: "Goblin", heritage: "Unbreakable", background: "Street Urchin",
                                    className: "Alchemist")
        hero.player?.feats = ["Burn It!"]
        hero.player?.classFeatures = ["Research Field"]
        #expect(render(BattleCard(creature: hero, scrolls: false), pieces: CardArtPieces(folder: nil)) != nil)
    }

    @Test("Shapes fill their frames")
    func shapes() {
        let rect = CGRect(x: 0, y: 0, width: 100, height: 20)
        #expect(ElongatedHexagon().path(in: rect).boundingRect == rect)
        #expect(Hexagon().path(in: rect).boundingRect == rect)
    }
}

@Suite("Glossary links")
@MainActor
struct GlossaryTests {
    let style = CardTextStyle(body: FontName.condensed, bold: FontName.condensedBold, italic: FontName.condensedItalic,
                              size: 15, ink: .black, paper: .white, worse: .red, better: .green)

    @Test("Links go two deep, and only open with a glossary")
    func depth() throws {
        let context = GlossaryContext(bestiary: BestiaryStore())
        #expect(!context.linksOpen)
        #expect(context.deeper.deeper.depth == GlossaryContext.maximumDepth)
        let url = try #require(GlossaryContext.url(for: "pf2e.spells.abc"))
        #expect(context.entry(for: url) == nil)
        #expect(context.entry(for: try #require(URL(string: "https://example.com"))) == nil)
    }

    @Test("A glossary entry draws in a popover")
    func drawsAnEntry() {
        let entry = GlossaryEntry(id: "pf2e.spells.abc", name: "Fireball", category: "Spell 3",
                                  text: RulesText("A roaring blast of fire deals **6d6** fire damage."))
        let popover = GlossaryPopover(entry: entry, style: style).frame(width: 300)
        #expect(ImageRenderer(content: popover).cgImage != nil)
    }

    @Test("Fonts in a folder are registered; a missing folder is skipped")
    func fonts() {
        Fonts.register(from: nil)
        Fonts.register(from: FileManager.default.temporaryDirectory.appendingPathComponent("NoFonts-\(UUID())"))
        #expect(Font.pad(FontName.condensed, size: 12) == Font.custom(FontName.condensed, size: 12, relativeTo: .body))
    }
}
