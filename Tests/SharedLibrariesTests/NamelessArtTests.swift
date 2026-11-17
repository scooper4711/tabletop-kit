import ArtExtraction
import ArtExtractionTestSupport
import CoreGraphics
import Foundation
@testable import SharedLibraries
import Testing

/// Art printed without a name in the shared library (shared libraries R2.3a).
@Suite struct NamelessArtTests {
    static let heroesAndVillains = "Pathfinder Pawns- Heroes & Villains Pawn Collection PDF.pdf"
    static let heroesTitle = "Pathfinder Pawns: Heroes & Villains Pawn Collection"
    let folder = temporaryFolder()
    let goblinArt = artImage(variant: 0)
    let ogreArt = artImage(variant: 1)

    func library(_ app: TablesideApp = .pawnShop) throws -> SharedLibrary {
        try SharedLibrary(folder: folder.appending(path: "Tableside"), app: app)
    }

    func pawn(_ art: CGImage, _ name: String? = nil, at column: Int = 0) -> DrawnPawn {
        DrawnPawn(rect: CGRect(x: 20 + 100 * column, y: 600, width: 81, height: 138), art: art, name: name)
    }

    func pdf(_ pawns: [DrawnPawn], named name: String) throws -> URL {
        try writePawnPDF(pawns, named: name, in: folder)
    }

    @Test func keepsArtPrintedWithoutANameUnderAStandInName() throws {
        let library = try library()
        let report = try library.add(try pdf([pawn(goblinArt), pawn(ogreArt, at: 1)], named: Self.heroesAndVillains),
                                     keeping: true)
        #expect(report.added == 2 && report.needingNames == 2 && report.unnamed == 0)
        let entries = try library.artEntries()
        #expect(entries.count == 2)
        for entry in entries {
            #expect(entry.needsName && entry.name == "Unknown \(Self.heroesTitle)")
            #expect(entry.picture != nil)
        }
        let digests = try #require(entries.first?.fingerprint.imageDigests)
        let keys = Set(entries.map(\.id))
        #expect(keys.contains(ArtKey.nameBasedUUID("image:\(digests.joined(separator: ","))|")))
    }

    @Test func takesTheNameOfTheSamePictureFromAnotherProduct() throws {
        let library = try library()
        try library.add(try pdf([pawn(goblinArt, "GOBLIN WARRIOR")], named: "Pathfinder Bestiary Pawn Box PDF.pdf"),
                        keeping: true)
        let report = try library.add(try pdf([pawn(goblinArt), pawn(ogreArt, at: 1)], named: Self.heroesAndVillains),
                                     keeping: true)
        #expect(report.namedFromOtherProducts == 1 && report.needingNames == 1)
        let entries = try library.artEntries()
        let goblin = try #require(entries.first { $0.name == "Goblin Warrior" })
        #expect(!goblin.needsName && goblin.prints.count == 2)
        #expect(entries.filter(\.needsName).count == 1)
    }

    @Test func namesWaitingArtWhenANamedProductIsReadLater() throws {
        let library = try library()
        try library.add(try pdf([pawn(goblinArt)], named: Self.heroesAndVillains), keeping: true)
        let waitingID = try #require(try library.artEntries().first?.id)

        let report = try library.add(try pdf([pawn(goblinArt, "GOBLIN WARRIOR")],
                                             named: "Pathfinder Bestiary Pawn Box PDF.pdf"), keeping: true)
        #expect(report.alreadyKnown == 1 && report.added == 0)
        let goblin = try #require(try library.artEntries().first)
        #expect(try library.artEntries().count == 1)
        #expect(goblin.name == "Goblin Warrior" && !goblin.needsName && goblin.prints.count == 2)
        #expect(try library.artEntry(id: waitingID)?.id == goblin.id)
    }

    @Test func otherNamelessProductsJoinArtWaitingForAName() throws {
        let library = try library()
        try library.add(try pdf([pawn(goblinArt)], named: Self.heroesAndVillains), keeping: true)
        let report = try library.add(try pdf([pawn(goblinArt), pawn(ogreArt, at: 1)],
                                             named: "Pathfinder Unnamed Pawn Collection PDF.pdf"), keeping: true)
        #expect(report.alreadyKnown == 1 && report.added == 1 && report.namedFromOtherProducts == 0)
        let entries = try library.artEntries()
        #expect(entries.count == 2 && entries.allSatisfy(\.needsName))
        #expect(entries.contains { $0.name == "Unknown Pathfinder Unnamed Pawn Collection" })
    }

    @Test func otherNamelessProductsArentNamedFromOtherProducts() throws {
        let library = try library()
        try library.add(try pdf([pawn(goblinArt, "GOBLIN WARRIOR")], named: "Pathfinder Bestiary Pawn Box PDF.pdf"),
                        keeping: true)
        let report = try library.add(try pdf([pawn(goblinArt)], named: "Pathfinder Unnamed Pawn Collection PDF.pdf"),
                                     keeping: true)
        #expect(report.needingNames == 1 && report.namedFromOtherProducts == 0)
        #expect(try library.artEntries().count == 2)
    }

    @Test func aNameTheArtHasWinsOverAStandIn() throws {
        let library = try library()
        let key = UUID()
        func entry(_ name: String, needsName: Bool, keys: [UUID]) -> SharedArtEntry {
            let face = PawnFace(pageIndex: 0, rect: CGRect(x: 0, y: 0, width: 80, height: 130), rotation: 0)
            let art = ArtEntry(id: keys[0], name: name, game: .pathfinder, size: .medium, traits: [],
                               fingerprint: ArtFingerprint(imageDigests: ["ab"]),
                               prints: keys.map { _ in ArtPrint(sourceID: "pdf", kind: .pawn, face: face, copies: 1) },
                               palette: [])
            var shared = SharedArtEntry(art, keys: keys)
            shared.needsName = needsName
            return shared
        }
        try library.write { writer in try writer.merge(entry("Goblin", needsName: false, keys: [key])) }
        try library.write { writer in
            try writer.merge(entry("Unknown Heroes", needsName: true, keys: [key, UUID()]))
        }
        let merged = try #require(try library.artEntries().first)
        #expect(merged.name == "Goblin" && !merged.needsName)
    }
}

/// Telling art apart when naming it (shared libraries R2.3a).
@Suite struct NamingArtTests {
    let thumbnail = (0..<64).map { UInt8($0 * 3) }

    @Test func theSameImagesAreTheSameArt() {
        let one = ArtFingerprint(imageDigests: ["a"]), other = ArtFingerprint(imageDigests: ["a"])
        #expect(one.isSameArt(as: other) && one.namingDistance(from: other) == 0)
        #expect(!one.isSameArt(as: ArtFingerprint(imageDigests: [])))
    }

    @Test func lookalikeThumbnailsAreTheSameArtOnlyWhenClose() {
        let one = ArtFingerprint(imageDigests: ["a"], thumbnail: thumbnail)
        let close = ArtFingerprint(imageDigests: ["b"], thumbnail: thumbnail)
        let far = ArtFingerprint(imageDigests: ["c"], thumbnail: thumbnail.reversed())
        #expect(one.isSameArt(as: close) && one.namingDistance(from: close) < 1)
        #expect(!one.isSameArt(as: far))
    }

    @Test func namesProductsThatPrintNoNames() {
        #expect(NamelessProducts.contains(title: "Pathfinder Pawns: Heroes & Villains Pawn Collection"))
        #expect(!NamelessProducts.contains(title: "Pathfinder Bestiary Pawn Box"))
        #expect(NamelessProducts.standInName(forTitle: "Pawns") == "Unknown Pawns")
    }
}
