import Foundation
@testable import SharedLibraries
import Testing

/// Syncing a custom creature's name, game and size (shared libraries "Custom pawns are custom creatures").
@Suite struct SyncCustomCreatureTests {
    let devices: SyncedDevices

    init() throws {
        devices = try SyncedDevices()
    }

    var first: SharedLibrary { devices.firstLibrary }
    var second: SharedLibrary { devices.secondLibrary }

    @Test func sendsANameGameAndSize() throws {
        var gremlin = creature(named: "Gremlin")
        gremlin.game = .pathfinder
        gremlin.size = .tiny
        try first.save(gremlin)
        try devices.exchange()
        #expect(try second.customCreatures() == [gremlin])

        try second.renameCustomCreature(id: gremlin.id, to: "Grimple")
        try second.setCustomCreatureSize(nil, id: gremlin.id)
        try devices.exchange()
        let renamed = try #require(try first.customCreatures().first)
        #expect(renamed.name == "Grimple" && renamed.size == nil && renamed.game == .pathfinder)
    }

    @Test func keepsTheNameGameAndSizeWhenABuildBeforeThemSendsTheCreature() throws {
        var gremlin = creature(named: "Gremlin")
        gremlin.game = .starfinder
        gremlin.size = .huge
        try first.save(gremlin)
        let sent = try first.sendEverything()
        try second.applyRemote(sent)
        #expect(try second.customCreatures() == [gremlin])

        guard case .saved(let record, let fields) = try #require(savedRecords(sent, of: .customCreature).first) else {
            return
        }
        var payload = try JSONDecoder().decode(CustomCreaturePayload.self, from: record.payload)
        payload.name = nil
        payload.game = nil
        payload.size = nil
        payload.record = Data("edited".utf8)
        payload.modified += 10
        let older = SyncRecord(id: record.id, payload: try SyncPayloads.encode(payload), title: record.title)
        try second.applyRemote([.saved(older, systemFields: fields + Data([2]))])

        gremlin.record = Data("edited".utf8)
        #expect(try second.customCreatures() == [gremlin])
    }
}
