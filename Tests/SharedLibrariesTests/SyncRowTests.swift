import ArtExtraction
import Foundation
@testable import SharedLibraries
import Testing

/// Merging in notes, the art chosen for creatures, custom creatures and custom art (library sync design).
@Suite struct SyncRowTests {
    let devices: SyncedDevices
    let pawn = SyncFixture.pawnKey
    let figure = SyncFixture.figureKey
    let early = Date(timeIntervalSinceReferenceDate: 1_000)
    let late = Date(timeIntervalSinceReferenceDate: 2_000)

    init() throws {
        devices = try SyncedDevices()
    }

    var first: SharedLibrary { devices.firstLibrary }
    var second: SharedLibrary { devices.secondLibrary }

    /// Both devices have the art "Ogre" (pawn and Battle Card), from one source each, in step with each other.
    func shareArt() throws {
        try first.write { writer in
            try SyncFixture.addSource("pawns", to: writer)
            try SyncFixture.addSource("cards", to: writer)
            try writer.merge(SyncFixture.entry([.init(.pawn, pawn, "pawns"), .init(.figure, figure, "cards")]))
        }
        try devices.exchange()
    }

    @Test func findsANoteByAnyIDOfItsArt() throws {
        try shareArt()
        try second.write { writer in try writer.upsert(ArtNote(tags: ["club"]), for: pawn) }
        let sent = try second.sendEverything()
        let named = try #require(sent.first)
        guard case .saved(let record, let fields) = named else { return }
        var payload = try JSONDecoder().decode(NotePayload.self, from: record.payload)
        payload.entry = figure
        let byFigure = SyncRecord(id: SyncRecordID(kind: .note, name: "note-\(figure.uuidString)"),
                                  payload: try SyncPayloads.encode(payload), title: "")

        try first.applyRemote([.saved(byFigure, systemFields: fields)])
        #expect(try first.notes() == [pawn: ArtNote(tags: ["club"])])
    }

    @Test func keepsANoteAsideUntilItsArtArrivesThenAppliesIt() throws {
        let sender = try devices.first.library()
        try sender.write { writer in
            try SyncFixture.addSource("pawns", to: writer)
            try writer.merge(SyncFixture.entry([.init(.pawn, pawn, "pawns")]))
            try writer.upsert(ArtNote(tags: ["club"]), for: pawn)
        }
        let sent = try sender.sendEverything()
        let notes = savedRecords(sent, of: .note)
        let sources = savedRecords(sent, of: .source)

        let waiting = try second.applyRemote(notes)
        #expect(waiting == RemoteApplyReport(applied: 0, parked: 1, unchanged: 0))
        #expect(try second.notes().isEmpty)
        let report = try second.applyRemote(sources)
        #expect(report.applied == 2 && report.parked == 0)
        #expect(try second.notes() == [pawn: ArtNote(tags: ["club"])])
        #expect(try second.connection().rows("SELECT * FROM parkedRecords").isEmpty)
    }

    @Test func renamesANoteWhenTheArtsIDDiffersHere() throws {
        try shareArt()
        let lone = try devices.first.library(.pawnShop)
        try lone.write { writer in
            try SyncFixture.addSource("cards", to: writer)
            try writer.merge(SyncFixture.entry([.init(.figure, figure, "cards")]))
            try writer.upsert(ArtNote(tags: ["club"]), for: figure)
        }
        let renamed = savedRecords(try lone.sendEverything(), of: .note)

        try second.applyRemote(renamed)
        #expect(try second.notes() == [pawn: ArtNote(tags: ["club"])])
        let candidates = try second.syncCandidates()
        #expect(candidates.saves.map(\.name) == ["note-\(pawn.uuidString)"])
        #expect(candidates.deletions.map(\.name) == ["note-\(figure.uuidString)"])
    }

    @Test func letsACorrectedNoteBeatAnUncorrectedOneWhateverTheirTimes() throws {
        try shareArt()
        try first.write { writer in
            try writer.upsert(ArtNote(tags: ["axe"], isCorrected: true), for: pawn, modified: early)
        }
        try second.write { writer in try writer.upsert(ArtNote(tags: ["club"]), for: pawn, modified: late) }
        try devices.exchange()
        #expect(try first.notes() == [pawn: ArtNote(tags: ["axe"], isCorrected: true)])
        #expect(try second.notes() == first.notes())
    }

    @Test func letsTheLaterEditWinForEachKindOfRow() throws {
        try shareArt()
        let art = UUID()
        let creature = creature(named: "Gremlin")
        for (library, tag, date) in [(first, "axe", early), (second, "club", late)] {
            try library.write { writer in
                try writer.upsert(ArtNote(tags: [tag]), for: pawn, modified: date)
                try writer.upsert(.custom(art), for: "gremlin", modified: date)
                try writer.upsert(CustomCreatureRecord(id: creature.id, campaignID: nil, sharedVersion: nil,
                                                       record: Data(tag.utf8)), modified: date)
                try writer.upsert(CustomArtRecord(id: art, fileName: "\(tag).png", sharedVersion: nil,
                                                  record: Data(tag.utf8)), modified: date)
            }
        }
        try Data([1]).write(to: first.customFile("axe.png"))
        try Data([2]).write(to: second.customFile("club.png"))
        try devices.exchange()

        for library in [first, second] {
            #expect(try library.notes() == [pawn: ArtNote(tags: ["club"])])
            #expect(try library.customCreatures().first?.record == Data("club".utf8))
            #expect(try library.customArt().first?.fileName == "club.png")
        }
        #expect(try Data(contentsOf: first.customFile("club.png")) == Data([2]))
    }

    @Test func keepsALaterLocalEditAgainstAnEarlierOneFromElsewhere() throws {
        try shareArt()
        try second.write { writer in try writer.upsert(ArtNote(tags: ["club"]), for: pawn, modified: late) }
        try first.write { writer in try writer.upsert(ArtNote(tags: ["axe"]), for: pawn, modified: early) }
        try devices.exchange()
        #expect(try first.notes() == [pawn: ArtNote(tags: ["club"])])
    }

    @Test func keepsARowEditedHereWhenItWasDeletedElsewhere() throws {
        try shareArt()
        let gremlin = creature(named: "Gremlin")
        try first.save(gremlin)
        try devices.exchange()
        try first.removeCustomCreature(id: gremlin.id)
        try second.save(CustomCreatureRecord(id: gremlin.id, campaignID: nil, sharedVersion: nil,
                                             record: Data("edited".utf8)))
        try devices.exchange()

        #expect(try first.customCreatures().first?.record == Data("edited".utf8))
        #expect(try second.customCreatures().count == 1)
    }

    @Test func deletesARowDeletedElsewhereWhenNothingHereIsUnsent() throws {
        try shareArt()
        let gremlin = creature(named: "Gremlin")
        let image = CustomArtRecord(id: UUID(), fileName: "a.png", sharedVersion: nil, record: Data())
        try first.save(gremlin)
        try first.save(image, image: Data([1]))
        try first.setNote(ArtNote(tags: ["club"]), forArt: pawn)
        try first.setCreatureArt(.custom(image.id), for: "gremlin")
        try devices.exchange()
        #expect(FileManager.default.fileExists(atPath: second.customFile("a.png").path))

        try first.removeCustomCreature(id: gremlin.id)
        try first.removeCustomArt(id: image.id)
        try first.setNote(nil, forArt: pawn)
        try first.setCreatureArt(nil, for: "gremlin")
        try devices.exchange()
        #expect(try second.customCreatures().isEmpty && second.customArt().isEmpty && second.notes().isEmpty)
        #expect(try second.creatureArt().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: second.customFile("a.png").path))
    }

    @Test func sendsCustomArtsImageWithItsRecord() throws {
        let image = CustomArtRecord(id: UUID(), fileName: "a.png", sharedVersion: nil, record: Data([7]))
        try first.save(image, image: Data([1, 2, 3]))
        let id = try #require(try first.syncCandidates().saves.first)
        let record = try #require(try first.outgoingRecord(id)).record
        #expect(record.file == first.customFile("a.png") && record.id.kind == .customArt)
        try devices.exchange()
        #expect(try Data(contentsOf: second.customFile("a.png")) == Data([1, 2, 3]))
    }

    @Test func keepsCustomArtsImageWhenItsStagedCopyIsGoneBeforeItIsPutInPlace() throws {
        let art = CustomArtRecord(id: UUID(), fileName: "a.png", sharedVersion: nil, record: Data())
        try first.save(art, image: Data([1]))
        try devices.exchange()
        try first.save(CustomArtRecord(id: art.id, fileName: "a.png", sharedVersion: nil, record: Data([2])),
                       image: Data([3]))
        let update = try first.sendEverything(fields: Data([2]))
        let application = try second.write { writer in
            var application = RemoteApplication(writer: writer, library: second)
            try application.apply(update)
            return application
        }

        // As when another app on the device, applying the same record, has put the staged image in place.
        try FileManager.default.removeItem(at: second.stagedCustomFile("a.png"))
        application.finish()
        #expect(FileManager.default.fileExists(atPath: second.customFile("a.png").path))
    }

    @Test func forgetsANoteKeptAsideWhenItIsDeletedBeforeItsArtArrives() throws {
        let sender = try devices.first.library()
        try sender.write { writer in
            try SyncFixture.addSource("pawns", to: writer)
            try writer.merge(SyncFixture.entry([.init(.pawn, pawn, "pawns")]))
            try writer.upsert(ArtNote(tags: ["club"]), for: pawn)
        }
        let sent = try sender.sendEverything()
        try second.applyRemote(savedRecords(sent, of: .note))

        try second.applyRemote([.deleted(SyncRecordID(kind: .note, name: "note-\(pawn.uuidString)"))])
        try second.applyRemote(savedRecords(sent, of: .source))
        #expect(try second.notes().isEmpty)
        #expect(try second.connection().rows("SELECT * FROM parkedRecords").isEmpty)
    }

    @Test func keepsCustomArtsImagesWhenABatchFails() throws {
        let kept = CustomArtRecord(id: UUID(), fileName: "kept.png", sharedVersion: nil, record: Data())
        let changed = CustomArtRecord(id: UUID(), fileName: "changed.png", sharedVersion: nil, record: Data())
        try first.save(kept, image: Data([1]))
        try first.save(changed, image: Data([2]))
        try devices.exchange()
        try first.save(changed, image: Data([3]))
        let candidate = try #require(try first.syncCandidates().saves.first)
        let update = try #require(try first.outgoingRecord(candidate))
        var broken = update.record
        broken.id = SyncRecordID(kind: .customArt, name: "customArt-\(UUID().uuidString)")
        broken.file = devices.first.root.appending(path: "no-such-image.png")
        let batch: [RemoteChange] = [
            .deleted(SyncRecordID(kind: .customArt, name: "customArt-\(kept.id.uuidString)")),
            .saved(update.record, systemFields: Data([2])), .saved(broken, systemFields: Data([1]))
        ]

        #expect(throws: SharedLibraryError.self) { try second.applyRemote(batch) }
        #expect(try second.customArt().count == 2)
        #expect(try Data(contentsOf: second.customFile("kept.png")) == Data([1]))
        #expect(try Data(contentsOf: second.customFile("changed.png")) == Data([2]))
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: second.customFile("").path)
        #expect(leftovers.sorted() == ["changed.png", "kept.png"])
    }
}
