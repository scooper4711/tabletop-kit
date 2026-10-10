import Foundation
import Testing
@testable import ArtExtraction
import ArtExtractionTestSupport

/// Finding PDFs of art in a folder.
@Suite struct ProductScannerTests {
    @Test func findsPawnTokenAndBattleCardsPDFsEachDeckOnce() throws {
        let folder = temporaryFolder()
        let deck = folder.appendingPathComponent("Pathfinder Bestiary Battle Cards", isDirectory: true)
        try FileManager.default.createDirectory(at: deck, withIntermediateDirectories: true)
        for name in ["Pathfinder Test Pawn Box.pdf", "Alien Core Token Box.pdf", "Core Rulebook.pdf", "Notes.txt"] {
            try Data().write(to: folder.appendingPathComponent(name))
        }
        _ = try writeSplitDeck(threeCards, base: "PZO1 Bestiary Battle Cards", in: deck)
        let names = ProductScanner.artPDFs(in: folder).map(\.lastPathComponent)
        #expect(names == ["Alien Core Token Box.pdf", "Pathfinder Test Pawn Box.pdf",
                          "PZO1 Bestiary Battle Cards BACKS.pdf"])
    }
}
