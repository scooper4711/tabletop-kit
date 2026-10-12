import Foundation

/// An item deck sold as JPGs, one per card face (Weapons & Armor): a folder of `…Fronts<n>.jpg`, naming each
/// item, and `…Backs<n>.jpg`, painting it on a background every back shares.
public struct ImageDeck: Equatable, Sendable {
    /// One card: its number, its back and, when there is one, its front.
    struct Card: Equatable, Sendable {
        let number: Int
        let back: URL
        let front: URL?
    }

    /// Decks need this many backs for their shared background to tell from the items.
    static let fewestCards = 3

    public let folder: URL
    let cards: [Card]

    /// The deck in the folder `url` is, or is in; nil unless the folder, or the one it is in, names an item deck
    /// and the folder holds enough backs.
    public static func containing(_ url: URL) -> ImageDeck? {
        let folder = isFolder(url) ? url : url.deletingLastPathComponent()
        let names = Array(folder.pathComponents.suffix(2))
        guard names.contains(where: CardDeck.isItemDeck),
              let files = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return nil }
        let numberedFronts = files.compactMap { name in number(of: name, side: "Fronts").map { ($0, name) } }
        let fronts = Dictionary(numberedFronts) { first, _ in first }
        let cards = files.compactMap { name in number(of: name, side: "Backs").map { ($0, name) } }
            .sorted { $0.0 < $1.0 }
            .map { Card(number: $0.0, back: folder.appendingPathComponent($0.1),
                        front: fronts[$0.0].map(folder.appendingPathComponent)) }
        return cards.count >= fewestCards ? ImageDeck(folder: folder, cards: cards) : nil
    }

    /// The deck's product name, from the folder Scrollkeeper keeps it in when there is one.
    public var title: String {
        let deck = CardDeck(artFile: folder.appendingPathComponent("deck.pdf"), statsFile: nil, kind: .items)
        return deck.title.replacingOccurrences(of: #"^deck$"#, with: folder.lastPathComponent,
                                               options: .regularExpression)
    }

    /// The card number in a face's file name: 12 in "PZO2209 Armor and Weapon Cards Backs12.jpg".
    private static func number(of name: String, side: String) -> Int? {
        guard let range = name.range(of: side + #"\s*(\d+)\.jpe?g$"#, options: [.regularExpression, .caseInsensitive])
        else { return nil }
        return Int(name[range].filter(\.isNumber))
    }

    private static func isFolder(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}
