import Foundation

/// How hurt a creature looks to the players, without numbers.
public enum HealthEstimate: String, CaseIterable, Sendable {
    case unharmed = "Unharmed"
    case healthy = "Healthy"
    case injured = "Injured"
    case bloodied = "Bloodied"
    case nearDeath = "Near Death"
    case down = "Down"

    /// The band for the fraction of maximum HP left: over 75% is healthy, over 50% injured, over 25% bloodied.
    public init(hitPoints: Int, maxHitPoints: Int) {
        guard hitPoints > 0 else { self = .down; return }
        guard maxHitPoints > 0, hitPoints < maxHitPoints else { self = .unharmed; return }
        let fraction = Double(hitPoints) / Double(maxHitPoints)
        let bands: [(above: Double, estimate: HealthEstimate)] = [(0.75, .healthy), (0.5, .injured), (0.25, .bloodied)]
        self = bands.first { fraction > $0.above }?.estimate ?? .nearDeath
    }

    public var label: String { rawValue }
}
