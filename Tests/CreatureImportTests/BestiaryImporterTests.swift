import Bestiary
import Foundation
import Testing
@testable import CreatureImport

@Suite("Importing a bestiary end to end")
struct BestiaryImporterTests {
    /// A copy of the fixture repository with an Actor pack holding the goblin warrior.
    private func repositoryWithACreature(in folder: URL) throws -> URL {
        let repository = folder.appendingPathComponent("repo")
        try FileManager.default.copyItem(at: try Fixtures.repository(), to: repository)
        let pack = repository.appendingPathComponent("packs/pf2e/test-bestiary")
        try FileManager.default.createDirectory(at: pack, withIntermediateDirectories: true)
        let goblin = try #require(Bundle.module.url(forResource: "goblin-warrior", withExtension: "json",
                                                    subdirectory: "Fixtures"))
        try FileManager.default.copyItem(at: goblin, to: pack.appendingPathComponent("goblin-warrior.json"))
        let system = repository.appendingPathComponent("system.pf2e.json")
        var manifest = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: system)) as? [String: Any])
        var packs = manifest["packs"] as? [[String: Any]] ?? []
        packs.append(["name": "test-bestiary", "label": "Test Bestiary", "type": "Actor",
                      "path": "packs/pf2e/test-bestiary"])
        manifest["packs"] = packs
        try JSONSerialization.data(withJSONObject: manifest).write(to: system)
        return repository
    }

    @Test("Creatures, conditions and art overrides are written for the bestiary to load")
    func writesWhatTheBestiaryLoads() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ImporterTests-\(UUID())")
        defer { try? FileManager.default.removeItem(at: folder) }
        let output = folder.appendingPathComponent("Generated")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        try #"{"Goblin Warrior": "GOBLIN, WARRIOR"}"#.write(to: folder.appendingPathComponent("art-overrides.json"),
                                                         atomically: true, encoding: .utf8)
        let configuration = ImportConfiguration(repository: try repositoryWithACreature(in: folder),
                                                outputDirectory: output, configurationDirectory: folder)
        let report = try BestiaryImporter(configuration: configuration).run()
        #expect(report.creatureCount == 1)

        let bestiary = try BestiaryStore(generatedDirectory: output)
        let entry = try #require(bestiary.index.entries.first)
        #expect(entry.name == "Goblin Warrior" && entry.game == .pathfinder)
        #expect(bestiary.creature(entry.key)?.name == "Goblin Warrior")
        #expect(!bestiary.conditions.isEmpty)
        #expect(bestiary.artOverrides == ["Goblin Warrior": "GOBLIN, WARRIOR"])
        #expect(FileManager.default.fileExists(atPath: output.appendingPathComponent("import-report.md").path))
    }
}
