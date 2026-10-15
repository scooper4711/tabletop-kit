import Foundation

/// A Foundry roll formula, such as `(floor(@item.level/2))d6` or `2d8+@actor.abilities.str.mod`: parsed so the
/// values an importer knows can be put in and every part without dice or unknown references worked out.
indirect enum RollFormula: Equatable {
    case number(Double)
    case reference(String)
    case dice(count: RollFormula, sides: RollFormula)
    case operation(Character, RollFormula, RollFormula)
    case negation(RollFormula)
    case function(String, [RollFormula])
    /// A part in parentheses, kept so the printed formula groups as the original did.
    case group(RollFormula)
    /// A part with a flavor tag, as in `1d4[splash]`.
    case flavored(RollFormula, String)

    /// The formula parsed, or nil when it isn't one this parser reads.
    init?(_ text: String) {
        var parser = FormulaParser(text)
        guard let formula = parser.formula() else { return nil }
        self = formula
    }

    /// `formula` with `values` put in and its constant parts worked out, printed as Foundry writes formulas:
    /// `(floor(2/2))d6` becomes `1d6`. A formula this parser can't read comes back with only the values put in.
    static func resolved(_ formula: String, values: FormulaValues) -> String {
        guard let parsed = RollFormula(formula) else { return values.substituted(in: formula) }
        return parsed.folded(values).text
    }

    /// The references still in the formula.
    var references: Set<String> {
        switch self {
        case .number: []
        case let .reference(name): [name]
        case let .dice(count, sides): count.references.union(sides.references)
        case let .operation(_, left, right): left.references.union(right.references)
        case let .negation(inner), let .group(inner), let .flavored(inner, _): inner.references
        case let .function(_, arguments): arguments.reduce(into: Set()) { $0.formUnion($1.references) }
        }
    }

    /// The formula with `values` put in and every part that has no dice and no unknown reference worked out.
    func folded(_ values: FormulaValues) -> RollFormula {
        if let value = value(values) { return .number(value) }
        switch self {
        case .number, .reference: return self
        case let .dice(count, sides): return .dice(count: count.folded(values), sides: sides.folded(values))
        case let .operation(symbol, left, right): return .operation(symbol, left.folded(values), right.folded(values))
        case let .negation(inner): return .negation(inner.folded(values))
        case let .function(name, arguments): return .function(name, arguments.map { $0.folded(values) })
        case let .flavored(inner, flavor): return .flavored(inner.folded(values), flavor)
        case let .group(inner):
            let folded = inner.folded(values)
            return folded.isAtomic ? folded : .group(folded)
        }
    }

    /// The formula's value when it has no dice and every reference is known.
    func value(_ values: FormulaValues) -> Double? {
        switch self {
        case let .number(value): value
        case let .reference(name): values[name]
        case .dice, .flavored: nil
        case let .operation(symbol, left, right):
            left.value(values).flatMap { left in right.value(values).flatMap { Self.apply(symbol, left, $0) } }
        case let .negation(inner): inner.value(values).map { -$0 }
        case let .group(inner): inner.value(values)
        case let .function(name, arguments):
            FormulaFunctions.apply(name, arguments.map { $0.value(values) })
        }
    }

    /// The formula as Foundry writes it, without spaces.
    var text: String { printed(words: [:]) }

    /// The formula with references named in words and spaced operators, for a formula that can't be worked
    /// out: `1d4+@item.system.damage.dice` reads "1d4 + the number of weapon damage dice".
    func text(naming words: [String: String]) -> String { printed(words: words) }

    private var isAtomic: Bool {
        switch self {
        case .number, .reference, .dice, .function, .group: true
        default: false
        }
    }

    private func printed(words: [String: String]) -> String {
        let spaced = !words.isEmpty
        switch self {
        case let .number(value): return Self.numberText(value)
        case let .reference(name): return words[name] ?? name
        case let .dice(count, sides):
            return Self.diceOperand(count, words: words) + "d" + Self.diceOperand(sides, words: words)
        case let .operation(symbol, left, right):
            let shown = spaced && symbol == "*" ? "×" : String(symbol)
            let operands = (left.printed(words: words), right.printed(words: words))
            return spaced ? "\(operands.0) \(shown) \(operands.1)" : "\(operands.0)\(shown)\(operands.1)"
        case let .negation(inner): return "-" + inner.printed(words: words)
        case let .group(inner): return "(" + inner.printed(words: words) + ")"
        case let .flavored(inner, flavor): return inner.printed(words: words) + "[\(flavor)]"
        case let .function(name, arguments):
            return name + "(" + arguments.map { $0.printed(words: words) }.joined(separator: ",") + ")"
        }
    }

    /// A dice count or size: plain when it is a number, else in parentheses, as Foundry writes `(@item.level)d6`.
    private static func diceOperand(_ operand: RollFormula, words: [String: String]) -> String {
        switch operand {
        case .number, .group: operand.printed(words: words)
        default: "(" + operand.printed(words: words) + ")"
        }
    }

    static func numberText(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(value)
    }

    private static func apply(_ symbol: Character, _ left: Double, _ right: Double) -> Double? {
        switch symbol {
        case "+": left + right
        case "-": left - right
        case "*": left * right
        case "/": right == 0 ? nil : left / right
        default: nil
        }
    }
}

/// The functions Foundry formulas use; comparisons give 1 or 0.
enum FormulaFunctions {
    static func apply(_ name: String, _ arguments: [Double?]) -> Double? {
        let values = arguments.compactMap { $0 }
        guard values.count == arguments.count, let function = functions[name], function.arity.contains(values.count)
        else { return nil }
        return function.apply(values)
    }

    private typealias Function = (arity: ClosedRange<Int>, apply: @Sendable ([Double]) -> Double?)

    private static func compare(_ test: @escaping @Sendable (Double, Double) -> Bool) -> Function {
        (2...2, { test($0[0], $0[1]) ? 1 : 0 })
    }

    private static let functions: [String: Function] = [
        "floor": (1...1, { $0[0].rounded(.down) }),
        "ceil": (1...1, { $0[0].rounded(.up) }),
        "round": (1...1, { $0[0].rounded() }),
        "abs": (1...1, { abs($0[0]) }),
        "max": (1...Int.max, { $0.max() }),
        "min": (1...Int.max, { $0.min() }),
        "ternary": (3...3, { $0[0] != 0 ? $0[1] : $0[2] }),
        "gte": compare(>=), "gt": compare(>), "lte": compare(<=), "lt": compare(<), "eq": compare(==)
    ]
}

/// What a formula's references are worth, as far as the importer knows, and how to name the rest.
public struct FormulaValues: Sendable {
    public var values: [String: Double]

    public init(_ values: [String: Double] = [:]) {
        self.values = values
    }

    /// A spell's rank or an item's level, which pf2e's formulas call `@item.level` or `@item.rank`.
    public static func level(_ level: Int) -> FormulaValues {
        FormulaValues(["@item.level": Double(level), "@item.rank": Double(level)])
    }

    public subscript(name: String) -> Double? { values[name] }

    /// References only known in play, named as the books name them.
    public static let words: [String: String] = [
        "@actor.level": "your level",
        "@actor.abilities.str.mod": "your Strength modifier",
        "@actor.abilities.dex.mod": "your Dexterity modifier",
        "@actor.abilities.con.mod": "your Constitution modifier",
        "@actor.abilities.int.mod": "your Intelligence modifier",
        "@actor.abilities.wis.mod": "your Wisdom modifier",
        "@actor.abilities.cha.mod": "your Charisma modifier",
        "@item.system.damage.dice": "the number of weapon damage dice"
    ]

    /// `text` with the known values written in, for a formula the parser can't read.
    func substituted(in text: String) -> String {
        values.keys.sorted { $0.count > $1.count }.reduce(text) { text, name in
            text.replacingOccurrences(of: name, with: RollFormula.numberText(values[name] ?? 0))
        }
    }
}
