import ArtExtraction
import Foundation

/// What a pasted picture shows (R4.11): the creature's name and size, saved in the art's record by an app that
/// knows the creature, so that Pawn Shop, which has no bestiary, can name and size the art's pawn. An app's own
/// art model carries the same two keys, and the label reads them from whatever JSON the record is.
public struct ArtSubjectLabel: Codable, Equatable, Sendable {
    public var subjectName: String
    /// Nil when the creature's size isn't one of Paizo's six.
    public var subjectSize: CreatureSize?

    public init(name: String, size: CreatureSize?) {
        subjectName = name
        subjectSize = size
    }

    /// The label a custom art's record carries; nil for an empty record, one that isn't JSON, or one that names
    /// no creature. A size that isn't one of the six reads as none.
    public init?(record: Data) {
        guard let saved = try? JSONDecoder().decode(Saved.self, from: record),
              let name = saved.subjectName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty
        else { return nil }
        self.init(name: name, size: saved.subjectSize.flatMap(CreatureSize.init(rawValue:)))
    }

    /// The two keys as any record may hold them.
    private struct Saved: Decodable {
        var subjectName: String?
        var subjectSize: String?
    }
}

extension CustomArtRecord {
    /// The creature the art shows, when its record says (R4.11).
    public var subjectLabel: ArtSubjectLabel? { ArtSubjectLabel(record: record) }
}

extension SharedLibrary {
    /// The key prefix of a custom creature, whose pawn has the creature's own ID.
    static let customSubjectPrefix = "custom."

    /// The ID of a creature's pawn (R4.12), the same in every app and on every device: a custom creature's own
    /// ID, and for any other creature one made from its key, which stays when its art is replaced.
    public static func pawnID(forSubject subject: String) -> UUID {
        if subject.hasPrefix(customSubjectPrefix),
           let id = UUID(uuidString: String(subject.dropFirst(customSubjectPrefix.count))) {
            return id
        }
        return ArtKey.nameBasedUUID("creature:" + subject)
    }
}
