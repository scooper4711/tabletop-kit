import Foundation

/// Describes a formula on the character's level the way the books do, by working it out for levels 1 to 20:
/// "your level", "half your level", "1d6 per level", "1d6, increasing by 1d6 at 3rd level and every 2 levels
/// after", or the values where they change, "1d6 (2d6 at 5th level, 3d6 at 10th)".
struct LevelWording {
    static let reference = "@actor.level"
    static let levels = 1...20

    /// The wording, or nil when the formula refers to something besides the level.
    static func wording(_ formula: RollFormula, values: FormulaValues) -> FormulaWording? {
        let folded = formula.folded(values)
        guard folded.references == [reference] else { return nil }
        let steps = levels.map { level in
            var known = values
            known.values[reference] = Double(level)
            return Step(formula.folded(known))
        }
        return wording(steps)
    }

    /// Lists of more changes than this read worse than the formula in words.
    static let listedChanges = 5

    private static func wording(_ steps: [Step]) -> FormulaWording? {
        if let words = levelWords(steps.map(\.number)) { return FormulaWording(start: words) }
        if let perLevel = perLevel(steps) { return FormulaWording(start: perLevel, ending: "per level") }
        let changes = changes(in: steps)
        if let regular = regularGrowth(changes, steps: steps) { return regular }
        guard changes.count <= listedChanges else { return nil }
        let listed = changes.enumerated().map { index, level in
            "\(steps[level - 1].text) at \(ordinal(level))" + (index == 0 ? " level" : "")
        }
        return FormulaWording(start: steps[0].text, growth: listed.isEmpty ? nil : listed.joined(separator: ", "))
    }

    /// "your level", "twice your level", "half your level" for a number that follows the level.
    private static func levelWords(_ numbers: [Double?]) -> String? {
        let values = numbers.compactMap { $0 }
        guard values.count == levels.count else { return nil }
        let candidates: [(String, (Double) -> Double)] = [
            ("your level", { $0 }),
            ("twice your level", { $0 * 2 }),
            ("half your level", { ($0 / 2).rounded(.down) }),
            ("half your level (rounded up)", { ($0 / 2).rounded(.up) })
        ]
        return candidates.first { _, rule in zip(levels, values).allSatisfy { rule(Double($0)) == $1 } }?.0
    }

    /// "1d6" (per level) for dice that gain one die a level.
    private static func perLevel(_ steps: [Step]) -> String? {
        guard let sides = steps[0].sides, steps.allSatisfy({ $0.sides == sides }) else { return nil }
        let counts = steps.compactMap(\.count)
        guard counts.count == levels.count, zip(levels, counts).allSatisfy({ Double($0) == $1 }) else { return nil }
        return "1d\(RollFormula.numberText(sides))"
    }

    /// "1d6, increasing by 1d6 at 3rd level and every 2 levels after" for a value that grows by the same
    /// amount at a steady interval, at least twice, through 20th level.
    private static func regularGrowth(_ changes: [Int], steps: [Step]) -> FormulaWording? {
        guard changes.count >= 2, let interval = interval(changes),
              steps.allSatisfy({ $0.sides == steps[0].sides }) else { return nil }
        let amounts = ([1] + changes).map { steps[$0 - 1].amount }
        let increases = zip(amounts, amounts.dropFirst()).map { pair -> Double? in
            guard let first = pair.0, let second = pair.1 else { return nil }
            return second - first
        }
        guard let increase = increases.first ?? nil, increases.allSatisfy({ $0 == increase }) else { return nil }
        let increaseText = steps[0].sides.map { "\(RollFormula.numberText(increase))d\(RollFormula.numberText($0))" }
            ?? RollFormula.numberText(increase)
        let every = interval == 1 ? "every level after" : "every \(interval) levels after"
        return FormulaWording(start: steps[0].text,
                       growth: "increasing by \(increaseText) at \(ordinal(changes[0])) level and \(every)")
    }

    /// The steady gap between changes, when they carry on that way through 20th level.
    private static func interval(_ changes: [Int]) -> Int? {
        let gap = changes[1] - changes[0]
        return changes == Array(stride(from: changes[0], through: levels.upperBound, by: gap)) ? gap : nil
    }

    /// The levels where the value differs from the level before.
    private static func changes(in steps: [Step]) -> [Int] {
        levels.dropFirst().filter { steps[$0 - 1].text != steps[$0 - 2].text }
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

    /// The formula at one level: its text, and its number or dice when it is that simple.
    private struct Step {
        let text: String
        let number: Double?
        let count: Double?
        let sides: Double?

        init(_ formula: RollFormula) {
            text = formula.text
            if case let .number(value) = formula { number = value } else { number = nil }
            if case let .dice(.number(count), .number(sides)) = formula {
                self.count = count
                self.sides = sides
            } else {
                count = nil
                sides = nil
            }
        }

        /// The dice count, or the number, that growth is measured in.
        var amount: Double? { count ?? number }
    }
}
