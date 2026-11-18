import ArtExtraction
import ArtExtractionTestSupport
import Foundation
@testable import SharedLibraries
import Testing

/// Which picture art keeps when two devices have different ones (library sync design, "Pictures").
@Suite struct SyncPictureSizeTests {
    let devices: SyncedDevices

    init() throws {
        devices = try SyncedDevices()
    }

    var first: SharedLibrary { devices.firstLibrary }
    var second: SharedLibrary { devices.secondLibrary }

    /// The ogre printed as a pawn and on a Battle Card, with `picture`.
    func addOgre(to library: SharedLibrary, picture: ArtPicture?) throws {
        try library.write { writer in
            try SyncFixture.addSource("pawns", to: writer)
            try SyncFixture.addSource("cards", to: writer)
            var entry = SyncFixture.entry([.init(.pawn, SyncFixture.pawnKey, "pawns"),
                                           .init(.figure, SyncFixture.figureKey, "cards")])
            entry.artPicture = picture
            try writer.merge(entry)
        }
    }

    func picture(in library: SharedLibrary) throws -> ArtPicture? {
        try library.artEntries().first?.artPicture
    }

    @Test func keepsTheSharperPictureWhenEachDeviceAppliesTheOthersRecordsAtOnce() throws {
        let sharp = ArtPicture(name: "sharp.heic", pixels: 1_024)
        try addOgre(to: first, picture: ArtPicture(name: "blurry.heic", pixels: 512))
        try addOgre(to: second, picture: sharp)
        let fromFirst = try first.sendEverything(), fromSecond = try second.sendEverything()

        try first.applyRemote(fromSecond)
        try second.applyRemote(fromFirst)
        #expect(try picture(in: first) == sharp)
        #expect(try picture(in: second) == sharp)
    }

    @Test func keepsThePictureWhoseNameSortsFirstOfTwoAsSharp() throws {
        try addOgre(to: first, picture: ArtPicture(name: "b.heic", pixels: 800))
        try addOgre(to: second, picture: ArtPicture(name: "a.heic", pixels: 800))

        try devices.exchange()
        #expect(try picture(in: first) == ArtPicture(name: "a.heic", pixels: 800))
        #expect(try picture(in: second) == ArtPicture(name: "a.heic", pixels: 800))
    }

    @Test func givesArtWithoutAPictureTheOtherDevices() throws {
        try addOgre(to: first, picture: nil)
        try addOgre(to: second, picture: ArtPicture(name: "only.heic", pixels: 0))

        try devices.exchange()
        #expect(try picture(in: first) == ArtPicture(name: "only.heic", pixels: 0))
    }

    @Test func takesAPicturesKnownSizeOverAnUnknownOne() throws {
        try addOgre(to: first, picture: ArtPicture(name: "same.heic", pixels: 0))
        try addOgre(to: second, picture: ArtPicture(name: "same.heic", pixels: 640))

        try devices.exchange()
        #expect(try picture(in: first) == ArtPicture(name: "same.heic", pixels: 640))
    }

    @Test func keepsAPawnsSharperPictureWhenItsBattleCardIsRead() throws {
        let device = devices.first
        let goblin = DrawnPawn(rect: device.goblin.rect, art: creatureArt(variant: 0, scale: 4),
                               name: "GOBLIN WARRIOR")
        try first.add(try device.pawnBox([goblin]), keeping: true)
        let sharp = try #require(try picture(in: first))
        try first.markPicturesUploaded([sharp.name])
        let deck = [DrawnCard(name: "GOBLIN WARRIOR", traits: "N SMALL GOBLIN HUMANOID",
                              creature: creatureArt(variant: 0))]

        try first.add(try writeCardDeck(deck, in: device.root), keeping: true)
        #expect(try first.artEntries().first?.prints.map(\.print.kind) == [.figure, .pawn])
        #expect(try picture(in: first) == sharp)
        #expect(try first.picturesToDelete().isEmpty)
    }
}
