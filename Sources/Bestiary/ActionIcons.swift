/// Paizo's Pathfinder-Icons font, which draws the action icons. The apps bundle the unaltered file from their
/// private `Artwork` submodule: its license (the Paizo Compatibility License) forbids changing or redistributing it.
public enum ActionIcons {
    /// The font's PostScript name.
    public static let fontName = "Pathfinder-Icons"
    /// The font file's name.
    public static let fileName = "Pathfinder-Icons.ttf"

    /// The character the font draws `cost` with: one of its private-use code points, which work without the
    /// ligatures (`[one-action]` and so on) its readme describes. Empty for `.none`.
    public static func character(for cost: ActionCost) -> String {
        switch cost {
        case .one: "\u{E902}"
        case .two: "\u{E901}"
        case .three: "\u{E900}"
        case .free: "\u{E903}"
        case .reaction: "\u{E904}"
        case .none: ""
        }
    }

    /// Plain Unicode symbols standing in for the icons where the font is missing. Empty for `.none`.
    public static func symbols(for cost: ActionCost) -> String {
        switch cost {
        case .one: "◆"
        case .two: "◆◆"
        case .three: "◆◆◆"
        case .free: "◇"
        case .reaction: "⤾"
        case .none: ""
        }
    }
}
