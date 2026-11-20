import Foundation

/// Custom creatures made, renamed, resized and removed in any app (shared libraries R4.6 to R4.9). Each write names
/// only its own columns, so Pawn Shop never touches a stat block.
extension SharedLibrary {
    /// Adds a creature, its custom art and the choice of that art for it, in one transaction (R4.6): how Pawn Shop
    /// makes a custom pawn. `image` is written to the art's file first when given; Pawn Shop's move (R6.6) moves the
    /// file in itself and passes none.
    public func addCustomCreature(_ creature: CustomCreatureRecord, art: CustomArtRecord, image: Data? = nil) throws {
        if let image { try writeCustomImage(image, named: art.fileName) }
        try write { writer in
            try writer.upsert(creature)
            try writer.upsert(art)
            try writer.upsert(.custom(art.id), for: Self.subject(ofCustomCreature: creature.id))
        }
    }

    /// Renames a custom creature in every app (R4.7), leaving the rest of its row alone.
    public func renameCustomCreature(id: UUID, to name: String) throws {
        try updateCustomCreature(id: id, [("name", .text(name))], operation: "Renaming a custom creature")
    }

    /// Changes a custom creature's size (R4.4b), leaving the rest of its row alone; nil when it has none of the six.
    public func setCustomCreatureSize(_ size: CreatureSize?, id: UUID) throws {
        try updateCustomCreature(id: id, [("size", size.map { .text($0.rawValue) } ?? .null)],
                                 operation: "Changing a custom creature's size")
    }

    /// Takes out a custom creature, the art chosen for it, and that art when no other creature chose it (R4.9).
    public func removeCustomCreature(id: UUID) throws {
        let subject = Self.subject(ofCustomCreature: id)
        let orphans = try write { writer in
            try writer.delete(from: .customCreatures, where: "id = ?", [.text(id.uuidString)])
            let chosen = try writer.database.rows("SELECT customArt FROM creatureArt WHERE subject = ?",
                                                  [.text(subject)]).first?.uuid("customArt")
            try writer.delete(from: .creatureArt, where: "subject = ?", [.text(subject)])
            return try chosen.map { try writer.removeUnchosenCustomArt(id: $0) } ?? []
        }
        for file in orphans { try? FileManager.default.removeItem(at: customFile(file)) }
    }

    /// The `creatureArt` subject of a custom creature: `custom.<id>`, as Turnkeeper keys it (R4.5).
    public static func subject(ofCustomCreature id: UUID) -> String {
        "custom.\(id.uuidString)"
    }

    /// Writes custom art's image to its file in `Custom`.
    func writeCustomImage(_ image: Data, named fileName: String) throws {
        do {
            try image.write(to: customFile(fileName), options: .atomic)
        } catch {
            throw SharedLibraryError(operation: "Saving \(fileName)", detail: error.localizedDescription)
        }
    }

    private func updateCustomCreature(id: UUID, _ columns: [(String, SQLValue)], operation: String) throws {
        try write { writer in
            let key = SQLValue.text(id.uuidString)
            guard try !writer.database.rows("SELECT id FROM customCreatures WHERE id = ?", [key]).isEmpty else {
                throw SharedLibraryError(operation: operation, detail: "no custom creature \(id.uuidString)")
            }
            let all = columns + [LibraryWriter.modified(Date()), ("changed", .integer(writer.counter))]
            try writer.database.run("UPDATE customCreatures SET "
                                    + all.map { "\($0.0) = ?" }.joined(separator: ", ") + " WHERE id = ?",
                                    all.map(\.1) + [key])
        }
    }
}

extension LibraryWriter {
    /// Deletes custom art no creature chooses any more; returns its image file's name, to remove once saved.
    func removeUnchosenCustomArt(id: UUID) throws -> [String] {
        let key = [SQLValue.text(id.uuidString)]
        guard try database.rows("SELECT subject FROM creatureArt WHERE customArt = ?", key).isEmpty else { return [] }
        let files = try database.rows("SELECT file FROM customArt WHERE id = ?", key).compactMap { $0.text("file") }
        try delete(from: .customArt, where: "id = ?", key)
        return files
    }
}
