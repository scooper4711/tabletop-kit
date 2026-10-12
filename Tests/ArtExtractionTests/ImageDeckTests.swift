import CoreGraphics
import Foundation
import Testing
@testable import ArtExtraction
import ArtExtractionTestSupport

@Suite struct ImageDeckTests {
    let folder = temporaryFolder()
    let fiveItems = ["DAGGER", "LONGSWORD", "FULL PLATE", "WHIP", "SPEAR"]
    var deckFolder: URL {
        folder.appendingPathComponent("Pathfinder Weapons & Armor Deck/Pathfinder Weapons & Armor Deck (Download)")
    }

    @Test func recognizesAFolderOfCardPicturesInAnItemDeck() throws {
        try writeImageDeck(fiveItems, in: deckFolder)
        let deck = try #require(ImageDeck.containing(deckFolder))
        #expect(deck.cards.map(\.number) == [1, 2, 3, 4, 5] && deck.cards.allSatisfy { $0.front != nil })
        #expect(deck.title == "Pathfinder Weapons & Armor Deck")
        #expect(ImageDeck.containing(deckFolder.appendingPathComponent("Deck Backs2.jpg")) == deck)
        #expect(ProductScanner.artPDFs(in: folder).map { $0.resolvingSymlinksInPath().path }
                == [deckFolder.resolvingSymlinksInPath().path])
        let other = folder.appendingPathComponent("Pathfinder Condition Card Deck")
        try writeImageDeck(["FRIGHTENED", "SICKENED", "PRONE"], in: other)
        #expect(ImageDeck.containing(other) == nil)
    }

    @Test func cutsEachItemFromTheSharedBackgroundAndReadsItsName() throws {
        try writeImageDeck(fiveItems, in: deckFolder)
        let result = try PawnExtractor.extract(from: deckFolder)
        #expect(result.pawns.map(\.name) == ["Dagger", "Longsword", "Full Plate", "Whip", "Spear"])
        let first = try #require(result.pawns.first)
        guard case .drawnItem(let png) = first.shape else { Issue.record("expected a drawn item"); return }
        let image = try #require(image(fromPNG: png))
        // The shape alone, cropped to it: 60 × 84 pixels of the 300 × 420 card, opaque.
        #expect(abs(image.width - 60) <= 2 && abs(image.height - 84) <= 2)
        #expect(pixel(of: image, x: 30, y: 42)[3] == 255)
    }

    @Test func keepsTheItemsInTheLibraryAndKnowsTheFolderAgain() throws {
        try writeImageDeck(fiveItems, in: deckFolder)
        let library = try ArtLibrary(folder: folder.appendingPathComponent("Library"))
        let report = try library.add(deckFolder, keeping: false)
        #expect(report.added == 5 && library.entries.allSatisfy(\.isItem))
        #expect(library.contains(deckFolder.appendingPathComponent("Deck Fronts1.jpg")))
        #expect(library.picture(of: library.entries[0], maxPixels: 50) != nil)
        try FileManager.default.removeItem(at: deckFolder)
        library.refreshStatuses()
        // The items' pictures were kept, so they stay available without the folder.
        #expect(library.entries.allSatisfy(library.isAvailable))
    }

    @Test func readsTheTitleLinesInCapitalsTopToBottom() {
        let lines: [(text: String, box: CGRect)] = [
            ("ACID FLASK", CGRect(x: 0, y: 0.3, width: 1, height: 0.24)),
            ("LESSER", CGRect(x: 0, y: 0.55, width: 1, height: 0.25)),
            ("Though referred to as a flask", CGRect(x: 0, y: 0.05, width: 1, height: 0.17)),
            ("ITEM 1", CGRect(x: 0, y: 0.1, width: 1, height: 0.1))
        ]
        #expect(CardNameReader.name(in: lines) == "Lesser Acid Flask")
        #expect(CardNameReader.name(in: [("BLowgUn", CGRect(x: 0, y: 0, width: 1, height: 0.2))]) == "Blowgun")
        #expect(CardNameReader.name(in: []).isEmpty)
        #expect(CardNameReader.name(onFront: folder.appendingPathComponent("none.jpg")).isEmpty)
    }

    @Test func findsNothingInTooFewOrUnreadablePictures() throws {
        try writeImageDeck(["DAGGER", "LONGSWORD"], in: deckFolder)
        #expect(ImageDeck.containing(deckFolder) == nil)
        try Data("not a picture".utf8).write(to: deckFolder.appendingPathComponent("Deck Backs3.jpg"))
        try Data("not a picture".utf8).write(to: deckFolder.appendingPathComponent("Deck Backs1.jpg"))
        let deck = try #require(ImageDeck.containing(deckFolder))
        #expect(ImageDeckExtractor.extract(from: deck).pawns.isEmpty)
    }
}
