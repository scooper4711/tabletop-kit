import Foundation
import Testing
@testable import Bestiary

@Suite("Immunities granted by traits")
struct TraitImmunitiesTests {
    private func creature(traits: [String], immunities: [String]) -> Creature {
        var creature = Creature(key: "test.creature", name: "Nodocite Experimenter", game: .starfinder)
        creature.traits = TraitLine(rarity: "uncommon", size: "Medium", traits: traits)
        creature.defenses.immunities = immunities
        return creature
    }

    @Test("A construct that lists only mental gets the construct's full set")
    func construct() {
        let immunities = creature(traits: ["construct", "robot", "tech"], immunities: ["mental"]).allImmunities
        #expect(immunities.first == "mental")
        #expect(immunities.count == 16)
        #expect(Set(immunities).isSuperset(of: ["death effects", "nonlethal attacks", "unconscious", "void"]))
    }

    @Test("Immunities the source lists aren't repeated, however they're written")
    func noDuplicates() {
        let listed = ["Death-Effects", "poison", "mental"]
        let immunities = TraitImmunities.merged(listed, traits: ["Construct", "mindless"])
        #expect(immunities.count == 16)
        #expect(Array(immunities.prefix(3)) == listed)
        #expect(!immunities.contains("death effects"))
    }

    @Test("Swarms and mindless creatures", arguments: [
        (["swarm", "animal"], ["grabbed", "prone", "restrained"]), (["mindless", "ooze"], ["mental"])
    ])
    func swarmAndMindless(traits: [String], expected: [String]) {
        #expect(creature(traits: traits, immunities: []).allImmunities == expected)
    }

    @Test("Undead and other traits grant nothing")
    func undead() {
        #expect(creature(traits: ["undead", "skeleton"], immunities: ["poison"]).allImmunities == ["poison"])
    }
}
