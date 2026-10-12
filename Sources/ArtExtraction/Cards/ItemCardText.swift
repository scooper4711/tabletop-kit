import Foundation

/// What an item card's text side says: the item's name. Paizo's item decks print it three ways: in capitals
/// before the item's level ("BEACON SHOT ITEM 3", or "DEADLY SPARK MINOR GIFT" for relics), in title case on
/// the first lines with no level (the Guns deck's "Knuckle Duster"), or in capitals on the first line (Deck of
/// Endless Treasure's "BATTLE AXE").
enum ItemCardText {
    /// Names that start the deck's own pages rather than a card's.
    private static let notItems = ["instructions", "deck", "product identity"]
    /// Lowercase words a title-case name may hold.
    private static let joiningWords: Set<String> = ["of", "the", "and", "&", "a", "an", "to", "in", "on", "for"]
    /// The most lines a name printed without its level runs to.
    private static let nameLines = 3

    /// The item's name in title case; nil for a page that names no item.
    static func name(in text: String) -> String? {
        let cleaned = CardStats.cleaned(text)
        let name = headerName(cleaned) ?? leadingName(cleaned)
        guard let name, !notItems.contains(where: name.lowercased().contains) else { return nil }
        return name
    }

    private static func headerName(_ text: String) -> String? {
        guard let header = text.range(of: #"\b(ITEM\s+\d+\+?|(MINOR|MAJOR|GRAND)\s+GIFT)\b"#,
                                      options: .regularExpression) else { return nil }
        return CardStats.name(before: header, in: text)?.0
    }

    /// The first lines while they look like a name: all in capitals, or else all in title case.
    private static func leadingName(_ text: String) -> String? {
        let lines = text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard let first = lines.first else { return nil }
        let inCapitals = isCapitals(first)
        let kept = lines.prefix(nameLines).prefix { inCapitals ? isCapitals($0) : isTitleCase($0) }
        guard !kept.isEmpty else { return nil }
        let words = kept.flatMap { $0.split(separator: " ").map(String.init) }
        return inCapitals ? PawnLabel.titleCase(words) : words.joined(separator: " ")
    }

    private static func isCapitals(_ line: String) -> Bool {
        line.contains(where: \.isLetter) && !line.contains(where: \.isLowercase) && !line.contains(where: \.isNumber)
    }

    /// Short, with every word capitalized but the joining ones (and not in capitals), and no sentence
    /// punctuation.
    private static func isTitleCase(_ line: String) -> Bool {
        let words = line.split(separator: " ")
        guard words.count <= 5, !line.contains(where: { ".:;,".contains($0) }), let first = words.first,
              isCapitalized(first) else { return false }
        return words.allSatisfy { isCapitalized($0) || joiningWords.contains(String($0)) }
    }

    private static func isCapitalized(_ word: Substring) -> Bool {
        word.first?.isUppercase == true && word.contains(where: \.isLowercase)
    }
}
