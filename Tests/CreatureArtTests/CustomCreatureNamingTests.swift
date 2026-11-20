import Bestiary
import SharedLibraries
import Testing
@testable import CreatureArt

/// A custom creature's row put over its stat block (shared libraries R4.4a, R4.7).
@Suite struct CustomCreatureNamingTests {
    let gremlin = Creature(key: "custom.1", name: "Gremlin", game: .pathfinder)

    @Test func putsTheRowsNameAndSizeOverTheStatBlocks() {
        let applied = gremlin.applying(name: "Grimple", size: .tiny)
        #expect(applied.name == "Grimple" && applied.traits.size == "Tiny")
    }

    @Test func keepsTheStatBlocksWhenTheRowHasNone() {
        #expect(gremlin.applying(name: "", size: nil) == gremlin)
    }
}
