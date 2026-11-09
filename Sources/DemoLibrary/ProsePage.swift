import CoreGraphics
import CoreText
import Foundation

/// Lays out a letter page from the top down: headings, paragraphs, pictures and stat blocks, in the fonts and
/// weights Paizo's books use, so Pluck reads headings, paragraphs and stat blocks from them.
struct ProsePage {
    static let size = CGSize(width: 612, height: 792)
    private static let margin: CGFloat = 60
    private static let width = size.width - 2 * margin

    private let context: CGContext
    /// The top of the space left on the page.
    private var top = size.height - margin

    init(context: CGContext) {
        self.context = context
    }

    mutating func heading(_ text: String, size: CGFloat = 20) {
        top -= draw(text, font: "Helvetica-Bold", size: size, in: CGRect(x: Self.margin, y: 0, width: Self.width,
                                                                       height: top))
        top -= 8
    }

    mutating func paragraph(seed: Int) {
        top -= draw(Lorem.paragraph(seed: seed), font: "Times-Roman", size: 10,
                    in: CGRect(x: Self.margin, y: 0, width: Self.width, height: top))
        top -= 8
    }

    /// A picture centered across the text, at most `height` tall.
    mutating func picture(_ image: CGImage, height: CGFloat) {
        let scale = min(height / CGFloat(image.height), Self.width / CGFloat(image.width))
        let size = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
        context.draw(image, in: CGRect(x: (Self.size.width - size.width) / 2, y: top - size.height,
                                       width: size.width, height: size.height))
        top -= size.height + 12
    }

    /// A creature's stat block: its name with "CREATURE <level>" on the same line, its traits, then entries that
    /// each start with a bold label.
    mutating func statBlock(name: String, level: Int, traits: String, entries: [(label: String, text: String)]) {
        let left = Self.margin
        draw(name.uppercased(), font: "Helvetica-Bold", size: 12, in: CGRect(x: left, y: 0, width: 300, height: top))
        let levelLabel = "CREATURE \(level)"
        draw(levelLabel, font: "Helvetica-Bold", size: 12,
             in: CGRect(x: left + Self.width - 110, y: 0, width: 110, height: top))
        top -= 18
        top -= draw(traits, font: "Helvetica-Bold", size: 8, in: CGRect(x: left, y: 0, width: Self.width, height: top))
        top -= 4
        for entry in entries {
            let labelWidth = draw(entry.label, font: "Helvetica-Bold", size: 9,
                                  in: CGRect(x: left, y: 0, width: 120, height: top), measuringWidth: true)
            top -= draw(entry.text, font: "Helvetica", size: 9,
                        in: CGRect(x: left + labelWidth + 4, y: 0, width: Self.width - labelWidth - 4, height: top))
            top -= 2
        }
        top -= 10
    }

    /// Draws `text` wrapped into `frame` from its top, and returns the height it took, or with `measuringWidth`
    /// the width of its first line.
    @discardableResult
    private func draw(_ text: String, font name: String, size: CGFloat, in frame: CGRect,
                      measuringWidth: Bool = false) -> CGFloat {
        let font = CTFontCreateWithName(name as CFString, size, nil)
        let string = NSAttributedString(string: text, attributes: [.init(kCTFontAttributeName as String): font])
        let framesetter = CTFramesetterCreateWithAttributedString(string)
        let fitted = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter, CFRange(), nil, CGSize(width: frame.width, height: .greatestFiniteMagnitude), nil)
        let box = CGRect(x: frame.minX, y: frame.maxY - fitted.height, width: frame.width, height: fitted.height)
        CTFrameDraw(CTFramesetterCreateFrame(framesetter, CFRange(), CGPath(rect: box, transform: nil), nil), context)
        if measuringWidth {
            let line = CTLineCreateWithAttributedString(string)
            return CTLineGetTypographicBounds(line, nil, nil, nil)
        }
        return fitted.height
    }
}

/// The last page of every demo PDF: what the file is, and Paizo's Community Use notice.
enum DemoNotice {
    /// What a demo file holds, which its notice describes.
    enum Content {
        /// Lorem ipsum under headings: the rulebook, adventure and scenario.
        case placeholderProse
        /// Pawns of Paizo's Iconics, from the Community Use Package.
        case iconicPawns
        /// Pawns, tokens or Battle Cards whose art was drawn for the demo, under real creatures' names.
        case drawnCreatures
        /// Battle maps drawn for the demo.
        case drawnMaps

        var sentence: String {
            switch self {
            case .placeholderProse: "Its text is placeholder lorem ipsum; it is not a Paizo product."
            case .iconicPawns:
                "These are pawns of Paizo's Iconic characters. Their names and images come from Paizo's Community "
                    + "Use Package and are used under the Community Use Policy. It is not a Paizo product."
            case .drawnCreatures:
                "Its art was drawn for the demo, under the names of real creatures; it is not a Paizo product."
            case .drawnMaps: "Its maps were drawn for the demo; it is not a Paizo product."
            }
        }
    }

    static let lead = "This file is from Scrollkeeper's demo library, made for trying the Tableside Toolkit apps."
    static let communityUse = """
        The Tableside Toolkit uses trademarks and/or copyrights owned by Paizo Inc., used under Paizo's Community \
        Use Policy (paizo.com/licenses/communityuse). We are expressly prohibited from charging you to use or \
        access this content. The Tableside Toolkit is not published, endorsed, or specifically approved by Paizo. \
        For more information about Paizo Inc. and Paizo products, visit paizo.com.
        """

    /// The notice for a file holding `content`.
    static func text(for content: Content) -> String {
        "\(lead) \(content.sentence)\n\n\(communityUse)"
    }

    /// The notice on a letter page.
    static func page(_ content: Content) -> (CGContext) -> Void {
        { context in
            drawText(text(for: content), in: CGRect(x: 72, y: 72, width: 468, height: 648), size: 11,
                     context: context)
        }
    }

    /// The notice on a card-sized page.
    static func smallPage(_ content: Content) -> (CGContext) -> Void {
        { context in
            drawText(text(for: content), in: CGRect(x: 16, y: 16, width: 257, height: 393), size: 8,
                     context: context)
        }
    }

    private static func drawText(_ text: String, in frame: CGRect, size: CGFloat, context: CGContext) {
        let font = CTFontCreateWithName("Helvetica" as CFString, size, nil)
        let string = NSAttributedString(string: text, attributes: [.init(kCTFontAttributeName as String): font])
        let framesetter = CTFramesetterCreateWithAttributedString(string)
        let ctFrame = CTFramesetterCreateFrame(framesetter, CFRange(), CGPath(rect: frame, transform: nil), nil)
        CTFrameDraw(ctFrame, context)
    }
}

/// Placeholder text that reads like prose, chosen by a seed so the same seed gives the same words every time.
enum Lorem {
    private static let words = """
        lorem ipsum dolor sit amet consectetur adipiscing elit sed do eiusmod tempor incididunt ut labore et dolore \
        magna aliqua enim ad minim veniam quis nostrud exercitation ullamco laboris nisi aliquip ex ea commodo \
        consequat duis aute irure in reprehenderit voluptate velit esse cillum fugiat nulla pariatur excepteur sint \
        occaecat cupidatat non proident sunt culpa qui officia deserunt mollit anim id est laborum
        """.split(separator: " ").map(String.init)

    /// A sentence of six to fourteen words.
    static func sentence(seed: Int) -> String {
        let count = 6 + seed % 9
        let text = (0..<count).map { words[(seed * 7 + $0 * 13) % words.count] }.joined(separator: " ")
        return text.prefix(1).uppercased() + text.dropFirst() + "."
    }

    /// A paragraph of three to six sentences.
    static func paragraph(seed: Int) -> String {
        (0..<(3 + seed % 4)).map { sentence(seed: seed * 5 + $0) }.joined(separator: " ")
    }
}
