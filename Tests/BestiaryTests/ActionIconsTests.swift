import Testing
@testable import Bestiary

@Suite("Action icons")
struct ActionIconsTests {
    @Test("Each cost has its Pathfinder-Icons code point and its stand-in symbols", arguments: [
        (ActionCost.one, "\u{E902}", "◆"), (.two, "\u{E901}", "◆◆"), (.three, "\u{E900}", "◆◆◆"),
        (.free, "\u{E903}", "◇"), (.reaction, "\u{E904}", "⤾"), (.none, "", "")
    ])
    func characters(cost: ActionCost, character: String, symbols: String) {
        #expect(ActionIcons.character(for: cost) == character)
        #expect(ActionIcons.symbols(for: cost) == symbols)
    }

    @Test("The font is named as its file says")
    func fontName() {
        #expect(ActionIcons.fontName == "Pathfinder-Icons")
        #expect(ActionIcons.fileName == "Pathfinder-Icons.ttf")
    }
}
