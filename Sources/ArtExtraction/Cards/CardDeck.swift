import Foundation

/// A deck of Paizo cards with art: Battle Cards (creatures) or an item deck (Potions & Talismans, Guns, Deck of
/// Endless Treasure, …). One PDF holds both sides of every card, or a pair of PDFs holds one with the fronts
/// (stat blocks) and one with the backs (art).
public struct CardDeck: Equatable, Sendable {
    /// What a deck's cards show.
    public enum Kind: Sendable {
        case creatures, items
    }

    /// The PDF with the art, which the library keeps.
    public let artFile: URL
    /// The PDF with the stat blocks when the deck comes as two; nil when `artFile` holds both sides.
    public let statsFile: URL?
    public var kind: Kind = .creatures

    /// Matches the word naming a side in a two-file deck: "… FRONT.pdf", "… FRONTS.pdf", "… BACKS.pdf".
    private static let sideWord = #"(?i)\b(FRONT|BACK)S?\b"#

    /// Words naming decks without art of their own: spells, conditions, rules and the like.
    private static let decksWithoutArt = ["spell", "condition", "npc", "hero point", "harrow", "chase", "critical",
                                          "rules", "reference", "character", "many worlds", "starship"]

    /// The deck `url` belongs to, or nil when it isn't a deck with art: its name, or the folders it is in, must
    /// say "Battle Cards", or name an item deck ("Pathfinder Guns Deck"). Either PDF of a two-file deck gives
    /// the whole deck.
    public static func containing(_ url: URL) -> CardDeck? {
        let names = [url.lastPathComponent] + url.deletingLastPathComponent().pathComponents.suffix(2)
        let kind: Kind
        if names.contains(where: isBattleCards) {
            kind = .creatures
        } else if names.contains(where: isItemDeck) {
            kind = .items
        } else {
            return nil
        }
        guard let side = side(of: url), let partner = partner(of: url) else {
            return CardDeck(artFile: url, statsFile: nil, kind: kind)
        }
        return side == "BACK" ? CardDeck(artFile: url, statsFile: partner, kind: kind)
                              : CardDeck(artFile: partner, statsFile: url, kind: kind)
    }

    /// The deck's product name: from the folder Scrollkeeper keeps it in, when there is one ("Starfinder Alien
    /// Archive 1 & 2 Battle Cards"), or else from the file name without its side and reference code.
    public var title: String {
        let folders = artFile.deletingLastPathComponent().pathComponents.suffix(2).reversed()
        let named = folders.map(Self.withoutDownloadWords).filter { Self.isBattleCards($0) || Self.isItemDeck($0) }
        if let product = named.first(where: { $0.hasPrefix("Pathfinder") || $0.hasPrefix("Starfinder") }) {
            return product
        }
        var title = (artFile.lastPathComponent as NSString).deletingPathExtension
        title = title.replacingOccurrences(of: Self.sideWord, with: "", options: .regularExpression)
        return Self.withoutDownloadWords(ProductTitle.fromFileName(title + ".pdf"))
    }

    private static func isBattleCards(_ name: String) -> Bool {
        name.range(of: #"battle ?cards?"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    static func isItemDeck(_ name: String) -> Bool {
        let lowercased = name.lowercased()
        return lowercased.range(of: #"\bdeck\b"#, options: .regularExpression) != nil
            && !decksWithoutArt.contains(where: lowercased.contains)
    }

    /// The name without the words Paizo's downloads add: "… Battle Cards (Download) - PDFs" becomes
    /// "… Battle Cards".
    private static func withoutDownloadWords(_ name: String) -> String {
        name.replacingOccurrences(of: #"(\s*\(Download\))?(\s*[-:]\s*PDFs?)?\s*[-:]?$"#, with: "",
                                  options: [.regularExpression, .caseInsensitive])
            .trimmingCharacters(in: .whitespaces)
    }

    /// "FRONT" or "BACK" when the file name names a side, else nil.
    private static func side(of url: URL) -> String? {
        let name = url.lastPathComponent
        return name.range(of: sideWord, options: .regularExpression).map { name[$0].uppercased() }
            .map { $0.hasPrefix("FRONT") ? "FRONT" : "BACK" }
    }

    /// The PDF beside `url` whose name differs only in naming the other side, or else the only PDF beside it
    /// naming the other side ("Relic Deck Fronts.pdf" and "Relics Deck Backs.pdf").
    private static func partner(of url: URL) -> URL? {
        let folder = url.deletingLastPathComponent()
        let others = ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).filter { name in
            name.lowercased().hasSuffix(".pdf") && side(of: URL(fileURLWithPath: name)).map { $0 != side(of: url) }
                == true
        }
        let key = sideless(url.lastPathComponent)
        let partner = others.first { sideless($0) == key } ?? (others.count == 1 ? others.first : nil)
        return partner.map { folder.appendingPathComponent($0) }
    }

    private static func sideless(_ name: String) -> String {
        name.replacingOccurrences(of: sideWord, with: "", options: .regularExpression).lowercased()
    }
}
