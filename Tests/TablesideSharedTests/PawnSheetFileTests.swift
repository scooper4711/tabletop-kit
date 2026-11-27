import Foundation
@testable import TablesideShared
import Testing

/// A request written as a sheet file for Pawn Shop (R6.5 to R6.7).
@Suite struct PawnSheetFileTests {
    private let goblin = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!

    private func request(_ lines: [PawnSheetRequest.Line], title: String = "Trouble in Otari") -> PawnSheetRequest {
        PawnSheetRequest(title: title, lines: lines)
    }

    private func contents(of data: Data) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func entries(of data: Data) throws -> [[String: Any]] {
        try #require(try contents(of: data)["entries"] as? [[String: Any]])
    }

    @Test func eachLineIsAnEntryWithItsPawnCountAndName() throws {
        let file = request([.init(name: "Goblin Warrior", count: 3, pawnID: goblin)]).sheetFile()
        let entry = try #require(try entries(of: file).first)
        let label = try #require(entry["label"] as? [String: Any])
        #expect(entry["pawnID"] as? String == goblin.uuidString)
        #expect(entry["count"] as? Int == 3)
        #expect(label["id"] as? String == goblin.uuidString)
        #expect(label["name"] as? String == "Goblin Warrior")
        #expect(label["product"] as? String == "")
        #expect(UUID(uuidString: try #require(entry["id"] as? String)) != nil)
    }

    @Test func entriesKeepTheOrderAndHaveIDsOfTheirOwn() throws {
        let file = request([.init(name: "Spike Trap"), .init(name: "Goblin Warrior", count: 2, pawnID: goblin),
                            .init(name: "Sewer Ooze", count: 4)]).sheetFile()
        let entries = try entries(of: file)
        #expect(entries.compactMap { ($0["label"] as? [String: Any])?["name"] as? String }
            == ["Spike Trap", "Goblin Warrior", "Sewer Ooze"])
        #expect(Set(entries.compactMap { $0["id"] as? String }).count == 3)
    }

    @Test func aLineWithoutAPawnGetsAnIDOfItsOwn() throws {
        let file = request([.init(name: "Spike Trap", count: 2), .init(name: "Sewer Ooze")]).sheetFile()
        let entries = try entries(of: file)
        let pawns = entries.compactMap { $0["pawnID"] as? String }
        #expect(Set(pawns).count == 2 && pawns.allSatisfy { UUID(uuidString: $0) != nil })
        #expect(entries.compactMap { ($0["label"] as? [String: Any])?["id"] as? String } == pawns)
    }

    @Test func aLineThatAsksForNoneIsLeftOut() throws {
        let file = request([.init(name: "Ogre", count: 0), .init(name: "Ghost", count: -2),
                            .init(name: "Spike Trap")]).sheetFile()
        #expect(try entries(of: file).count == 1)
        #expect(try entries(of: request([]).sheetFile()).isEmpty)
    }

    @Test func theFileSaysItsFormatAndHoldsNoSettings() throws {
        let contents = try contents(of: request([.init(name: "Spike Trap")]).sheetFile())
        #expect(contents["formatVersion"] as? Int == 2)
        #expect(contents["formatVersion"] as? Int == PawnSheetRequest.sheetFileFormatVersion)
        #expect(contents["settings"] == nil)
        #expect(contents["readerVersion"] == nil)
    }

    @Test func theFileCarriesTheReadersVersionWhenGiven() throws {
        let contents = try contents(of: request([.init(name: "Spike Trap")]).sheetFile(readerVersion: 6))
        #expect(contents["readerVersion"] as? Int == 6)
    }

    @Test(arguments: [("Trouble in Otari", "Trouble in Otari.pawnsheet"),
                      ("#6-08 Upon Wheels and Rime: Docks", "#6-08 Upon Wheels and Rime Docks.pawnsheet"),
                      ("Either/Or \\ Both", "Either Or Both.pawnsheet"),
                      ("  Spaced\n\tout  ", "Spaced out.pawnsheet"),
                      ("...hidden", "hidden.pawnsheet"),
                      ("", "Pawns.pawnsheet"),
                      (" /: ", "Pawns.pawnsheet"),
                      ("Agathion, Vicuñal ゴブリン", "Agathion, Vicuñal ゴブリン.pawnsheet")])
    func theFileIsNamedAfterTheTitle(title: String, name: String) {
        #expect(request([], title: title).sheetFileName == name)
    }

    @Test func aLongTitleIsCutShort() {
        let name = request([], title: String(repeating: "Goblin ", count: 40)).sheetFileName
        #expect(name.hasSuffix(".pawnsheet"))
        #expect(name.count <= 100 + ".pawnsheet".count)
        #expect(!name.dropLast(".pawnsheet".count).hasSuffix(" "))
    }

    @Test func theTypeIsPawnShopsSheet() {
        #expect(PawnSheetRequest.sheetFileType == "io.github.scooper4711.pawnsheet")
        #expect(PawnSheetRequest.sheetFileExtension == "pawnsheet")
    }
}
