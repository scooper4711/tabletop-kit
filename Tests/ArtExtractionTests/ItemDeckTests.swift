import Foundation
import Testing
@testable import ArtExtraction
import ArtExtractionTestSupport

@Suite struct ItemDeckTests {
    let folder = temporaryFolder()

    /// A folder named as Scrollkeeper names a product's, holding its download's folder.
    func productFolder(_ name: String) throws -> URL {
        let download = folder.appendingPathComponent(name).appendingPathComponent("\(name) - PDF")
        try FileManager.default.createDirectory(at: download, withIntermediateDirectories: true)
        return download
    }

    @Test func recognizesItemDecksByTheirFolderAndLeavesDecksWithoutArtAlone() throws {
        let guns = try writeCardDeck(threeItems, named: "PZO2230 Guns Deck 001-055.pdf",
                                     in: try productFolder("Pathfinder Guns Deck"))
        let deck = try #require(CardDeck.containing(guns))
        #expect(deck.kind == .items && deck.statsFile == nil && deck.title == "Pathfinder Guns Deck")
        let spells = try writeCardDeck(threeItems, named: "Spells.pdf",
                                       in: try productFolder("Pathfinder Primal Spell Deck (Remastered)"))
        #expect(CardDeck.containing(spells) == nil)
        #expect(CardDeck.containing(try writeCardDeck(threeCards, in: folder))?.kind == .creatures)
        #expect(ProductScanner.artPDFs(in: folder).map(\.lastPathComponent).sorted()
                == ["PZO2230 Guns Deck 001-055.pdf", "Pathfinder Test Battle Cards.pdf"])
    }

    @Test func pairsSidesWhoseNamesDifferBeyondTheSide() throws {
        let relics = try productFolder("Pathfinder Relics Deck")
        let fronts = relics.appendingPathComponent("PZO2234 Relic Deck Fronts.pdf")
        let backs = relics.appendingPathComponent("PZO2234 Relics Deck Backs.pdf")
        try makePDF(size: cardPage, pages: threeItems.map { $0.drawStats }).write(to: fronts)
        try makePDF(size: cardPage, pages: threeItems.map { $0.drawArt }).write(to: backs)
        #expect(CardDeck.containing(fronts) == CardDeck(artFile: backs, statsFile: fronts, kind: .items))
    }

    @Test(arguments: [CardLayout.alternating, .sameSide])
    func findsEachItemByName(layout: CardLayout) throws {
        let file = try writeCardDeck(threeItems, layout: layout, named: "Deck.pdf",
                                     in: try productFolder("Pathfinder Deck of Endless Treasure"))
        let result = try PawnExtractor.extract(from: file)
        #expect(result.pawns.map(\.name) == ["Healing Potion", "Bayonet", "Knuckle Duster"])
        #expect(result.pawns.allSatisfy { if case .item = $0.shape { $0.traits.isEmpty } else { false } })
    }
}

@Suite struct ItemCardTextTests {
    @Test func readsTheNameBeforeTheLevelOrGift() {
        #expect(ItemCardText.name(in: "BEACON SHOT ITEM 3\nCONSUMABLE EVOCATION MAGICAL\nPrice 10 gp") == "Beacon Shot")
        #expect(ItemCardText.name(in: "Mountebank’s\nPassage\nMOUNTEBANK’S PASSAGE ITEM 15") == "Mountebank’s Passage")
        #expect(ItemCardText.name(in: "DEADLY SPARK MINOR GIFT\nAIR ELECTRICITY") == "Deadly Spark")
    }

    @Test func readsANamePrintedAloneOnTheFirstLines() {
        #expect(ItemCardText.name(in: "Knuckle Duster\nThis bit of hardened metal, favored by street")
                == "Knuckle Duster")
        #expect(ItemCardText.name(in: "Waterproof Firearm\nCarrying Case\nThis buttoned, leather case")
                == "Waterproof Firearm Carrying Case")
        #expect(ItemCardText.name(in: "BATTLE AXE\nSweep\nDamage 1d8 S; Bulk 1") == "Battle Axe")
    }

    @Test func skipsPagesThatNameNoItem() {
        #expect(ItemCardText.name(in: "Instructions\nThis deck includes the base versions") == nil)
        #expect(ItemCardText.name(in: "DECK OF ENDLESS TREASURE\nFLEXIBLE READING") == nil)
        #expect(ItemCardText.name(in: "2\nRooting\nThe item") == nil)
        #expect(ItemCardText.name(in: "these small pieces of cloth") == nil)
        #expect(ItemCardText.name(in: "") == nil)
    }
}

@Suite struct SameSidePairingTests {
    @Test func pairsEachPageWithItselfWhenHardlyAnyIsArtAlone() {
        let textless = [true] + Array(repeating: false, count: 11)
        #expect(CardPairing.pairs(textless: textless).map(\.art) == Array(0..<12))
        #expect(CardPairing.pairs(textless: textless).allSatisfy { $0.art == $0.stats })
    }
}
