import ArtExtraction
import ArtExtractionTestSupport
import CoreGraphics
import CoreText
import Foundation

/// The pawn, token and Battle Cards products, drawn as Paizo prints them so the toolkit's art import reads them.
enum DemoArtProducts {
    /// A real bestiary creature, so Turnkeeper and Field Guide match the art to it.
    struct Monster {
        let name: String
        let level: Int
        let traits: String

        init(_ name: String, _ level: Int, _ traits: String) {
            self.name = name
            self.level = level
            self.traits = traits
        }

        /// The pawn size its size trait calls for, whose outline Paizo prints.
        var size: PawnSize {
            if traits.contains("SMALL") { return .small }
            return traits.contains("LARGE") ? .large : .medium
        }
    }

    static let monsters: [Monster] = [
        Monster("Goblin Warrior", -1, "CE SMALL GOBLIN HUMANOID"),
        Monster("Kobold Warrior", -1, "LE SMALL HUMANOID KOBOLD"),
        Monster("Skeleton Guard", -1, "NE MEDIUM MINDLESS SKELETON UNDEAD"),
        Monster("Zombie Shambler", -1, "NE MEDIUM UNDEAD"),
        Monster("Giant Rat", -1, "N SMALL ANIMAL"),
        Monster("Giant Centipede", -1, "N MEDIUM ANIMAL"),
        Monster("Wolf", 1, "N MEDIUM ANIMAL"),
        Monster("Aapoph Serpentfolk", 3, "CE MEDIUM HUMANOID MUTANT SERPENTFOLK"),
        Monster("Ghoul", 1, "CE MEDIUM GHOUL UNDEAD"),
        Monster("Ogre Warrior", 3, "CE LARGE GIANT HUMANOID"),
        Monster("Owlbear", 4, "N LARGE ANIMAL"),
        Monster("Cave Bear", 6, "N LARGE ANIMAL")
    ]

    /// Outlined monster pawns, four columns of three, each with its name inside; front then mirrored back.
    static func pawnCollection() -> Data {
        let pawns = monsters.enumerated().map { index, monster in
            DemoPawn(rect: CGRect(origin: CGPoint(x: 30 + CGFloat(index % 4) * 145, y: 520 - CGFloat(index / 4) * 230),
                                  size: monster.size.outlineSize),
                     art: creatureArt(variant: index, scale: 4), name: monster.name)
        }
        return makePDF(pages: [{ context in pawns.forEach { $0.draw(context) } },
                               { context in pawns.forEach { $0.mirrored(pageWidth: letterPage.width).draw(context) } },
                               DemoNotice.page(.drawnCreatures)])
    }

    /// The Iconics as pawns printed without outlines, named along their feet; front then mirrored back.
    static func heroPawns(_ art: DemoArt) -> Data {
        let heroes = (0..<min(8, art.iconics.count)).map { index in
            DemoFigurePawn(rect: CGRect(x: 50 + CGFloat(index % 4) * 135, y: 450 - CGFloat(index / 4) * 230,
                                        width: 100, height: 165),
                           art: art.iconic(index).image, name: art.iconic(index).name)
        }
        return makePDF(pages: [{ context in heroes.forEach { $0.draw(context) } },
                               { context in
                                   heroes.forEach { $0.mirrored(pageWidth: letterPage.width).draw(context) }
                               },
                               DemoNotice.page(.iconicPawns)])
    }

    /// Round tokens of the monsters, their names along the rim.
    static func tokenSet() -> Data {
        let tokens = monsters.enumerated().map { index, monster in
            DrawnToken(center: CGPoint(x: 110 + CGFloat(index % 4) * 130, y: 640 - CGFloat(index / 4) * 150),
                       diameter: 110, art: tokenArt(variant: index), rimName: monster.name.uppercased())
        }
        return makePDF(pages: [{ context in tokens.forEach { $0.draw(context) } },
                               DemoNotice.page(.drawnCreatures)])
    }

    /// The monsters as a Battle Cards deck: each card's art side, then its stat side.
    static func battleCards() -> Data {
        let cards = monsters.enumerated().map { index, monster in
            // Battle Cards print their creatures' names in capitals, and the card reader looks for them so.
            DrawnCard(name: monster.name.uppercased(), traits: monster.traits,
                      creature: creatureArt(variant: index, scale: 4), heading: "CREATURE \(monster.level)")
        }
        let pages: [(CGContext) -> Void] = cards.flatMap { card -> [(CGContext) -> Void] in
            [{ card.drawArt($0) }, { card.drawStats($0) }]
        }
        return makePDF(size: cardPage, pages: pages + [DemoNotice.smallPage(.drawnCreatures)])
    }
}

/// An outlined pawn with its name inside, at one of Paizo's outline sizes, as Paizo's pawn boxes print them.
struct DemoPawn {
    var rect: CGRect
    var art: CGImage
    var name: String
    var head = Edge.top

    func mirrored(pageWidth: CGFloat) -> DemoPawn {
        var back = self
        back.rect.origin.x = pageWidth - rect.maxX
        return back
    }

    func draw(_ context: CGContext) {
        context.draw(art, in: rect.insetBy(dx: 4, dy: 20))
        strokeOutline(context, rect, head: head)
        drawText(context, name, at: CGPoint(x: rect.minX + 6, y: rect.minY + 10),
                 size: Self.fittedSize(of: name, within: rect.width - 12))
    }

    /// 8 points, or smaller when the name would run past the outline, as Paizo sets long names on small pawns.
    static func fittedSize(of name: String, within width: CGFloat) -> CGFloat {
        let font = CTFontCreateWithName("Helvetica-Bold" as CFString, 8, nil)
        let line = CTLineCreateWithAttributedString(
            NSAttributedString(string: name, attributes: [.init(kCTFontAttributeName as String): font]))
        let natural = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        return natural > width ? 8 * width / natural : 8
    }
}

/// A pawn printed without an outline, as Monster Core Pawn Box prints them: a transparent picture with its name
/// along its foot.
struct DemoFigurePawn {
    var rect: CGRect
    var art: CGImage
    var name: String

    func mirrored(pageWidth: CGFloat) -> DemoFigurePawn {
        var back = self
        back.rect.origin.x = pageWidth - rect.maxX
        return back
    }

    func draw(_ context: CGContext) {
        context.draw(art, in: rect)
        drawText(context, name, at: CGPoint(x: rect.minX + 4, y: rect.minY - 9), size: 8)
    }
}
