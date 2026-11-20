import ArtExtraction
import ArtExtractionTestSupport
import Foundation
@testable import SharedLibraries
import Testing

/// Custom pawns are custom creatures (shared libraries R4.4 to R4.10).
@Suite struct CustomPawnTests {
    let library: SharedLibrary

    init() throws {
        library = try SharedLibrary(folder: temporaryFolder().appending(path: "Tableside"), app: .pawnShop)
    }

    /// A pawn as Pawn Shop makes one: a creature without a stat block, and its art under the same ID.
    func addPawn(named name: String, size: CreatureSize? = .medium) throws -> (CustomCreatureRecord, CustomArtRecord) {
        let id = UUID()
        let creature = CustomCreatureRecord(id: id, name: name, campaignID: nil, sharedVersion: nil, record: Data(),
                                            size: size)
        let art = CustomArtRecord(id: id, fileName: "\(id.uuidString).png", sharedVersion: nil, record: Data())
        try library.addCustomCreature(creature, art: art, image: Data([7]))
        return (creature, art)
    }

    @Test func keepsANameGameAndSizeEveryAppReads() throws {
        var gremlin = creature(named: "Gremlin")
        gremlin.game = .starfinder
        gremlin.size = .tiny
        try library.save(gremlin)
        #expect(try library.customCreatures() == [gremlin])
        #expect(gremlin.hasStatBlock)
    }

    @Test func addsAPawnAsACreatureWithItsArtInOneGo() throws {
        let (pawn, art) = try addPawn(named: "Iconic Ezren")
        #expect(try library.customCreatures() == [pawn])
        #expect(!pawn.hasStatBlock && pawn.game == nil)
        #expect(try library.customArt() == [art])
        #expect(try library.creatureArt() == [SharedLibrary.subject(ofCustomCreature: pawn.id): .custom(art.id)])
        #expect(try Data(contentsOf: library.customFile(art.fileName)) == Data([7]))
    }

    @Test func addsAPawnWhoseImageWasMovedInWithoutWritingOne() throws {
        let id = UUID()
        let art = CustomArtRecord(id: id, fileName: "moved.png", sharedVersion: nil, record: Data())
        try library.addCustomCreature(creature(named: "Moved"), art: art)
        #expect(try library.customArt() == [art])
        #expect(!FileManager.default.fileExists(atPath: library.customFile("moved.png").path))
    }

    @Test func renamesAndResizesWithoutTouchingTheStatBlock() throws {
        var gremlin = creature(named: "Gremlin")
        gremlin.game = .pathfinder
        try library.save(gremlin)
        let counter = try library.changeCounter()

        try library.renameCustomCreature(id: gremlin.id, to: "Grimple")
        try library.setCustomCreatureSize(.tiny, id: gremlin.id)
        gremlin.name = "Grimple"
        gremlin.size = .tiny
        #expect(try library.customCreatures(changedSince: counter) == [gremlin])

        try library.setCustomCreatureSize(nil, id: gremlin.id)
        #expect(try library.customCreatures().first?.size == nil)
    }

    @Test func reportsRenamingACreatureItDoesNotHave() throws {
        #expect(throws: SharedLibraryError.self) { try library.renameCustomCreature(id: UUID(), to: "Nobody") }
        #expect(throws: SharedLibraryError.self) { try library.setCustomCreatureSize(.huge, id: UUID()) }
    }

    @Test func removesACreatureWithItsChoiceAndArt() throws {
        let (pawn, art) = try addPawn(named: "Iconic Ezren")
        try library.removeCustomCreature(id: pawn.id)
        #expect(try library.customCreatures().isEmpty && library.customArt().isEmpty && library.creatureArt().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: library.customFile(art.fileName).path))
        let deletions = try library.changes(since: 0).deletions
        #expect(deletions[.customCreatures] == [pawn.id.uuidString] && deletions[.customArt] == [art.id.uuidString])
    }

    @Test func keepsArtAnotherCreatureStillChooses() throws {
        let (pawn, art) = try addPawn(named: "Iconic Ezren")
        try library.setCreatureArt(.custom(art.id), for: "pathfinder-monster-core.goblin-warrior")
        try library.removeCustomCreature(id: pawn.id)
        #expect(try library.customArt() == [art])
        #expect(try library.creatureArt().count == 1)
        #expect(FileManager.default.fileExists(atPath: library.customFile(art.fileName).path))
    }

    @Test func removesACreatureWithLibraryArtChosen() throws {
        let gremlin = creature(named: "Gremlin")
        try library.save(gremlin)
        try library.setCreatureArt(.library(UUID()), for: SharedLibrary.subject(ofCustomCreature: gremlin.id))
        try library.removeCustomCreature(id: gremlin.id)
        #expect(try library.creatureArt().isEmpty)
    }

    @Test func readsTheSixSizesFromATraitLine() {
        #expect(CreatureSize(trait: "Tiny") == .tiny)
        #expect(CreatureSize(trait: " gargantuan ") == .gargantuan)
        #expect(CreatureSize(trait: "Colossal") == nil)
        #expect(CreatureSize.tiny.trait == "Tiny")
        #expect(CreatureSize.allCases.map(\.pawnSize) == [.small, .small, .medium, .large, .huge, .gargantuan])
    }

    @Test func givesCreaturesFromBeforeVersion7NoNameGameOrSize() throws {
        let folder = temporaryFolder().appending(path: "Tableside")
        let old = try SharedLibrary(folder: folder, app: .turnkeeper)
        try old.save(creature(named: "Gremlin"))
        try old.connection().execute("""
            ALTER TABLE customCreatures DROP COLUMN name;
            ALTER TABLE customCreatures DROP COLUMN game;
            ALTER TABLE customCreatures DROP COLUMN size;
            PRAGMA user_version = 6;
            """)
        old.close()

        let reopened = try SharedLibrary(folder: folder, app: .pawnShop)
        let gremlin = try #require(try reopened.customCreatures().first)
        #expect(gremlin.name.isEmpty && gremlin.game == nil && gremlin.size == nil)
    }
}
