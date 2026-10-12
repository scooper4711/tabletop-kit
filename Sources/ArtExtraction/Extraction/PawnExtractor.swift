import CoreGraphics
import Foundation
import PDFKit

/// How a pawn is printed in its PDF.
public enum PrintedShape: Equatable, Sendable {
    /// A standing pawn in its cut outline.
    case pawn
    /// A round token, its faces being the squares around its art's circle, with its art drawn alone.
    case token(TokenPictures)
    /// A creature on a Battle Card: the picture drawn `imageIndex`th on its art page, cut to the face's rect.
    case card(imageIndex: Int)
    /// An item on an item deck's card, drawn as a creature on a Battle Card is.
    case item(imageIndex: Int)
    /// An item cut out of a card printed as a picture, as PNG: kept, since its card isn't a PDF.
    case drawnItem(Data)
}

/// A token's art drawn alone, as PNG: transparent outside the art and its circle.
public struct TokenPictures: Equatable, Sendable {
    public var front: Data
    /// Nil when the token has no back showing its art; the pawn's back is then the front mirrored.
    public var back: Data?

    public init(front: Data, back: Data? = nil) {
        self.front = front
        self.back = back
    }
}

/// A distinct pawn found in a PDF: one piece of art with one name, however many copies were printed.
public struct ExtractedPawn: Equatable, Sendable {
    /// Empty when no name is printed.
    public var name: String
    public var size: PawnSize
    public var front: PawnFace
    public var back: PawnFace
    public var fingerprint: ArtFingerprint
    /// How many copies the PDF prints.
    public var copies: Int
    public var shape: PrintedShape = .pawn
    /// The creature's traits, from its Battle Card (see `Pawn.traits`).
    public var traits: [String] = []
}

/// A cut outline with no name printed in it.
public struct UnnamedOutline: Equatable, Sendable {
    public let pageIndex: Int
    public let rect: CGRect
}

public struct ExtractionResult: Sendable {
    public var pawns: [ExtractedPawn] = []
    public var unnamed: [UnnamedOutline] = []
    /// Pages printed as one flattened picture with no text, whose pawns can't be told apart (zero-based).
    public var unreadablePages: [Int] = []
}

public enum PawnExtractionError: Error, Equatable, CustomStringConvertible {
    case unreadable(String)

    public var description: String {
        switch self {
        case .unreadable(let file): "Pawn extraction failed: \(file) could not be opened as a PDF"
        }
    }
}

/// Finds the pawns and round tokens in a Paizo pawn or token PDF, with their names, sizes and backs.
public enum PawnExtractor {
    /// Raised when extraction finds pawns it could not before, so that PDFs in which nothing was found are read
    /// again. 1: Battle Cards whose art pages credit the illustrator. 2: pawns printed without cut outlines.
    /// 3: item decks. 4: item decks printed as pictures.
    public static let version = 4

    /// The pawns in a pawn or token PDF, the creatures in a deck of Battle Cards, or the items in an item deck.
    public static func extract(from url: URL) throws -> ExtractionResult {
        if let deck = ImageDeck.containing(url) { return ImageDeckExtractor.extract(from: deck) }
        if let deck = CardDeck.containing(url) { return try CardExtractor.extract(from: deck) }
        guard let document = PDFDocument(url: url), let first = document.page(at: 0)?.pageRef,
              let cgDocument = first.document
        else { throw PawnExtractionError.unreadable(url.lastPathComponent) }
        return extract(from: cgDocument, labels: PDFKitLabelReader(document: document))
    }

    static func extract(from document: CGPDFDocument, labels: LabelReader) -> ExtractionResult {
        var result = ExtractionResult()
        let art = foundArt(in: document)
        for found in art.pawns {
            guard let size = PawnSize.classify(found.front.uprightSize) else { continue }
            let name = PawnLabel.name(from: labels.runs(onPage: found.front.pageIndex, in: found.front.rect))
            add(ExtractedPawn(name: name, size: size, front: found.front, back: found.back,
                              fingerprint: found.fingerprint, copies: 1), to: &result)
        }
        for token in art.tokens {
            if let pawn = token.extracted() { add(pawn, to: &result) }
        }
        for figure in art.figures {
            if let pawn = figure.extracted() { add(pawn, to: &result) }
        }
        result.unreadablePages = art.unreadablePages
        return result
    }

    /// A pawn's faces and art, before its label is read.
    struct FoundPawn {
        let front: PawnFace
        let back: PawnFace
        let fingerprint: ArtFingerprint
    }

    /// The pawns and tokens of a document, before their labels are read.
    struct FoundArt {
        var pawns: [FoundPawn] = []
        var tokens: [PairedToken] = []
        var figures: [PageFigure] = []
        var unreadablePages: [Int] = []
    }

    /// Every outlined pawn and round token, with its back from the mirrored page that follows, or else its front
    /// mirrored.
    static func foundArt(in document: CGPDFDocument) -> FoundArt {
        let pages = (0..<document.numberOfPages).map { index in
            var content = document.page(at: index + 1).map(PageScanner.scan) ?? PageContent()
            content.outlines = content.outlines.filter { $0.size != nil }
            return content
        }
        let tokens = pages.map(TokenFinder.tokens(on:))
        var found = FoundArt()
        found.unreadablePages = (0..<pages.count).filter { isFlattened(pages[$0], in: document, at: $0) }
        var pageIndex = 0
        while pageIndex < pages.count {
            let next = pageIndex + 1
            if pages[pageIndex].outlines.isEmpty, tokens[pageIndex].isEmpty {
                let figures = FigurePawns.figures(on: pages[pageIndex])
                if !figures.isEmpty {
                    found.figures += figures.map { PageFigure(found: $0, pageIndex: pageIndex) }
                    let backs = next < pages.count ? FigurePawns.figures(on: pages[next]) : []
                    pageIndex += FigurePawns.isBackPage(backs, of: figures) ? 2 : 1
                    continue
                }
            }
            let pawnBacks = PagePairing.backs(for: pages[pageIndex], among: next < pages.count ? pages[next] : .init())
            let tokenBacks = TokenPairing.backs(for: tokens[pageIndex], among: next < pages.count ? tokens[next] : [])
            found.pawns += outlinedPawns(on: pages[pageIndex], at: pageIndex, backs: pawnBacks)
            found.tokens += zip(tokens[pageIndex], tokenBacks ?? tokens[pageIndex].map { _ in nil }).map {
                PairedToken(front: $0, back: $1, pageIndex: pageIndex)
            }
            pageIndex += pawnBacks == nil && tokenBacks == nil ? 1 : 2
        }
        return found
    }

    /// True when a page after the first is one picture covering it, with no text or outlines: printed flattened.
    private static func isFlattened(_ page: PageContent, in document: CGPDFDocument, at index: Int) -> Bool {
        guard index > 0, page.glyphs.isEmpty, page.outlines.isEmpty, page.images.count == 1,
              let box = document.page(at: index + 1)?.getBoxRect(.mediaBox), box.width * box.height > 0
        else { return false }
        let image = page.images[0].rect.intersection(box)
        return image.width * image.height >= box.width * box.height * 0.9
    }

    /// The outlined pawns on a page, with their backs from the next page when `backs` has them.
    private static func outlinedPawns(on page: PageContent, at pageIndex: Int, backs: [Outline?]?) -> [FoundPawn] {
        zip(page.outlines, backs ?? page.outlines.map { _ in nil }).map { front, back in
            let frontFace = PawnFace(pageIndex: pageIndex, rect: front.rect, rotation: front.uprightRotation)
            let backFace = back.map { PawnFace(pageIndex: pageIndex + 1, rect: $0.rect, rotation: $0.uprightRotation) }
            return FoundPawn(front: frontFace, back: backFace ?? frontFace.mirroredCopy(),
                             fingerprint: page.art(inside: front.rect))
        }
    }

    /// Counts a copy when the same name, size and art is already listed; notes a pawn with no name.
    static func add(_ pawn: ExtractedPawn, to result: inout ExtractionResult) {
        if pawn.name.isEmpty {
            result.unnamed.append(UnnamedOutline(pageIndex: pawn.front.pageIndex, rect: pawn.front.rect))
        }
        if let index = result.pawns.firstIndex(where: {
            $0.name == pawn.name && $0.size == pawn.size && $0.fingerprint.matches(pawn.fingerprint)
        }) {
            result.pawns[index].copies += 1
        } else {
            result.pawns.append(pawn)
        }
    }
}

/// Matches the outlines of a front page with those of a back page printed mirror image for duplex.
enum PagePairing {
    static let tolerance: CGFloat = 3

    /// The back outline of each front, or nil when `candidates` is not the fronts' back page: at least half the
    /// fronts need a back where their mirror image falls that shows the same art. Pawn grids are symmetric, so
    /// a following page of other fronts lines up too; only the art tells them apart.
    static func backs(for fronts: PageContent, among candidates: PageContent) -> [Outline?]? {
        guard !fronts.outlines.isEmpty, let axis = mirrorAxis(fronts.outlines, candidates.outlines)
        else { return nil }
        let backs = fronts.outlines.map { front in candidates.outlines.first { isMirror($0, of: front, axis: axis) } }
        let agreeing = zip(fronts.outlines, backs).count { front, back in
            back.map { isBackArt(candidates.art(inside: $0.rect), of: fronts.art(inside: front.rect)) } ?? false
        }
        return agreeing * 2 >= fronts.outlines.count ? backs : nil
    }

    /// True when the back shows the front's art, or either has no raster art to compare.
    static func isBackArt(_ backArt: ArtFingerprint, of frontArt: ArtFingerprint) -> Bool {
        guard !frontArt.imageDigests.isEmpty, !backArt.imageDigests.isEmpty else { return true }
        return frontArt.matchesBack(backArt)
    }

    /// The most common sum of mirrored centers (twice the axis), over same-size outlines in the same row.
    static func mirrorAxis(_ fronts: [Outline], _ backs: [Outline]) -> CGFloat? {
        var sums: [CGFloat] = []
        for front in fronts {
            for back in backs where back.size == front.size && abs(back.rect.minY - front.rect.minY) < tolerance {
                sums.append(front.rect.midX + back.rect.midX)
            }
        }
        return sums.max { first, second in
            sums.count { abs($0 - first) < tolerance } < sums.count { abs($0 - second) < tolerance }
        }
    }

    static func isMirror(_ back: Outline, of front: Outline, axis: CGFloat) -> Bool {
        back.size == front.size && abs(back.rect.minY - front.rect.minY) < tolerance
            && abs(axis - front.rect.midX - back.rect.midX) < tolerance
    }
}

extension PageContent {
    /// The fingerprint of the art drawn inside `rect`.
    func art(inside rect: CGRect) -> ArtFingerprint {
        ArtFingerprint(images: images, inside: rect)
    }
}

/// A pawn printed without a cut outline, on its page.
struct PageFigure {
    let found: FigurePawns.Found
    let pageIndex: Int

    /// Longer labels are blurbs beside a cover's art, not names.
    static let longestName = 60

    /// The pawn, its picture drawn alone like a Battle Card's creature, named from its label; nil when its label
    /// gives no name (a cover's art) or its picture can't be decoded. Its back is its front mirrored, as the back
    /// page prints it.
    func extracted() -> ExtractedPawn? {
        let name = PawnLabel.name(from: found.label)
        guard !name.isEmpty, name.count <= Self.longestName, let figure = Figure(found.image) else { return nil }
        let face = PawnFace(pageIndex: pageIndex, rect: figure.bounds, rotation: found.rotation)
        let identity = found.image.identity
        return ExtractedPawn(name: name, size: found.size, front: face, back: face.mirroredCopy(),
                             fingerprint: ArtFingerprint(imageDigests: [identity.digest],
                                                         thumbnail: identity.thumbnail),
                             copies: 1, shape: .card(imageIndex: found.imageIndex))
    }
}
