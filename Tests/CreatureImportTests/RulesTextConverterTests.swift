import Bestiary
import Testing
@testable import CreatureImport

@Suite("Rules text conversion")
struct RulesTextConverterTests {
    private func convert(_ html: String) -> String {
        var converter = Fixtures.converter()
        return converter.convert(html).markup
    }

    @Test("Paragraphs, rules and emphasis become markup")
    func paragraphsAndEmphasis() {
        let html = "<p><strong>Trigger</strong> A goblin moves.</p>\n<hr />\n<p>It <em>Steps</em>.</p>"
        #expect(convert(html) == "**Trigger** A goblin moves.\n---\nIt *Steps*.")
    }

    @Test("A check keeps its statistic, DC and basic flag")
    func checkWithDC() {
        #expect(convert("@Check[reflex|dc:34|basic|options:area-effect]") == "{{check:reflex:34:basic}}")
        #expect(convert("@Check[type:will|dc:20]") == "{{check:will:20}}")
    }

    @Test("A check without a DC becomes prose")
    func checkWithoutDC() {
        #expect(convert("@Check[reflex|against:class|basic]") == "basic Reflex save against class DC")
        #expect(convert("@Check[athletics|defense:fortitude]") == "Athletics check against Fortitude DC")
        #expect(convert("@Check[thievery]{Disable it}") == "Disable it")
    }

    @Test("Damage with nested brackets, persistence and several parts")
    func damage() {
        #expect(convert("@Damage[(3d8+6)[piercing]]") == "{{damage:3d8+6|piercing}}")
        #expect(convert("@Damage[1d6[persistent,fire]]") == "{{damage:1d6|fire|persistent}}")
        #expect(convert("@Damage[2d6[bleed]|options:area-damage]") == "{{damage:2d6|bleed|persistent}}")
        #expect(convert("@Damage[2d6[fire],1d4[cold]]") == "{{damage:2d6|fire;1d4|cold}}")
    }

    @Test("Damage formulas are worked out from the values given")
    func damageFormulas() {
        var converter = Fixtures.converter()
        let grip = "plus @Damage[floor(@item.level/2)d6[persistent,acid]] damage"
        #expect(converter.convert(grip, values: .level(2)).markup == "plus {{damage:1d6|acid|persistent}} damage")
        #expect(converter.convert("[[/r (@item.rank+1)d4]]", values: .level(3)).markup == "4d4")
    }

    @Test("A formula only known in play prints its label, else words")
    func damageInPlay() {
        #expect(convert("@Damage[(@actor.level)d6|options:area-damage]{1d6 damage per level}")
            == "1d6 damage per level")
        #expect(convert("@Damage[(@actor.abilities.str.mod)[bludgeoning]]{bludgeoning}") == "bludgeoning")
        #expect(convert("@Damage[(@actor.abilities.str.mod)[bludgeoning]]")
            == "your Strength modifier bludgeoning")
        #expect(convert("@Damage[(floor((@actor.level-1)/2)+1)d6[fire]]")
            == "1d6 fire (increasing by 1d6 at 3rd level and every 2 levels after)")
        #expect(convert("@Damage[(1d4+@item.system.damage.dice)[persistent,fire]]")
            == "1d4 + the number of weapon damage dice persistent fire")
        #expect(convert("[[/r (@actor.level)d6]]") == "1d6 per level")
        #expect(convert("@Damage[9d6[@actor.flags.system.dragonDisciple.energyType]]") == "{{damage:9d6|}}")
        #expect(convert("[[/r 1d4+@actor.abilities.dex.mod]]") == "1d4 + your Dexterity modifier")
        #expect(convert("[[/r @item.level]]") == "@item.level")
    }

    @Test("Links, templates and inline rolls become words")
    func linksTemplatesAndRolls() {
        #expect(convert("@UUID[Compendium.pf2e.actionspf2e.Item.Step]{Steps}") == "Steps")
        #expect(convert("@UUID[Compendium.pf2e.conditionitems.Item.Frightened] 1") == "Frightened 1")
        #expect(convert("@UUID[Compendium.sf2e.bestiary-effects.Item.Effect: Lead the Charge]") == "")
        #expect(convert("@Template[cone|distance:40]") == "40-foot cone")
        #expect(convert("[[/gmr 1d4 #Recharge Breath]]{1d4 rounds}") == "1d4 rounds")
        #expect(convert("[[/act demoralize]]") == "Demoralize")
    }

    @Test("Localized glossary text is expanded and converted")
    func localization() {
        let html = "<p>@Localize[PF2E.NPC.Abilities.Glossary.ReactiveStrike]</p>"
        #expect(convert(html) == "**Trigger** A creature moves.")
    }

    @Test("Action glyph spans become action tokens")
    func actionGlyphs() {
        #expect(convert(#"<span class="action-glyph">2</span> Strike"#) == "{{actions:2}} Strike")
        #expect(convert(#"<span class="action-glyph">R</span>"#) == "{{actions:reaction}}")
    }

    @Test("Unknown enrichers keep their label and are reported")
    func unknownEnricher() {
        var converter = Fixtures.converter()
        #expect(converter.convert("@Mystery[thing]{the label}").markup == "the label")
        #expect(converter.unparsedEnrichers == ["Mystery"])
    }
}
