import Testing
@testable import CreatureImport

@Suite("Roll formulas")
struct RollFormulaTests {
    private func resolved(_ formula: String, level: Int = 2) -> String {
        RollFormula.resolved(formula, values: .level(level))
    }

    @Test("A spell's rank is put in and the dice count worked out")
    func spellRank() {
        #expect(resolved("floor(@item.level/2)d6") == "1d6")
        #expect(resolved("(floor(@item.rank/2))d6") == "1d6")
        #expect(resolved("(@item.rank+1)d8", level: 3) == "4d8")
        #expect(resolved("(1+floor((@item.rank -1)/2))", level: 5) == "3")
        #expect(resolved("(ceil(@item.rank/2)*2)", level: 3) == "4")
    }

    @Test("Functions, comparisons and negation are worked out")
    func functions() {
        #expect(resolved("max(1,floor(@item.level/4))d4", level: 2) == "1d4")
        #expect(resolved("ternary(gte(@item.level,5),3,ternary(gte(@item.level,3),2,1))d6", level: 4) == "2d6")
        #expect(resolved("min(3,@item.level)+abs(-2)", level: 9) == "5")
        #expect(resolved("round(@item.level/4)+gt(@item.level,1)+lt(@item.level,1)+lte(1,1)+eq(2,2)") == "4")
        #expect(resolved("-@item.level") == "-2")
        #expect(resolved("@item.level/4") == "0.5")
    }

    @Test("Dice and unknown references stay; the parts around them are worked out")
    func partlyKnown() {
        #expect(resolved("2d8+(@item.level*1)") == "2d8+2")
        #expect(resolved("(1d4+@item.system.damage.dice)") == "(1d4+@item.system.damage.dice)")
        #expect(resolved("(@actor.level)d6") == "(@actor.level)d6")
        #expect(resolved("d20+@item.level") == "1d20+2")
        #expect(resolved("(2*@item.system.damage.dice)d6") == "(2*@item.system.damage.dice)d6")
    }

    @Test("Flavor tags are kept")
    func flavor() {
        #expect(resolved("(1*@item.level[splash])") == "(1*2[splash])")
        #expect(resolved("1d4[splash]") == "1d4[splash]")
    }

    @Test("Text that isn't a formula only gets its values written in")
    func unreadable() {
        #expect(resolved("@item.level fire") == "2 fire")
        #expect(resolved("floor(@item.level") == "floor(2")
        #expect(resolved("1/0") == "1/0")
        #expect(resolved("unknown(1)") == "unknown(1)")
        #expect(resolved("") == "")
    }

    @Test("References only known in play are named in words")
    func words() throws {
        let formula = try #require(RollFormula("1d4+@item.system.damage.dice"))
        #expect(formula.text(naming: FormulaValues.words) == "1d4 + the number of weapon damage dice")
        let doubled = try #require(RollFormula("2*@actor.abilities.str.mod"))
        #expect(doubled.text(naming: FormulaValues.words) == "2 × your Strength modifier")
        #expect(doubled.references == ["@actor.abilities.str.mod"])
    }
}

@Suite("Level wording")
struct LevelWordingTests {
    private func wording(_ formula: String) throws -> String {
        let parsed = try #require(RollFormula(formula))
        let wording = try #require(LevelWording.wording(parsed, values: FormulaValues()))
        return wording.text()
    }

    @Test("Numbers that follow the level are named")
    func levelWords() throws {
        #expect(try wording("@actor.level") == "your level")
        #expect(try wording("2*@actor.level") == "twice your level")
        #expect(try wording("floor(@actor.level/2)") == "half your level")
        #expect(try wording("ceil(@actor.level/2)") == "half your level (rounded up)")
    }

    @Test("A die a level reads per level")
    func perLevel() throws {
        #expect(try wording("(@actor.level)d6") == "1d6 per level")
    }

    @Test("Steady growth reads as the books write it")
    func regularGrowth() throws {
        #expect(try wording("(floor((@actor.level-1)/2)+1)d6")
            == "1d6 (increasing by 1d6 at 3rd level and every 2 levels after)")
        #expect(try wording("max(1,floor(@actor.level/2))")
            == "1 (increasing by 1 at 4th level and every 2 levels after)")
    }

    @Test("Irregular growth lists the values where they change")
    func listed() throws {
        #expect(try wording("ternary(gte(@actor.level,10),3,ternary(gte(@actor.level,5),2,1))d6")
            == "1d6 (2d6 at 5th level, 3d6 at 10th)")
        #expect(try wording("ternary(gte(@actor.level,21),2,1)") == "1")
    }

    @Test("A value that changes too often reads as the formula in words")
    func tooManyChanges() throws {
        let parsed = try #require(RollFormula("@actor.level+1d4"))
        #expect(LevelWording.wording(parsed, values: FormulaValues()) == nil)
        #expect(FormulaWording("@actor.level+1d4", values: FormulaValues()).text() == "your level + 1d4")
    }

    @Test("A worked-out formula says so")
    func workedOut() {
        #expect(FormulaWording("(@item.level)d6", values: .level(3))
            == FormulaWording(start: "3d6", isWorkedOut: true))
        #expect(FormulaWording("(@actor.level)d6", values: .level(3)).text(following: ["fire"]) == "1d6 fire per level")
    }

    @Test("Other references aren't described by level")
    func otherReferences() throws {
        let formula = try #require(RollFormula("@actor.level+@actor.abilities.str.mod"))
        #expect(LevelWording.wording(formula, values: FormulaValues()) == nil)
    }

    @Test("Ordinals")
    func ordinals() {
        #expect([1, 2, 3, 4, 11, 12, 13, 21, 22].map(LevelWording.ordinal)
            == ["1st", "2nd", "3rd", "4th", "11th", "12th", "13th", "21st", "22nd"])
    }
}
