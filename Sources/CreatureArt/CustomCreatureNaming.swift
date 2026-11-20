import Bestiary
import SharedLibraries

extension Creature {
    /// The creature with a custom creature's row put over its stat block (shared libraries R4.4a, R4.7): the row's
    /// name and size are what every app shows, so a rename or a size set in Pawn Shop shows before Turnkeeper next
    /// saves the record. An empty name (a row synced by a build before names) or no size leaves the record's.
    public func applying(name: String, size: CreatureSize?) -> Creature {
        var creature = self
        if !name.isEmpty { creature.name = name }
        if let size { creature.traits.size = size.trait }
        return creature
    }
}
