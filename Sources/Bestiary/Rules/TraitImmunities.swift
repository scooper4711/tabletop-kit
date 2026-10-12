import Foundation

/// The immunities a creature's traits grant by their rules text, which the source data often leaves out: most
/// constructs list only "mental", or nothing.
public enum TraitImmunities {
    /// Trait slug → what its rules text makes the creature immune to. Undead aren't here: their trait grants
    /// nothing.
    static let byTrait: [String: [String]] = [
        "construct": [
            "bleed", "death effects", "disease", "healing", "nonlethal attacks", "poison", "spirit", "vitality",
            "void", "doomed", "drained", "fatigued", "paralyzed", "sickened", "unconscious"
        ],
        "mindless": ["mental"],
        "swarm": ["grabbed", "prone", "restrained"]
    ]

    /// The source's immunities, then those the traits grant that it doesn't already list.
    public static func merged(_ immunities: [String], traits: [String]) -> [String] {
        var seen = Set(immunities.map(comparable))
        var result = immunities
        let granted = traits.flatMap { byTrait[$0.lowercased()] ?? [] }
        for immunity in granted where seen.insert(comparable(immunity)).inserted {
            result.append(immunity)
        }
        return result
    }

    /// "Death-Effects" and "death effects" are the same immunity.
    private static func comparable(_ immunity: String) -> String {
        immunity.lowercased().replacingOccurrences(of: "-", with: " ")
    }
}

extension Creature {
    /// The creature's immunities with those its traits grant.
    public var allImmunities: [String] {
        TraitImmunities.merged(defenses.immunities, traits: traits.traits)
    }
}
