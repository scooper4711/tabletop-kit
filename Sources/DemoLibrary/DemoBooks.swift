import CoreGraphics
import Foundation

/// The adventure, society scenario and rulebook: lorem ipsum under headings, with pictures from the Community Use
/// Package and a creature's stat block, for Pluck to pull pictures and stat blocks from.
enum DemoBooks {
    static func adventure(_ art: DemoArt) -> Data {
        makeDemoPDF(pages: [
            { context in
                var page = ProsePage(context: context)
                page.heading("Chapter 1: Lorem Ipsum Road", size: 24)
                page.paragraph(seed: 1)
                page.picture(art.iconic(0).image, height: 300)
                page.paragraph(seed: 2)
            },
            { context in
                var page = ProsePage(context: context)
                page.heading("A1. The Ambush")
                page.paragraph(seed: 3)
                page.statBlock(name: "Goblin Warrior", level: -1, traits: "CE  SMALL  GOBLIN  HUMANOID",
                               entries: goblinEntries)
                page.paragraph(seed: 4)
            },
            { context in
                var page = ProsePage(context: context)
                page.heading("Handout: The Map Fragment")
                page.picture(art.iconic(1).image, height: 360)
                page.paragraph(seed: 5)
            },
            DemoNotice.draw
        ])
    }

    static func scenario(_ art: DemoArt) -> Data {
        makeDemoPDF(pages: [
            { context in
                var page = ProsePage(context: context)
                page.heading("Society Scenario: Dolor Sit Amet", size: 24)
                page.picture(art.symbols[0], height: 160)
                page.paragraph(seed: 11)
                page.paragraph(seed: 12)
            },
            { context in
                var page = ProsePage(context: context)
                page.heading("B1. The Crypt")
                page.paragraph(seed: 13)
                page.statBlock(name: "Skeleton Guard", level: -1, traits: "NE  MEDIUM  MINDLESS  SKELETON  UNDEAD",
                               entries: skeletonEntries)
                page.picture(art.iconic(2).image, height: 220)
            },
            DemoNotice.draw
        ])
    }

    static func rulebook(_ art: DemoArt) -> Data {
        makeDemoPDF(pages: [
            { context in
                var page = ProsePage(context: context)
                page.heading("Introduction", size: 24)
                page.paragraph(seed: 21)
                page.picture(art.iconic(3).image, height: 320)
                page.paragraph(seed: 22)
            },
            { context in
                var page = ProsePage(context: context)
                page.heading("Chapter 2: The Gods")
                page.paragraph(seed: 23)
                for symbol in art.symbols.prefix(3) { page.picture(symbol, height: 110) }
            },
            DemoNotice.draw
        ])
    }

    private static let goblinEntries = [
        ("Perception", "+2; darkvision"), ("Languages", "Common, Goblin"),
        ("Skills", "Acrobatics +5, Athletics +2, Stealth +5"), ("Str", "+0, Dex +3, Con +1, Int +0, Wis -1, Cha +1"),
        ("AC", "16; Fort +5, Ref +7, Will +3"), ("HP", "6"), ("Speed", "25 feet"),
        ("Melee", "dogslicer +7 (agile, finesse), Damage 1d6 slashing")
    ]

    private static let skeletonEntries = [
        ("Perception", "+2; darkvision"), ("Skills", "Acrobatics +6, Athletics +3"),
        ("Str", "+1, Dex +4, Con +0, Int -5, Wis +0, Cha +0"), ("AC", "16; Fort +2, Ref +8, Will +2"),
        ("HP", "4, negative healing"), ("Speed", "25 feet"),
        ("Melee", "scimitar +6 (forceful, sweep), Damage 1d6+1 slashing")
    ]
}
