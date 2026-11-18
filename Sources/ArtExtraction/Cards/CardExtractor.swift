import CoreGraphics
import Foundation
import PDFKit

/// Finds the creatures in a deck of Battle Cards, or the items in an item deck. Each card's art side draws the
/// same background, frame and badges as every other card, then the card's own pictures, the creature or item
/// itself last, alone on a transparent background. Its stat side names it, and for a creature gives its size and
/// traits. Deck of Endless Treasure prints the art and the name on the same side.
enum CardExtractor {
    static func extract(from deck: CardDeck) throws -> ExtractionResult {
        guard let artText = PDFDocument(url: deck.artFile), let art = CGPDFDocument(deck.artFile as CFURL)
        else { throw PawnExtractionError.unreadable(deck.artFile.lastPathComponent) }
        let pairs: [CardPairing.Pair]
        let stats: PDFDocument
        if let statsFile = deck.statsFile {
            guard let statsText = PDFDocument(url: statsFile)
            else { throw PawnExtractionError.unreadable(statsFile.lastPathComponent) }
            stats = statsText
            pairs = CardPairing.pairs(artPages: artText.pageCount, statPages: statsText.pageCount)
        } else {
            stats = artText
            pairs = CardPairing.pairs(textless: (0..<artText.pageCount).map {
                printsLittleText(artText, $0, kind: deck.kind)
            })
        }
        return cards(in: pairs, of: deck.kind, art: art, stats: stats)
    }

    private static func cards(in pairs: [CardPairing.Pair], of kind: CardDeck.Kind, art: CGPDFDocument,
                              stats: PDFDocument) -> ExtractionResult {
        let pages = Dictionary(uniqueKeysWithValues: pairs.map { pair in
            (pair.art, ArtPage(art.page(at: pair.art + 1).map(PageScanner.images(on:)) ?? []))
        })
        let shared = ArtPage.sharedDigests(Array(pages.values))
        var result = ExtractionResult()
        for pair in pairs {
            guard let statsPage = stats.page(at: pair.stats), let card = read(statsPage, of: kind),
                  let page = pages[pair.art], let pawn = pawn(card, on: pair.art, page: page, shared: shared)
            else { continue }
            PawnExtractor.add(pawn, to: &result)
        }
        return result
    }

    /// The card a stat side describes. An item's name is looked for in the page's text as PDFKit gives it, and then
    /// in its lines from the top down: PDFKit gives a page's text in the order it was set since macOS 27, which
    /// puts the names of the Guns deck's cards last and a picture's placeholder before Deck of Endless Treasure's.
    private static func read(_ page: PDFPage, of kind: CardDeck.Kind) -> CardStats? {
        guard let text = page.string else { return nil }
        if let card = read(text, of: kind) { return card }
        return kind == .items ? read(linesFromTheTop(of: page), of: kind) : nil
    }

    /// The page's lines of text, the highest first and each row from the left, without pictures' placeholders.
    static func linesFromTheTop(of page: PDFPage) -> String {
        let lines = page.selection(for: page.bounds(for: .mediaBox))?.selectionsByLine() ?? []
        let placed = lines.compactMap { line -> (text: String, bounds: CGRect)? in
            let text = (line.string ?? "").replacingOccurrences(of: "\u{FFFC}", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : (text, line.bounds(for: page))
        }
        return placed.sorted { ($0.bounds.maxY, -$0.bounds.minX) > ($1.bounds.maxY, -$1.bounds.minX) }
            .map(\.text).joined(separator: "\n")
    }

    /// A creature card's stat side, or an item card's name as an item of medium size with no traits.
    private static func read(_ text: String, of kind: CardDeck.Kind) -> CardStats? {
        switch kind {
        case .creatures: CardStats.read(text)
        case .items: ItemCardText.name(in: text).map { CardStats(name: $0, size: .medium, traits: [], isItem: true) }
        }
    }

    /// The creature or item on an art page as a pawn; nil when the page draws no picture of its own.
    private static func pawn(_ card: CardStats, on pageIndex: Int, page: ArtPage,
                             shared: Set<String>) -> ExtractedPawn? {
        guard let index = page.creatureIndex(shared: shared), let figure = Figure(page.images[index]),
              let stream = page.images[index].stream
        else { return nil }
        let identity = EmbeddedImage.identity(of: stream)
        let face = PawnFace(pageIndex: pageIndex, rect: figure.bounds, rotation: 0)
        return ExtractedPawn(name: card.name, size: card.size, front: face, back: face.mirroredCopy(),
                             fingerprint: ArtFingerprint(imageDigests: [identity.digest],
                                                         thumbnail: identity.thumbnail),
                             copies: 1, shape: card.isItem ? .item(imageIndex: index) : .card(imageIndex: index),
                             traits: card.traits)
    }

    /// Art pages print no words, or only a credit such as "Illustration by Diana Martinez" (the NPC deck's
    /// combined PDF): little text, and no stat block or item name.
    static let artPageText = 80

    private static func printsLittleText(_ document: PDFDocument, _ index: Int, kind: CardDeck.Kind) -> Bool {
        let text = document.page(at: index)?.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.count < artPageText && read(text, of: kind) == nil
    }
}

/// The pictures a card's art side draws, with their digests.
struct ArtPage {
    let images: [ImagePlacement]
    /// Each image's digest; empty when its data can't be read.
    let digests: [String]

    init(_ images: [ImagePlacement]) {
        self.images = images
        digests = images.map { $0.stream.map(EmbeddedImage.digest(of:)) ?? "" }
    }

    /// The last picture drawn that is the card's own and transparent around its art: the creature.
    func creatureIndex(shared: Set<String>) -> Int? {
        images.indices.last { index in
            guard let stream = images[index].stream, !digests[index].isEmpty else { return false }
            return min(images[index].rect.width, images[index].rect.height) >= ArtFingerprint.smallestArt
                && EmbeddedImage.hasSoftMask(stream) && !shared.contains(digests[index])
        }
    }

    /// The pictures drawn on at least half the pages, and on three or more: the background, frame and badges
    /// every card shares, not a creature printed on a few cards.
    static func sharedDigests(_ pages: [ArtPage]) -> Set<String> {
        var counts: [String: Int] = [:]
        for page in pages {
            for digest in Set(page.digests) where !digest.isEmpty { counts[digest, default: 0] += 1 }
        }
        return Set(counts.filter { $0.value >= 3 && $0.value * 2 >= pages.count }.keys)
    }
}

/// Matches each card's art page with its stat page.
enum CardPairing {
    struct Pair: Equatable {
        /// Zero-based page indexes: of the art in the art PDF, and of the stat block in the stats PDF.
        let art: Int
        let stats: Int
    }

    /// Two-file decks print card n's back on page n of one PDF and its front on page n of the other.
    static func pairs(artPages: Int, statPages: Int) -> [Pair] {
        (0..<min(artPages, statPages)).map { Pair(art: $0, stats: $0) }
    }

    /// One-file decks print each card's art just before its stat block, or runs of stat blocks each followed by
    /// a run of the same cards' art, or, when hardly a page is free of words (Deck of Endless Treasure's two
    /// diagrams), each card's art beside its name on the same page. `textless` says which pages print no words:
    /// the art.
    static func pairs(textless: [Bool]) -> [Pair] {
        let artThenStats = textless.indices.dropLast().filter { textless[$0] && !textless[$0 + 1] }
        if artThenStats.count * 3 > textless.count {
            return artThenStats.map { Pair(art: $0, stats: $0 + 1) }
        }
        if textless.count { $0 } * 10 < textless.count {
            return textless.indices.map { Pair(art: $0, stats: $0) }
        }
        return runPairs(textless)
    }

    /// The k-th stat page of each run of stat pages with the k-th art page of the run of art pages after it.
    private static func runPairs(_ textless: [Bool]) -> [Pair] {
        var pairs: [Pair] = []
        var start = 0
        while start < textless.count {
            let statsEnd = textless[start...].firstIndex(of: true) ?? textless.count
            let artEnd = textless[statsEnd...].firstIndex(of: false) ?? textless.count
            let count = min(statsEnd - start, artEnd - statsEnd)
            pairs += (0..<count).map { Pair(art: statsEnd + $0, stats: start + $0) }
            start = max(artEnd, start + 1)
        }
        return pairs
    }
}
