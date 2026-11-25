@testable import SourceAttribution
import Testing

struct SourceTallyTests {
    @Test func spellingsOfOneTitleAddUpUnderTheFirst() {
        var tally = SourceTally()
        tally.add(" Pathfinder Treasure Vault (Remastered)", count: 3)
        tally.add("Pathfinder Treasure Vault (Remastered)")
        #expect(tally.sources == [.init(title: "Pathfinder Treasure Vault (Remastered)", count: 4)])
    }

    @Test func sourcesSortTheWayFinderDoes() {
        #expect(tally("Pathfinder #210: B", "Pathfinder #99: A").sources.map(\.title)
            == ["Pathfinder #99: A", "Pathfinder #210: B"])
    }

    @Test func textRoundTrips() throws {
        let text = "Monster Core\t12\nTech Core\t3\n"
        #expect(try SourceTally(text: text).text == text)
    }

    @Test func aLineWithoutACountIsRefusedWithItsNumber() {
        #expect(throws: AttributionError.malformedTally(line: 2, "Tech Core")) {
            try SourceTally(text: "Monster Core\t12\nTech Core\n")
        }
    }
}
