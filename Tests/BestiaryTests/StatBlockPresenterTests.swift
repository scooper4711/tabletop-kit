import Foundation
import Testing
@testable import Bestiary

@Suite("Stat block presentation")
struct StatBlockPresenterTests {
    private var warrior: Creature {
        var creature = Creature(key: "k", name: "Warrior", game: .pathfinder)
        creature.level = 5
        creature.defenses = Defenses(armorClass: 22, fortitude: 12, reflex: 10, will: 8, hitPoints: 75)
        creature.attributes = AttributeModifiers(
            strength: 4, dexterity: 2, constitution: 3, intelligence: 0, wisdom: 1, charisma: 0
        )
        creature.strikes = [
            Strike(name: "maul", isRanged: false, attackBonus: 15,
                   traits: [], damage: [DamagePart(formula: "2d12+7", type: "bludgeoning")]),
            Strike(name: "dagger", isRanged: false, attackBonus: 14,
                   traits: ["finesse"], damage: [DamagePart(formula: "1d4", type: "piercing")])
        ]
        return creature
    }

    @Test("Elite raises statistics, HP and the first damage instance")
    func elite() {
        let elite = StatBlockPresenter(creature: warrior, template: .elite)
        #expect(elite.level == 6)
        #expect(elite.armorClass.value == 24)
        #expect(elite.maxHitPoints.value == 95)
        #expect(elite.damage(warrior.strikes[0]).map(\.formula) == ["2d12+9"])
    }

    @Test("Conditions show in the numbers with their sources")
    func conditions() {
        let conditions = [AppliedCondition(slug: "enfeebled", value: 2), AppliedCondition(slug: "off-guard")]
        let presenter = StatBlockPresenter(creature: warrior, template: .weak, conditions: conditions)
        #expect(presenter.armorClass.value == 18)
        #expect(presenter.armorClass.modifiers.map(\.label) == ["weak", "off-guard"])
        #expect(presenter.attack(warrior.strikes[0]).value == 11)
        #expect(presenter.damage(warrior.strikes[0]).map(\.formula) == ["2d12+3"])
        #expect(presenter.attribute(of: warrior.strikes[1]) == .strength)
    }

    @Test("Ability damage changes by 4 when limited; flat checks never change")
    func abilityText() {
        let elite = StatBlockPresenter(creature: warrior, template: .elite)
        let breath = [DamagePart(formula: "6d6", type: "fire")]
        #expect(elite.damage(breath, isLimited: true).map(\.formula) == ["6d6+4"])
        #expect(elite.check(CheckReference(statistic: "reflex", difficultyClass: 22)).value == 24)
        #expect(elite.check(CheckReference(statistic: "flat", difficultyClass: 5)).value == 5)
    }

    @Test("Weak damage can go negative on the constant; unparseable formulas are left alone")
    func formulas() {
        let weak = StatBlockPresenter(creature: warrior, template: .weak)
        #expect(weak.damage([DamagePart(formula: "1d4", type: "")], isLimited: false).map(\.formula) == ["1d4-2"])
        #expect(weak.damage([DamagePart(formula: "(@item.level)d6", type: "")], isLimited: false)
            .map(\.formula) == ["(@item.level)d6"])
    }
}
