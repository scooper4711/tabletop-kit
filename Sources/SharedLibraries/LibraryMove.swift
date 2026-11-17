import ArtExtraction
import Foundation

/// What an app brings into the shared library when it moves in (shared libraries R6).
public struct LibraryMove: Sendable {
    public var app: TablesideApp
    /// The folder of the app's own art library (`art-library.json`), if it has one.
    public var artFolder: URL?
    /// Turnkeeper's custom creatures.
    public var customCreatures: [CustomCreatureRecord] = []
    /// Turnkeeper's custom art, whose images are in `customArtFolder`.
    public var customArt: [CustomArtRecord] = []
    public var customArtFolder: URL?
    /// The art chosen for creatures, by bestiary key or `custom.<id>`, with library art by its old ID.
    public var creatureArt: [String: CreatureArtChoice] = [:]
    /// Art the app has keyed itself, such as Pawn Shop's pawns (`library.json` version 2), moved in as it is.
    public var keyedArt: [SharedArtEntry] = []
    /// The PDFs the keyed art comes from, as the app reaches them.
    public var keyedSources: [ArtSource] = []
    /// Other IDs the keyed art answers to (R2.7): each old ID, with the ID or print key of the art it names.
    public var aliases: [UUID: UUID] = [:]
    /// What the app has learned about art, by the art's ID, print key or alias (R3.3).
    public var notes: [UUID: ArtNote] = [:]
    /// Kept PDFs to move in, by source ID.
    public var keptPDFs: [String: URL] = [:]
    /// Pictures to move into the library's `Pictures` folder, by their name there (`SharedPrint.print.tokenFile`).
    public var pictureFiles: [String: URL] = [:]

    public init(app: TablesideApp, artFolder: URL?) {
        self.app = app
        self.artFolder = artFolder
    }
}

/// What a move brought in.
public struct MoveReport: Equatable, Sendable {
    /// The pieces of art the app's library had.
    public var art = 0
    /// The pieces of art the shared library has after the move.
    public var sharedArt = 0
    /// The files moved into the shared library's folders.
    public var filesMoved = 0
}

extension SharedLibrary {
    /// The name the app's old art library file is given once moved; kept for one version, then deleted.
    public static let movedSuffix = ".moved"

    /// True when `app` has moved its library in.
    public func hasMovedIn(_ app: TablesideApp) throws -> Bool {
        try moveStage(of: app) == .finished
    }

    /// Moves an app's library in, merging it into what the other apps moved in (R6.1, R6.2); nil when it has
    /// moved in already. An app calls it at launch until it succeeds: a move cut short finishes the next time,
    /// and until then the app keeps its own library (R6.5).
    public func moveIn(_ move: LibraryMove) throws -> MoveReport? {
        let stage = try moveStage(of: move.app)
        guard stage != .finished else { return nil }
        let plan = try MovePlan(move: move, library: self)
        var report = MoveReport(art: plan.entries.count + move.keyedArt.count)
        if stage == nil {
            try write { writer in try plan.record(with: writer) }
        }
        report.filesMoved = try plan.moveFiles()
        try plan.retireOldLibrary()
        try write { writer in try writer.setMoveStage(.finished, of: move.app) }
        report.sharedArt = try artEntries().count
        return report
    }

    // MARK: Helpers

    private func moveStage(of app: TablesideApp) throws -> MoveStage? {
        try connection().rows("SELECT stage FROM moves WHERE app = ?", [.text(app.rawValue)])
            .first?.text("stage").flatMap(MoveStage.init(rawValue:))
    }
}

/// How far an app's move has got: its rows are written, then its files are moved.
enum MoveStage: String {
    case recorded, finished
}

extension LibraryWriter {
    func setMoveStage(_ stage: MoveStage, of app: TablesideApp) throws {
        try upsert(.moves, [("app", .text(app.rawValue)), ("stage", .text(stage.rawValue))])
    }
}
