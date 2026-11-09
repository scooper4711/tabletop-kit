import ArtExtraction
import ArtExtractionTestSupport
import CoreGraphics
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
    }

    static let monsters: [Monster] = [
        Monster("Goblin Warrior", -1, "CE SMALL GOBLIN HUMANOID"),
        Monster("Kobold Warrior", -1, "LE SMALL HUMANOID KOBOLD"),
        Monster("Skeleton Guard", -1, "NE MEDIUM MINDLESS SKELETON UNDEAD"),
        Monster("Zombie Shambler", -1, "NE MEDIUM UNDEAD"),
        Monster("Giant Rat", -1, "N SMALL ANIMAL"),
        Monster("Giant Centipede", -1, "N MEDIUM ANIMAL"),
        Monster("Wolf", 1, "N MEDIUM ANIMAL"),
        Monster("Hobgoblin Soldier", 1, "LE MEDIUM GOBLIN HUMANOID"),
        Monster("Ghoul", 1, "CE MEDIUM GHOUL UNDEAD"),
        Monster("Ogre Warrior", 3, "CE LARGE GIANT HUMANOID"),
        Monster("Owlbear", 4, "N LARGE ANIMAL"),
        Monster("Cave Bear", 6, "N LARGE ANIMAL")
    ]

    /// Outlined monster pawns, four columns of three, each with its name inside; front then mirrored back.
    static func pawnCollection() -> Data {
        let pawns = monsters.enumerated().map { index, monster in
            DemoPawn(rect: CGRect(x: 60 + CGFloat(index % 4) * 130, y: 460 - CGFloat(index / 4) * 200,
                                  width: 90, height: 170),
                     art: creatureArt(variant: index, scale: 4), name: monster.name)
        }
        return makePDF(pages: [{ context in pawns.forEach { $0.draw(context) } },
                               { context in pawns.forEach { $0.mirrored(pageWidth: letterPage.width).draw(context) } },
                               DemoNotice.draw])
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
                               DemoNotice.draw])
    }

    /// Round tokens of the monsters, their names along the rim.
    static func tokenSet() -> Data {
        let tokens = monsters.enumerated().map { index, monster in
            DrawnToken(center: CGPoint(x: 110 + CGFloat(index % 4) * 130, y: 640 - CGFloat(index / 4) * 150),
                       diameter: 110, art: tokenArt(variant: index), rimName: monster.name.uppercased())
        }
        return makePDF(pages: [{ context in tokens.forEach { $0.draw(context) } }, DemoNotice.draw])
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
        return makePDF(size: cardPage, pages: pages + [DemoNotice.drawSmall])
    }
}

/// The fine print under a demo pawn's name. Paizo's pawns carry their copyright there, and the art import takes a
/// "©" line beside a label as the sign of a pawn; this one claims nothing for Paizo.
let demoCopyright = "© 2026 TABLESIDE TOOLKIT DEMO"

/// An outlined pawn with its name inside, as Paizo's pawn boxes print them, with the demo's fine print.
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
        drawText(context, name, at: CGPoint(x: rect.minX + 6, y: rect.minY + 10), size: 8)
        drawText(context, demoCopyright, at: CGPoint(x: rect.minX + 6, y: rect.minY + 4), size: 4)
    }
}

/// A pawn printed without an outline, as Monster Core Pawn Box prints them: a transparent picture with its name and
/// the demo's fine print along its foot.
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
        drawText(context, demoCopyright, at: CGPoint(x: rect.minX + 4, y: rect.minY - 15), size: 4)
    }
}
