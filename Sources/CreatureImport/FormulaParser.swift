import Foundation

/// Reads a Foundry roll formula into a `RollFormula`, by recursive descent:
///
///     sum     = product (("+" | "-") product)*
///     product = roll (("*" | "/") roll)*
///     roll    = (unary ("d" unary)? | "d" unary) flavor?
///     unary   = "-" unary | primary
///     primary = number | @reference | name "(" arguments ")" | "(" sum ")"
struct FormulaParser {
    private let characters: [Character]
    private var position = 0

    init(_ text: String) {
        characters = Array(text)
    }

    /// The whole text as a formula, or nil when any of it isn't one.
    mutating func formula() -> RollFormula? {
        guard let result = sum(), next == nil else { return nil }
        return result
    }

    /// The next character, past any spaces; spaces only separate.
    private var next: Character? {
        mutating get {
            while position < characters.count, characters[position].isWhitespace { position += 1 }
            return position < characters.count ? characters[position] : nil
        }
    }

    private mutating func take(_ character: Character) -> Bool {
        guard next == character else { return false }
        position += 1
        return true
    }

    private mutating func sum() -> RollFormula? {
        guard var result = product() else { return nil }
        while let symbol = next, symbol == "+" || symbol == "-" {
            position += 1
            guard let right = product() else { return nil }
            result = .operation(symbol, result, right)
        }
        return result
    }

    private mutating func product() -> RollFormula? {
        guard var result = roll() else { return nil }
        while let symbol = next, symbol == "*" || symbol == "/" {
            position += 1
            guard let right = roll() else { return nil }
            result = .operation(symbol, result, right)
        }
        return result
    }

    private mutating func roll() -> RollFormula? {
        guard let roll = dice() else { return nil }
        return flavor().map { .flavored(roll, $0) } ?? roll
    }

    private mutating func dice() -> RollFormula? {
        if take("d") { return unary().map { .dice(count: .number(1), sides: $0) } }
        guard let count = unary() else { return nil }
        guard take("d") else { return count }
        return unary().map { .dice(count: count, sides: $0) }
    }

    private mutating func unary() -> RollFormula? {
        if take("-") { return unary().map { .negation($0) } }
        return primary()
    }

    private mutating func primary() -> RollFormula? {
        guard let character = next else { return nil }
        if character.isNumber { return number() }
        if character == "@" { return reference() }
        if take("(") {
            guard let inner = sum(), take(")") else { return nil }
            return .group(inner)
        }
        return function()
    }

    private mutating func number() -> RollFormula? {
        let digits = run { $0.isNumber || $0 == "." }
        return Double(digits).map { .number($0) }
    }

    private mutating func reference() -> RollFormula? {
        position += 1
        let name = run { $0.isLetter || $0.isNumber || $0 == "." || $0 == "_" }
        return name.isEmpty ? nil : .reference("@" + name)
    }

    /// `floor(…)` and its kin; a word that isn't followed by "(" isn't part of a formula.
    private mutating func function() -> RollFormula? {
        let name = run(\.isLetter)
        guard !name.isEmpty, take("(") else { return nil }
        var arguments: [RollFormula] = []
        repeat {
            guard let argument = sum() else { return nil }
            arguments.append(argument)
        } while take(",")
        return take(")") ? .function(name, arguments) : nil
    }

    /// A `[splash]` tag after a part.
    private mutating func flavor() -> String? {
        guard next == "[", let close = characters[position...].firstIndex(of: "]") else { return nil }
        let tag = String(characters[(position + 1)..<close])
        position = close + 1
        return tag
    }

    /// The characters from here that `isIncluded` accepts, stopping at a space.
    private mutating func run(_ isIncluded: (Character) -> Bool) -> String {
        let start = position
        while position < characters.count, isIncluded(characters[position]) { position += 1 }
        return String(characters[start..<position])
    }
}
