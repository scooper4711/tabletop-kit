import CoreGraphics
import Foundation
import Testing
@testable import ArtExtraction

@Suite struct ArtKeyTests {
    let bestiary = String(repeating: "b", count: 64)
    let adventure = String(repeating: "a", count: 64)

    @Test func makesVersion5UUIDsAsRFC9562Does() throws {
        let dns = try #require(UUID(uuidString: "6BA7B810-9DAD-11D1-80B4-00C04FD430C8"))
        #expect(ArtKey.nameBasedUUID("www.example.com", namespace: dns).uuidString
            == "2ED6657D-E927-568B-95E1-2665A8AEA6A2")
    }

    @Test func hashesThePicturesAndTheFoldedName() {
        let goblin = print("Goblin Warrior", digests: ["ff", "0a"])
        #expect(ArtKey.keyNames(for: [goblin]) == ["image:0a,ff|goblinwarrior"])
        #expect(ArtKey.keys(for: [goblin]) == [ArtKey.nameBasedUUID("image:0a,ff|goblinwarrior")])
    }

    @Test func foldsCaseAccentsSpacesAndPunctuation() {
        #expect(ArtKey.foldedName("Demon, Brimorak") == ArtKey.foldedName("Demon,brimorak"))
        #expect(ArtKey.foldedName("Élémental, Huge Air") == "elementalhugeair")
    }

    @Test func givesReprintsUnderTheSameNameTheSameKey() {
        let keys = ArtKey.keys(for: [print("Goblin", source: bestiary, at: 10),
                                     print("goblin", source: adventure, size: .large, at: 300)])
        #expect(keys[0] == keys[1])
    }

    @Test func keepsApartNamesThatSharePicturesWithinAndAcrossProducts() {
        let keys = ArtKey.keys(for: [print("Mantis, Deadly", source: bestiary),
                                     print("Mantis, Giant", source: bestiary),
                                     print("Drone 1", source: adventure), print("Drone 2", source: adventure),
                                     print("Bloodmaw", source: adventure)])
        #expect(Set(keys).count == 5)
    }

    @Test func addsTheSizeWhereOneProductPrintsAPictureAndNameInTwoSizes() {
        let prints = [print("Air Elemental", source: bestiary, size: .large),
                      print("Air Elemental", source: bestiary, size: .huge),
                      print("Air Elemental", source: adventure, size: .large)]
        let names = ArtKey.keyNames(for: prints)
        #expect(names[0].hasSuffix("|large") && names[1].hasSuffix("|huge"))
        #expect(names[2] == "image:aa|airelemental")
    }

    @Test func givesCopiesOfOnePrintOneKey() {
        let keys = ArtKey.keys(for: [print("Goblin", at: 10), print("Goblin", at: 200)])
        #expect(keys[0] == keys[1])
    }

    @Test func keysArtWithoutPicturesByItsPlace() {
        let prints = [print("Amiri", digests: [], at: 100), print("Amiri", digests: [], at: 105),
                      print("Amiri", digests: [], page: 3, at: 100)]
        let names = ArtKey.keyNames(for: prints)
        #expect(names[0] == "place:\(bestiary)|0|3,4")
        #expect(names[1] == "place:\(bestiary)|0|4,4")
        #expect(names[2] == "place:\(bestiary)|3|3,4")
    }

    @Test func keepsAPlaceWhenADetectorMovesTheFaceALittle() {
        let names = ArtKey.keyNames(for: [print("Amiri", digests: [], at: 92)])
            + ArtKey.keyNames(for: [print("Amiri", digests: [], at: 98)])
        #expect(names[0] == names[1])
    }

    @Test func numbersSharedPlacesInReadingOrder() {
        let lower = face(CGRect(x: 88, y: 100, width: 10, height: 10))
        let upper = face(CGRect(x: 88, y: 104, width: 10, height: 10))
        let left = face(CGRect(x: 84, y: 104, width: 10, height: 10))
        let names = ArtKey.keyNames(for: [placed(lower), placed(upper), placed(left), placed(left)])
        #expect(names == ["place:\(bestiary)|0|3,4#4", "place:\(bestiary)|0|3,4#3",
                          "place:\(bestiary)|0|3,4", "place:\(bestiary)|0|3,4#2"])
    }

    @Test func choosesThePawnsKeyForAnEntry() throws {
        let figure = ArtKey.nameBasedUUID("figure"), pawn = ArtKey.nameBasedUUID("pawn")
        let token = ArtKey.nameBasedUUID("token"), item = ArtKey.nameBasedUUID("item")
        #expect(ArtKey.entryID(among: [(.figure, figure), (.item, item), (.token, token), (.pawn, pawn)]) == pawn)
        #expect(ArtKey.entryID(among: [(.item, item), (.figure, figure)]) == figure)
        #expect(ArtKey.entryID(among: [(.token, token)]) == token)
        #expect(ArtKey.entryID(among: []) == nil)
        let first = try #require([pawn, token].min { $0.uuidString < $1.uuidString })
        #expect(ArtKey.entryID(among: [(.pawn, pawn), (.pawn, token)]) == first)
    }

    // MARK: Helpers

    private func print(_ name: String, digests: [String] = ["aa"], source: String? = nil, size: PawnSize = .medium,
                       page: Int = 0, at minX: CGFloat = 10) -> ArtKeyInput {
        ArtKeyInput(sourceID: source ?? bestiary, name: name, size: size,
                    fingerprint: ArtFingerprint(imageDigests: digests),
                    face: PawnFace(pageIndex: page, rect: CGRect(x: minX - 5, y: 115, width: 10, height: 20),
                                   rotation: 0))
    }

    private func face(_ rect: CGRect) -> PawnFace { PawnFace(pageIndex: 0, rect: rect, rotation: 0) }

    private func placed(_ face: PawnFace) -> ArtKeyInput {
        ArtKeyInput(sourceID: bestiary, name: "Amiri", size: .medium, fingerprint: ArtFingerprint(imageDigests: []),
                    face: face)
    }
}

@Suite struct ArtReferenceTests {
    @Test func saysWhatIsMissing() {
        let goblin = ArtReference(id: UUID(), name: "Goblin Warrior", product: "Monster Core Pawn Box")
        #expect(goblin.missingDescription == "Goblin Warrior, from Monster Core Pawn Box")
        #expect(ArtReference(id: UUID(), name: "Goblin", product: "").missingDescription == "Goblin")
    }

    @Test func roundTripsThroughJSON() throws {
        let reference = ArtReference(id: UUID(), name: "Goblin", product: "Bestiary Pawn Box")
        let decoded = try JSONDecoder().decode(ArtReference.self, from: JSONEncoder().encode(reference))
        #expect(decoded == reference)
    }
}
