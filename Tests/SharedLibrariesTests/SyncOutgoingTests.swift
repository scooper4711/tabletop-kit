import ArtExtraction
import Foundation
@testable import SharedLibraries
import Testing

/// What a device sends to the cloud (library sync design, "What to upload").
@Suite struct SyncOutgoingTests {
    let device = SyncDevice()

    func importedLibrary() throws -> (SharedLibrary, UUID) {
        let library = try device.library()
        try library.add(device.pawnBox(), keeping: false)
        try library.sendEverything()
        return (library, try #require(try library.artIDs().first))
    }

    @Test func offersEveryRecordOfAnImportedLibraryOnceAndThenNone() throws {
        let library = try device.library()
        try library.add(device.pawnBox(), keeping: false)

        let candidates = try library.syncCandidates()
        #expect(candidates.saves.map(\.kind) == [.source])
        #expect(candidates.deletions.isEmpty)
        try library.sendEverything()
        #expect(try library.syncCandidates().isEmpty)
    }

    @Test func offersARecordAfterEachKindOfWrite() throws {
        let (library, art) = try importedLibrary()
        let gremlin = creature(named: "Gremlin")
        try library.setNote(ArtNote(tags: ["club"]), forArt: art)
        try library.setCreatureArt(.library(art), for: "bestiary.gremlin")
        try library.save(gremlin)
        try library.save(CustomArtRecord(id: UUID(), fileName: "a.png", sharedVersion: nil, record: Data()),
                         image: Data([1, 2]))

        let kinds = try library.syncCandidates().saves.map(\.kind)
        #expect(Set(kinds) == [.note, .creatureArt, .customCreature, .customArt])
        #expect(kinds.count == 4)
        try library.sendEverything()
        try library.setNote(ArtNote(tags: ["axe"]), forArt: art)
        #expect(try library.syncCandidates().saves.map(\.kind) == [.note])
    }

    @Test func offersASourceWhenItsArtOrAliasChanges() throws {
        let (library, art) = try importedLibrary()
        let source = try #require(try library.sources().first)
        try library.write { writer in try writer.addAlias(UUID(), app: .turnkeeper, entry: art) }
        #expect(try library.syncCandidates().saves == [SyncRecordID(kind: .source, name: "source-\(source.id)")])
        try library.sendEverything()
        try library.write { writer in try writer.setPicture("new.heic", ofArtPrinting: art) }
        #expect(try library.syncCandidates().saves.map(\.kind) == [.source])
    }

    @Test func dropsAWriteThatChangesNothingThatSyncs() throws {
        let (library, _) = try importedLibrary()
        let pdf = try device.pawnBox()
        try device.library(.fieldGuide).add(pdf, keeping: false)
        let candidates = try library.syncCandidates()
        #expect(candidates.saves.count == 1)

        #expect(try library.outgoingRecord(candidates.saves[0]) == nil)
        #expect(try library.syncCandidates().isEmpty)
    }

    @Test func keepsAChangeMadeWhileARecordWasInFlight() throws {
        let (library, art) = try importedLibrary()
        try library.setNote(ArtNote(tags: ["club"]), forArt: art)
        let id = try #require(try library.syncCandidates().saves.first)
        let outgoing = try #require(try library.outgoingRecord(id))

        try library.setNote(ArtNote(tags: ["axe"]), forArt: art)
        try library.markSent(outgoing, systemFields: Data([1]))
        #expect(try library.syncCandidates().saves == [id])
    }

    @Test func turnsADeletedRowIntoADeletion() throws {
        let (library, art) = try importedLibrary()
        let gremlin = creature(named: "Gremlin")
        try library.save(gremlin)
        try library.setNote(ArtNote(tags: ["club"]), forArt: art)
        try library.sendEverything()
        try library.removeCustomCreature(id: gremlin.id)
        try library.setNote(nil, forArt: art)

        let candidates = try library.syncCandidates()
        #expect(candidates.saves.isEmpty)
        #expect(Set(candidates.deletions.map(\.kind)) == [.customCreature, .note])
        try library.sendEverything()
        #expect(try library.syncCandidates().isEmpty)
    }

    @Test func offersARecordAgainWhenTheServerLostIt() throws {
        let (library, art) = try importedLibrary()
        try library.setNote(ArtNote(tags: ["club"]), forArt: art)
        try library.sendEverything()
        let id = SyncRecordID(kind: .note, name: "note-\(art.uuidString)")

        try library.forgetSystemFields(of: id)
        #expect(try library.syncCandidates().saves == [id])
        #expect(try library.outgoingRecord(id)?.systemFields == nil)
    }

    @Test func offersEverythingAgainAfterForgettingTheServer() throws {
        let (library, art) = try importedLibrary()
        try library.setNote(ArtNote(tags: ["club"]), forArt: art)
        try library.sendEverything()
        try library.setEngineState(Data([9]))

        try library.forgetServer()
        #expect(try library.syncCandidates().saves.count == 2)
        #expect(try library.engineState() == nil)
    }

    @Test func offersNothingWhilePaused() throws {
        let (library, art) = try importedLibrary()
        try library.setNote(ArtNote(tags: ["club"]), forArt: art)
        try library.setSyncPaused(true)
        #expect(try library.isSyncPaused && library.syncCandidates().isEmpty)
        try library.setSyncPaused(false)
        #expect(try !library.isSyncPaused && !library.syncCandidates().isEmpty)
    }

    @Test func keepsTheEngineStateOfEachAppApart() throws {
        let turnkeeper = try device.library(.turnkeeper)
        let fieldGuide = try device.library(.fieldGuide)
        try turnkeeper.setEngineState(Data([1]))
        try fieldGuide.setEngineState(Data([2]))
        #expect(try turnkeeper.engineState() == Data([1]) && fieldGuide.engineState() == Data([2]))
        try turnkeeper.setEngineState(nil)
        #expect(try turnkeeper.engineState() == nil && fieldGuide.engineState() == Data([2]))
    }

    @Test func namesRecordsByKindAndKey() throws {
        let subject = "bestiary.goblin warrior ☠"
        let id = UUID()
        #expect(SyncRecordName.make(.note, rowKey: id.uuidString) == "note-\(id.uuidString)")
        #expect(SyncRecordName.make(.customCreature, rowKey: "x") == "creature-x")
        let name = SyncRecordName.make(.creatureArt, rowKey: subject)
        #expect(name.hasPrefix("creatureArt-") && name.count == 12 + 64)
        #expect(SyncRecordName.rowKey(of: SyncRecordID(kind: .creatureArt, name: name)) == nil)
        #expect(SyncRecordName.rowKey(of: SyncRecordID(kind: .customArt, name: "customArt-7")) == "7")
        #expect(SyncRecordName.rowKey(of: SyncRecordID(kind: .customArt, name: "note-7")) == nil)
    }

    @Test func findsCreatureArtByTheHashOfItsSubject() throws {
        let (library, art) = try importedLibrary()
        try library.setCreatureArt(.library(art), for: "bestiary.goblin warrior ☠")
        let id = try #require(try library.syncCandidates().saves.first)
        let outgoing = try #require(try library.outgoingRecord(id))
        #expect(outgoing.rowKey == "bestiary.goblin warrior ☠" && outgoing.record.title == outgoing.rowKey)
    }
}
