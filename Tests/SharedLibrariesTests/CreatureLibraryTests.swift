import Foundation
@testable import SharedLibraries
import ArtExtractionTestSupport
import Testing

/// The creature library (shared libraries R3.4, R4).
@Suite struct CreatureLibraryTests {
    let library: SharedLibrary

    init() throws {
        library = try SharedLibrary(folder: temporaryFolder().appending(path: "Tableside"), app: .turnkeeper)
    }

    @Test func keepsCustomCreaturesWithTheirCampaignAndSharedVersion() throws {
        let campaign = UUID()
        var gremlin = creature(named: "Gremlin", campaign: campaign)
        gremlin.sharedVersion = Date(timeIntervalSinceReferenceDate: 1000)
        try library.save(gremlin)
        try library.save(creature(named: "Kobold"))
        #expect(try library.customCreatures().first { $0.id == gremlin.id } == gremlin)

        let counter = try library.changeCounter()
        gremlin.record = Data("Gremlin, edited".utf8)
        try library.save(gremlin)
        #expect(try library.customCreatures(changedSince: counter) == [gremlin])

        try library.removeCustomCreature(id: gremlin.id)
        #expect(try library.customCreatures().count == 1)
    }

    @Test func keepsCustomArtWithItsImage() throws {
        let art = CustomArtRecord(id: UUID(), fileName: "art.png",
                                  sharedVersion: Date(timeIntervalSinceReferenceDate: 5), record: Data("{}".utf8))
        try library.save(art, image: Data([1, 2, 3]))
        #expect(try library.customArt() == [art])
        #expect(try Data(contentsOf: library.customFile("art.png")) == Data([1, 2, 3]))
        try library.save(art)
        #expect(try library.customArt(changedSince: 0).count == 1)

        try library.removeCustomArt(id: art.id)
        #expect(try library.customArt().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: library.customFile("art.png").path))
    }

    @Test func reportsAnImageItCannotSave() throws {
        let art = CustomArtRecord(id: UUID(), fileName: "missing/art.png", sharedVersion: nil, record: Data())
        #expect(throws: SharedLibraryError.self) { try library.save(art, image: Data([1])) }
    }

    @Test func remembersTheArtChosenForEachCreature() throws {
        let entry = UUID(), custom = UUID()
        try library.setCreatureArt(.library(entry), for: "pathfinder-monster-core.goblin-warrior")
        try library.setCreatureArt(.custom(custom), for: "custom.1")
        #expect(try library.creatureArt() == ["pathfinder-monster-core.goblin-warrior": .library(entry),
                                              "custom.1": .custom(custom)])

        try library.setCreatureArt(nil, for: "custom.1")
        #expect(try library.creatureArt() == ["pathfinder-monster-core.goblin-warrior": .library(entry)])
    }
}
