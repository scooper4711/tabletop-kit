import Foundation
import Testing
@testable import Bestiary

@Suite("Health estimates")
struct HealthEstimateTests {
    @Test("Bands by the fraction of maximum HP, at their edges", arguments: [
        (100, 100, HealthEstimate.unharmed), (120, 100, .unharmed), (99, 100, .healthy), (76, 100, .healthy),
        (75, 100, .injured), (51, 100, .injured), (50, 100, .bloodied), (26, 100, .bloodied),
        (25, 100, .nearDeath), (1, 100, .nearDeath), (0, 100, .down), (-5, 100, .down),
        (4, 5, .healthy), (3, 4, .injured), (1, 4, .nearDeath)
    ])
    func bands(hitPoints: Int, maxHitPoints: Int, estimate: HealthEstimate) {
        #expect(HealthEstimate(hitPoints: hitPoints, maxHitPoints: maxHitPoints) == estimate)
    }

    @Test("Without a maximum, a creature is unharmed until it's down")
    func noMaximum() {
        #expect(HealthEstimate(hitPoints: 5, maxHitPoints: 0) == .unharmed)
        #expect(HealthEstimate(hitPoints: 0, maxHitPoints: 0) == .down)
        #expect(HealthEstimate.nearDeath.label == "Near Death")
    }
}
