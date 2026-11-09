import Foundation

/// Writes the PDFs Scrollkeeper's demo library serves: lorem ipsum under real game terms, with drawn art and art from
/// Paizo's Community Use Package, in the layouts the Tableside Toolkit apps read. See `docs/specs/demo-library`.
public enum DemoLibrary {
    /// The files written, by name: Scrollkeeper's demo catalog names its editions' files the same way.
    public enum File: String, CaseIterable, Sendable {
        case pawnCollection = "pawn-collection.pdf"
        case heroPawns = "hero-pawns.pdf"
        case tokenSet = "token-set.pdf"
        case battleCards = "battle-cards.pdf"
        case forestMap = "map-forest.pdf"
        case starshipMap = "map-starship.pdf"
        case adventure = "adventure.pdf"
        case scenario = "scenario.pdf"
        case rulebook = "rulebook.pdf"
    }

    /// Writes every file into `folder`, with the Community Use Package's art from `communityUseFolder` when given.
    public static func write(to folder: URL, communityUseFolder: URL? = nil) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let art = DemoArt(communityUseFolder: communityUseFolder)
        for file in File.allCases {
            try data(of: file, art: art).write(to: folder.appendingPathComponent(file.rawValue))
        }
    }

    static func data(of file: File, art: DemoArt) -> Data {
        switch file {
        case .pawnCollection: DemoArtProducts.pawnCollection()
        case .heroPawns: DemoArtProducts.heroPawns(art)
        case .tokenSet: DemoArtProducts.tokenSet()
        case .battleCards: DemoArtProducts.battleCards()
        case .forestMap: DemoMaps.forest()
        case .starshipMap: DemoMaps.starshipDecks()
        case .adventure: DemoBooks.adventure(art)
        case .scenario: DemoBooks.scenario(art)
        case .rulebook: DemoBooks.rulebook(art)
        }
    }
}
