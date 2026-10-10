import Foundation

/// The parts of a player character's sheet that a creature doesn't have.
public struct PlayerDetails: Codable, Sendable, Hashable {
    public var ancestry: String
    public var heritage: String
    public var background: String
    public var className: String
    /// Zero when the sheet shows none.
    public var classDC: Int
    public var feats: [String]
    public var classFeatures: [String]

    public init(ancestry: String = "", heritage: String = "", background: String = "", className: String = "") {
        self.ancestry = ancestry
        self.heritage = heritage
        self.background = background
        self.className = className
        classDC = 0
        feats = []
        classFeatures = []
    }
}
