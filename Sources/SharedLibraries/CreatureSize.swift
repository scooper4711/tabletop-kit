import ArtExtraction

/// A creature's size, one of Paizo's six (shared libraries R4.4a): the same in a custom creature's stat block and on
/// its pawn. Tiny is a size of its own that prints the same pawn as Small, so a size set in Pawn Shop can be written
/// back to the stat block's size trait without guessing.
public enum CreatureSize: String, Codable, CaseIterable, Sendable {
    case tiny, small, medium, large, huge, gargantuan

    /// The size a trait line names, such as "Tiny", with case ignored; nil for a word that isn't one of the six.
    public init?(trait: String) {
        self.init(rawValue: trait.trimmingCharacters(in: .whitespaces).lowercased())
    }

    /// The word a stat block's trait line prints, such as "Tiny".
    public var trait: String { rawValue.capitalized }

    /// The pawn this size prints: Tiny and Small print the same one.
    public var pawnSize: PawnSize {
        switch self {
        case .tiny, .small: .small
        case .medium: .medium
        case .large: .large
        case .huge: .huge
        case .gargantuan: .gargantuan
        }
    }
}
