import Foundation

/// Describes a formula on the character's level the way the books do, by working it out for every level from the
/// entry's own (`@item.level`, as a 12th-level feat is only taken from 12th level) to 20th:
/// "your level", "half your level", "1d6 per level", "1d6, increasing by 1d6 at 3rd level and every 2 levels
/// after", or the values where they change, "1d6 (2d6 at 5th level, 3d6 at 10th)".
struct LevelWording {
    static let reference = "@actor.level"
    static let highestLevel = 20

    /// The wording, or nil when the formula refers to something besides the level.
    static func wording(_ formula: RollFormula, values: FormulaValues) -> FormulaWording? {
        let folded = formula.folded(values)
        guard folded.references == [reference] else { return nil }
        let first = min(max(Int(values["@item.level"] ?? 1), 1), highestLevel)
        let steps = (first...highestLevel).map { level in
            var known = values
            known.values[reference] = Double(level)
            return Step(level: level, formula.folded(known))
        }
        return wording(steps)
    }

    /// Lists of more changes than this read worse than the formula in words.
    static let listedChanges = 5

    private static func wording(_ steps: [Step]) -> FormulaWording? {
        if let words = levelWords(steps) { return FormulaWording(start: words) }
        if let perLevel = perLevel(steps) { return FormulaWording(start: perLevel, ending: "per level") }
        let changes = changes(in: steps)
        if let regular = regularGrowth(changes, steps: steps) { return regular }
        guard changes.count <= listedChanges else { return nil }
        let listed = changes.enumerated().map { index, step in
            "\(step.text) at \(ordinal(step.level))" + (index == 0 ? " level" : "")
        }
        return FormulaWording(start: steps[0].text, growth: listed.isEmpty ? nil : listed.joined(separator: ", "))
    }

    /// "your level", "twice your level", "half your level" for a number that follows the level.
    private static func levelWords(_ steps: [Step]) -> String? {
        guard steps.allSatisfy({ $0.number != nil }) else { return nil }
        let candidates: [(String, (Double) -> Double)] = [
            ("your level", { $0 }),
            ("twice your level", { $0 * 2 }),
            ("half your level", { ($0 / 2).rounded(.down) }),
            ("half your level (rounded up)", { ($0 / 2).rounded(.up) })
        ]
        return candidates.first { _, rule in steps.allSatisfy { rule(Double($0.level)) == $0.number } }?.0
    }

    /// "1d6" (per level) for dice that gain one die a level.
    private static func perLevel(_ steps: [Step]) -> String? {
        guard let sides = steps[0].amount?.sides,
              steps.allSatisfy({ $0.amount == Amount(dice: Double($0.level), sides: sides, bonus: 0) })
        else { return nil }
        return "1d\(RollFormula.numberText(sides))"
    }

    /// "1d6, increasing by 1d6 at 3rd level and every 2 levels after" for a value that grows by the same
    /// amount at a steady interval, at least twice, through 20th level. Dice and a bonus can grow together:
    /// "1d4+1, increasing by 1d4+5 at 3rd level and every 2 levels after".
    private static func regularGrowth(_ changes: [Step], steps: [Step]) -> FormulaWording? {
        let reached = [steps[0]] + changes
        let amounts = reached.compactMap(\.amount)
        // Growth every level reads better as the formula in words ("1d4 + your level").
        guard changes.count >= 2, let interval = interval(changes.map(\.level)), interval > 1,
              steps.allSatisfy({ $0.amount?.sides == amounts.first?.sides && $0.amount != nil }) else { return nil }
        let increases = zip(amounts, amounts.dropFirst()).map { $1.minus($0) }
        guard increases.allSatisfy({ $0 == increases[0] }) else { return nil }
        return FormulaWording(start: steps[0].text, growth: "increasing by \(increases[0].text) at "
                              + "\(ordinal(changes[0].level)) level and every \(interval) levels after")
    }

    /// The steady gap between changes, when they carry on that way through 20th level.
    private static func interval(_ changes: [Int]) -> Int? {
        let gap = changes[1] - changes[0]
        return changes == Array(stride(from: changes[0], through: highestLevel, by: gap)) ? gap : nil
    }

    /// The steps where the value differs from the level before.
    private static func changes(in steps: [Step]) -> [Step] {
        zip(steps, steps.dropFirst()).filter { $0.text != $1.text }.map(\.1)
    }

    static func ordinal(_ number: Int) -> String {
        let suffix = switch (number % 10, number % 100) {
        case (_, 11...13): "th"
        case (1, _): "st"
        case (2, _): "nd"
        case (3, _): "rd"
        default: "th"
        }
        return "\(number)\(suffix)"
    }

    /// The formula at one level: its text, and its amount when it is that simple.
    private struct Step {
        let level: Int
        let text: String
        let amount: Amount?

        init(level: Int, _ formula: RollFormula) {
            self.level = level
            amount = Amount(formula)
            text = amount?.text ?? formula.text
        }

        /// The number, when the formula is only that.
        var number: Double? { amount?.sides == nil ? amount?.bonus : nil }
    }

    /// A number, dice, or dice with a number added or taken away: "1d4+1".
    private struct Amount: Equatable {
        let dice: Double
        let sides: Double?
        let bonus: Double

        init(dice: Double, sides: Double?, bonus: Double) {
            self.dice = dice
            self.sides = sides
            self.bonus = bonus
        }

        init?(_ formula: RollFormula) {
            switch formula {
            case let .number(value): self.init(dice: 0, sides: nil, bonus: value)
            case let .dice(.number(dice), .number(sides)): self.init(dice: dice, sides: sides, bonus: 0)
            case let .group(inner): self.init(inner)
            case let .operation(symbol, left, right) where symbol == "+" || symbol == "-":
                // Dice and a number, either way round; never dice taken away or two kinds of dice.
                guard let first = Amount(left), let second = Amount(right), first.sides == nil || second.sides == nil,
                      symbol == "+" || second.sides == nil else { return nil }
                let sign: Double = symbol == "+" ? 1 : -1
                self.init(dice: first.dice + second.dice, sides: first.sides ?? second.sides,
                          bonus: first.bonus + sign * second.bonus)
            default: return nil
            }
        }

        func minus(_ other: Amount) -> Amount {
            Amount(dice: dice - other.dice, sides: sides, bonus: bonus - other.bonus)
        }

        /// "1d4+1", "1d4", "3" or "1d4-1".
        var text: String {
            guard let sides, dice > 0 else { return RollFormula.numberText(bonus) }
            let diceText = "\(RollFormula.numberText(dice))d\(RollFormula.numberText(sides))"
            return bonus == 0 ? diceText : diceText + (bonus > 0 ? "+" : "") + RollFormula.numberText(bonus)
        }
    }
}
