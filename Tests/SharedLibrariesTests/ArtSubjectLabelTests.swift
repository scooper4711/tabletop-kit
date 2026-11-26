import Foundation
@testable import SharedLibraries
import Testing

/// The name saved with pasted art, and the ID of a creature's pawn (shared libraries R4.11, R4.12).
@Suite struct ArtSubjectLabelTests {
    private func record(_ json: String) -> Data { Data(json.utf8) }

    @Test func readsTheNameAndSizeFromAnAppsRecord() {
        let saved = record(#"{"byteCount":12,"fileName":"a.png","subject":"pf2e.x.y","subjectName":"Rimesnap","#
            + #""subjectSize":"tiny"}"#)
        #expect(ArtSubjectLabel(record: saved) == ArtSubjectLabel(name: "Rimesnap", size: .tiny))
    }

    @Test func aRecordEncodedFromTheLabelReadsBack() throws {
        let label = ArtSubjectLabel(name: "Matriarch Szvetneera", size: .medium)
        #expect(ArtSubjectLabel(record: try JSONEncoder().encode(label)) == label)
        let sizeless = ArtSubjectLabel(name: "Zombie Crow Swarm", size: nil)
        #expect(ArtSubjectLabel(record: try JSONEncoder().encode(sizeless)) == sizeless)
    }

    @Test func aSizeThatIsNotOneOfTheSixReadsAsNone() {
        let saved = record(#"{"subjectName":"Rimesnap","subjectSize":"colossal"}"#)
        #expect(ArtSubjectLabel(record: saved) == ArtSubjectLabel(name: "Rimesnap", size: nil))
    }

    @Test(arguments: ["", "not json", "[]", #"{"subject":"pf2e.x.y","fileName":"a.png"}"#,
                      #"{"subjectName":"  ","subjectSize":"small"}"#, #"{"subjectName":7}"#])
    func aRecordNamingNoCreatureHasNoLabel(json: String) {
        #expect(ArtSubjectLabel(record: record(json)) == nil)
    }

    @Test func theNameLosesTheSpaceAroundIt() {
        #expect(ArtSubjectLabel(record: record(#"{"subjectName":" Ulfen Bodyguard\n"}"#))?.subjectName
            == "Ulfen Bodyguard")
    }

    @Test func anArtRowGivesItsLabel() {
        let labeled = CustomArtRecord(id: UUID(), fileName: "a.png", sharedVersion: nil,
                                      record: record(#"{"subjectName":"Rimesnap","subjectSize":"tiny"}"#))
        let bare = CustomArtRecord(id: UUID(), fileName: "b.png", sharedVersion: nil, record: Data())
        #expect(labeled.subjectLabel == ArtSubjectLabel(name: "Rimesnap", size: .tiny))
        #expect(bare.subjectLabel == nil)
    }

    @Test func aCustomCreaturesPawnHasTheCreaturesID() throws {
        let id = try #require(UUID(uuidString: "11C837C3-112E-4885-8195-5C797CF8C013"))
        #expect(SharedLibrary.pawnID(forSubject: "custom.\(id.uuidString)") == id)
        #expect(SharedLibrary.pawnID(forSubject: "custom.\(id.uuidString.lowercased())") == id)
    }

    @Test func anotherCreaturesPawnHasAnIDMadeFromItsKey() throws {
        let rimesnap = "pf2e.pfs-season-6-bestiary.GMKVSvtmRxBacSKH"
        let id = SharedLibrary.pawnID(forSubject: rimesnap)
        // The same on every device and in every version, so it is pinned here: a change would orphan the pawn's
        // entries on saved sheets.
        #expect(id.uuidString == "07CD1FD8-A3A1-57C3-8234-FB9D74772A84")
        #expect(id != SharedLibrary.pawnID(forSubject: "pf2e.pfs-season-6-bestiary.0GUp0mNrxqnnhZFP"))
        #expect(id != SharedLibrary.pawnID(forSubject: "custom.not-an-id"))
        #expect(SharedLibrary.pawnID(forSubject: "custom.not-an-id")
            == SharedLibrary.pawnID(forSubject: "custom.not-an-id"))
    }
}
