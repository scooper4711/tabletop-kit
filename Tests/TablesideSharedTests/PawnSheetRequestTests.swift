#if os(macOS)
import CoreGraphics
#endif
import Foundation
@testable import TablesideShared
import Testing

/// The link another app sends Pawn Shop for a new sheet of pawns (R6).
@Suite struct PawnSheetRequestTests {
    private let goblin = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!

    private func request(_ lines: [PawnSheetRequest.Line]) -> PawnSheetRequest {
        PawnSheetRequest(title: "Trouble in Otari", lines: lines)
    }

    private func link(_ text: String) throws -> URL {
        try #require(URL(string: text))
    }

    @Test func aLinkGivesBackItsRequest() throws {
        let sent = request([.init(name: "Goblin Warrior", count: 3, pawnID: goblin), .init(name: "Spike Trap")])
        let url = sent.url
        #expect(url.scheme == "pawnshop")
        #expect(url.host == "sheet")
        #expect(try PawnSheetRequest(url: url) == sent)
    }

    @Test func aLineWithoutAPawnKeepsNone() throws {
        let read = try PawnSheetRequest(url: request([.init(name: "Spike Trap", count: 2)]).url)
        #expect(read.lines == [.init(name: "Spike Trap", count: 2, pawnID: nil)])
    }

    @Test(arguments: ["Agathion, Vicuñal", "Krooth & Co. +1/2?", "ゴブリン 🐉", ""])
    func namesKeepEveryCharacter(name: String) throws {
        let sent = PawnSheetRequest(title: name, lines: [.init(name: name, count: 1, pawnID: goblin)])
        #expect(try PawnSheetRequest(url: sent.url) == sent)
    }

    @Test func thePayloadNeedsNoEscaping() throws {
        // Long enough for Base64 to use every one of its characters.
        let lines = (0..<40).map { PawnSheetRequest.Line(name: "Creature \($0) ÿ?>", count: $0, pawnID: UUID()) }
        let url = request(lines).url
        let payload = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first?.value)
        #expect(payload.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") })
        #expect(try PawnSheetRequest(url: url).lines == lines)
    }

    @Test func theSameRequestGivesTheSameLink() {
        let lines = [PawnSheetRequest.Line(name: "Goblin Warrior", count: 3, pawnID: goblin)]
        #expect(request(lines).url == request(lines).url)
    }

    @Test func theSchemeAndHostIgnoreCase() throws {
        let url = request([.init(name: "Goblin Warrior")]).url
        let text = url.absoluteString.replacingOccurrences(of: "pawnshop://sheet", with: "PawnShop://Sheet")
        let shouted = try link(text)
        #expect(try PawnSheetRequest(url: shouted).lines.map(\.name) == ["Goblin Warrior"])
    }

    @Test(arguments: ["scrollkeeper://sheet?request=e30", "pawnshop://library", "https://example.com/sheet",
                      "file:///tmp/sheet.pawnsheet"])
    func anotherLinkIsNotARequest(text: String) throws {
        let url = try link(text)
        #expect(throws: PawnSheetRequestError.unrecognizedLink) { try PawnSheetRequest(url: url) }
    }

    @Test(arguments: ["pawnshop://sheet", "pawnshop://sheet?request=", "pawnshop://sheet?request=%25%25",
                      "pawnshop://sheet?request=bm90IGpzb24", "pawnshop://sheet?request=e30",
                      "pawnshop://sheet?other=e30"])
    func aDamagedPayloadIsUnreadable(text: String) throws {
        let url = try link(text)
        #expect(throws: PawnSheetRequestError.unreadable) { try PawnSheetRequest(url: url) }
    }

    /// The link carrying `json` as its payload.
    private func link(carrying json: String) throws -> URL {
        let payload = Data(json.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return try link("pawnshop://sheet?request=\(payload)")
    }

    @Test func aRequestSaysItsFormat() throws {
        let sent = request([.init(name: "Goblin Warrior")])
        #expect(sent.formatVersion == PawnSheetRequest.currentFormatVersion)
        let json = try #require(String(data: try JSONEncoder().encode(sent), encoding: .utf8))
        #expect(json.contains("\"formatVersion\":1"))
    }

    @Test func aRequestWithoutAFormatIsTheFirst() throws {
        let json = #"{"title":"Docks","lines":[{"name":"Ogre","count":2}]}"#
        let read = try PawnSheetRequest(url: link(carrying: json))
        #expect(read.formatVersion == 1)
        #expect(read == PawnSheetRequest(title: "Docks", lines: [.init(name: "Ogre", count: 2)]))
    }

    @Test func fieldsAddedLaterAreIgnored() throws {
        let json = #"{"formatVersion":1,"title":"Docks","paper":"A4","lines":[{"name":"Ogre","count":2,"mood":"x"}]}"#
        #expect(try PawnSheetRequest(url: link(carrying: json)).lines == [.init(name: "Ogre", count: 2)])
    }

    @Test func aNewerFormatIsRefusedWhateverItHolds() throws {
        let known = PawnSheetRequest.currentFormatVersion
        for json in [#"{"formatVersion":\#(known + 1),"title":"Docks","lines":[]}"#,
                     #"{"formatVersion":\#(known + 6),"sheets":{"all":"changed"}}"#] {
            let url = try link(carrying: json)
            #expect(throws: PawnSheetRequestError.self) { try PawnSheetRequest(url: url) }
        }
        let url = try link(carrying: #"{"formatVersion":\#(known + 1),"title":"Docks","lines":[]}"#)
        #expect(throws: PawnSheetRequestError.newerFormat(known + 1)) { try PawnSheetRequest(url: url) }
    }

    @Test func theProbeCarriesNoRequest() {
        #expect(PawnSheetRequest.probeURL.absoluteString == "pawnshop://sheet")
        #expect(throws: PawnSheetRequestError.unreadable) { try PawnSheetRequest(url: PawnSheetRequest.probeURL) }
    }

    @Test func errorsSayWhatFailed() {
        #expect(PawnSheetRequestError.unrecognizedLink.localizedDescription.contains("pawn sheet request"))
        #expect(PawnSheetRequestError.unreadable.localizedDescription.contains("can't be read"))
        #expect(PawnSheetRequestError.newerFormat(7).localizedDescription.contains("newer format (7)"))
    }

    #if os(macOS)
    @MainActor @Test func theMacAsksWhetherALinkOpens() throws {
        let launcher = WorkspaceLauncher()
        // Without a desktop session, as on the CI runner, nothing is certain to open a web link.
        if CGSessionCopyCurrentDictionary() != nil {
            #expect(launcher.canOpen(try link("https://example.com")))
        }
        #expect(!launcher.canOpen(try link("tableside-nothing-takes-this-\(UUID().uuidString.lowercased())://x")))
    }
    #endif
}
