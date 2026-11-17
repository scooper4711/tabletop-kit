import Foundation

/// Products that print no names on their pawns (shared libraries R2.3a). Their art borrows the name of the same
/// picture printed in another product; the rest waits, under a stand-in name, for the user to name it.
public enum NamelessProducts {
    public static let titleFragments = ["Heroes & Villains"]

    /// True when the product titled `title` prints no names.
    public static func contains(title: String) -> Bool {
        titleFragments.contains { title.localizedCaseInsensitiveContains($0) }
    }

    /// The stand-in name for art printed without a name in the product titled `title`.
    public static func standInName(forTitle title: String) -> String { "Unknown \(title)" }
}

extension ArtFingerprint {
    /// Thumbnails at most this far apart are taken for the same art when giving art another product's name.
    /// Stricter than `matchingDistance`, which also requires equal names: across Pawn Shop's whole library, pawns
    /// up to about 15 apart showed the same figure and those from about 16 on did not.
    public static let namingDistance = 15.0

    /// True when both show the same images, or look the same by the stricter naming distance.
    public func isSameArt(as other: ArtFingerprint) -> Bool {
        guard !imageDigests.isEmpty, !other.imageDigests.isEmpty else { return false }
        return imageDigests == other.imageDigests || thumbnailDistance(from: other) <= Self.namingDistance
    }

    /// How far `other` is from this art when naming it: 0 for the same images, else the thumbnails' distance.
    public func namingDistance(from other: ArtFingerprint) -> Double {
        imageDigests == other.imageDigests ? 0 : thumbnailDistance(from: other)
    }
}
