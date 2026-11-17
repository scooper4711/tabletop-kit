import ArtExtraction
import Foundation

/// One app's library, keyed and ready to move in: the same every time it is worked out, so a move cut short
/// finishes from it at the next launch.
struct MovePlan {
    let move: LibraryMove
    let library: SharedLibrary
    /// The old library, when the app has one that hasn't moved.
    let oldLibrary: ArtLibrary?
    /// Each old entry's ID, and the entry with its prints keyed.
    let entries: [(oldID: UUID, entry: SharedArtEntry)]
    /// Files to move: from the app's folders, to the shared library's.
    let files: [(from: URL, to: URL)]

    init(move: LibraryMove, library: SharedLibrary) throws {
        self.move = move
        self.library = library
        oldLibrary = try move.artFolder.flatMap { folder in
            FileManager.default.fileExists(atPath: folder.appending(path: Self.oldFileName).path)
                ? try ArtLibrary(folder: folder) : nil
        }
        var files: [(from: URL, to: URL)] = []
        entries = oldLibrary.map { Self.keyed($0, library: library, files: &files) } ?? []
        for source in oldLibrary?.sources ?? [] where source.location == .kept {
            files.append((Self.oldSourcesFolder(of: move).appending(path: "\(source.id).pdf"),
                          library.keptFile(sourceID: source.id)))
        }
        for art in move.customArt {
            guard let folder = move.customArtFolder else { break }
            files.append((folder.appending(path: art.fileName), library.customFile(art.fileName)))
        }
        files += move.keptPDFs.sorted { $0.key < $1.key }.map { ($1, library.keptFile(sourceID: $0)) }
        files += move.pictureFiles.sorted { $0.key < $1.key }.map { ($1, library.pictureFile($0)) }
        self.files = files
    }

    /// Writes the app's sources, art, aliases and creature library into the shared library.
    func record(with writer: LibraryWriter) throws {
        for source in oldLibrary?.sources ?? [] { try writer.add(source, for: move.app) }
        for folder in oldLibrary?.watchedFolders ?? [] { try writer.addWatchedFolder(folder, for: move.app) }
        for (oldID, entry) in entries {
            try writer.addAlias(oldID, app: move.app, entry: try writer.merge(entry))
        }
        try recordKeyedArt(with: writer)
        for creature in move.customCreatures { try writer.upsert(creature) }
        for art in move.customArt { try writer.upsert(art) }
        try recordCreatureArt(with: writer)
        try writer.setMoveStage(.recorded, of: move.app)
    }

    /// Moves the files, skipping those moved already; returns how many it moved.
    func moveFiles() throws -> Int {
        var moved = 0
        for (from, to) in files where FileManager.default.fileExists(atPath: from.path) {
            do {
                if try Self.isSameFile(from, alreadyAt: to) {
                    try FileManager.default.removeItem(at: from)
                } else {
                    try? FileManager.default.removeItem(at: to)
                    try FileManager.default.moveItem(at: from, to: to)
                    moved += 1
                }
            } catch {
                throw SharedLibraryError(operation: "Moving \(from.lastPathComponent)",
                                         detail: error.localizedDescription)
            }
        }
        return moved
    }

    /// Renames the old library's file, so the app no longer reads it.
    func retireOldLibrary() throws {
        guard let folder = move.artFolder, oldLibrary != nil else { return }
        let old = folder.appending(path: Self.oldFileName)
        let retired = folder.appending(path: Self.oldFileName + SharedLibrary.movedSuffix)
        do {
            try? FileManager.default.removeItem(at: retired)
            try FileManager.default.moveItem(at: old, to: retired)
        } catch {
            throw SharedLibraryError(operation: "Renaming \(Self.oldFileName)", detail: error.localizedDescription)
        }
    }

    // MARK: Helpers

    static let oldFileName = "art-library.json"

    /// Art the app keyed itself, its aliases, and its notes, a note the user corrected winning over one they
    /// didn't (R6.2).
    private func recordKeyedArt(with writer: LibraryWriter) throws {
        for source in move.keyedSources { try writer.add(source, for: move.app) }
        for entry in move.keyedArt { try writer.merge(entry) }
        for (oldID, target) in move.aliases.sorted(by: { $0.key.uuidString < $1.key.uuidString }) {
            guard let entry = try ArtRows.entryID(answeringTo: target, in: writer.database) else { continue }
            try writer.addAlias(oldID, app: move.app, entry: entry)
        }
        for (id, note) in move.notes {
            guard let entry = try ArtRows.entryID(answeringTo: id, in: writer.database) else { continue }
            let known = try ArtRows.notes(in: writer.database, where: "entry = ?", [.text(entry.uuidString)])[entry]
            if known?.isCorrected == true, !note.isCorrected { continue }
            try writer.upsert(note, for: entry)
        }
    }

    /// The art chosen for creatures, library art found by the old ID's alias. A creature that has art chosen
    /// already, by an app that moved in before, keeps it.
    private func recordCreatureArt(with writer: LibraryWriter) throws {
        let chosen = try writer.database.rows("SELECT subject FROM creatureArt").compactMap { $0.text("subject") }
        for (subject, choice) in move.creatureArt where !chosen.contains(subject) {
            guard case .library(let oldID) = choice else {
                try writer.upsert(choice, for: subject)
                continue
            }
            let entry = try ArtRows.entryID(answeringTo: oldID, in: writer.database) ?? oldID
            try writer.upsert(.library(entry), for: subject)
        }
    }

    /// Each entry with its prints' keys (R2), and the token and item pictures renamed by their prints' keys.
    private static func keyed(_ old: ArtLibrary, library: SharedLibrary,
                              files: inout [(from: URL, to: URL)]) -> [(oldID: UUID, entry: SharedArtEntry)] {
        let inputs = old.entries.flatMap { entry in
            entry.prints.map { ArtKeyInput(sourceID: $0.sourceID, name: entry.name, size: entry.size,
                                           fingerprint: entry.fingerprint, face: $0.face) }
        }
        var keys = ArtKey.keys(for: inputs)[...]
        return old.entries.map { entry in
            var shared = SharedArtEntry(entry, keys: Array(keys.prefix(entry.prints.count)))
            keys = keys.dropFirst(entry.prints.count)
            for index in shared.prints.indices {
                guard let file = shared.prints[index].print.tokenFile else { continue }
                let renamed = shared.prints[index].key.uuidString + "." + (file as NSString).pathExtension
                files.append((old.folder.appending(path: "Tokens/\(file)"), library.pictureFile(renamed)))
                shared.prints[index].print.tokenFile = renamed
            }
            shared.id = shared.keyedID
            return (entry.id, shared)
        }
    }

    private static func oldSourcesFolder(of move: LibraryMove) -> URL {
        (move.artFolder ?? URL(filePath: "/")).appending(path: "Sources", directoryHint: .isDirectory)
    }

    /// True when `destination` holds the same file: for a kept PDF, one whose SHA-256 is still its name.
    private static func isSameFile(_ source: URL, alreadyAt destination: URL) throws -> Bool {
        guard FileManager.default.fileExists(atPath: destination.path) else { return false }
        guard destination.pathExtension == "pdf" else { return true }
        return try ArtLibrary.digest(of: destination) == destination.deletingPathExtension().lastPathComponent
    }
}
