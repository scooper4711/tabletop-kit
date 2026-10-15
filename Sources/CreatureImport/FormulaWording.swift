import Foundation

/// How a roll formula reads in rules text (R4.4): worked out from the values the importer knows, or, when it
/// refers to something only known in play, described ("1d6 per level", "your Strength modifier").
public struct FormulaWording: Equatable, Sendable {
    /// The formula, or its value at 1st level.
    public var start: String
    /// How a value on the character's level grows ("increasing by 1d6 at 3rd level and every 2 levels after").
    public var growth: String?
    /// Words that end the wording, as in "1d6 fire per level".
    public var ending: String?
    /// Whether the formula was worked out, so it can be rolled as written.
    public var isWorkedOut: Bool

    public init(start: String, growth: String? = nil, ending: String? = nil, isWorkedOut: Bool = false) {
        self.start = start
        self.growth = growth
        self.ending = ending
        self.isWorkedOut = isWorkedOut
    }

    /// `formula` worked out from `values`, or described.
    public init(_ formula: String, values: FormulaValues) {
        let resolved = RollFormula.resolved(formula, values: values)
        guard resolved.contains("@"), let parsed = RollFormula(resolved) else {
            self.init(start: resolved, isWorkedOut: true)
            return
        }
        self = LevelWording.wording(parsed, values: values)
            ?? FormulaWording(start: parsed.namedText)
    }

    /// The wording with words after the start, such as a damage type: "1d6 fire (increasing by …)".
    public func text(following words: [String] = []) -> String {
        ([start] + words + [ending].compactMap { $0 }).joined(separator: " ") + (growth.map { " (\($0))" } ?? "")
    }
}
