import Bestiary
import CoreGraphics
import SwiftUI
import Testing
@testable import BattleCards

@Suite("Interactive cards")
@MainActor
struct InteractiveBattleCardTests {
    let size = CGSize(width: 300, height: 400)

    func render(_ view: some View) -> CGImage? {
        ImageRenderer(content: view.frame(width: size.width, height: size.height)).cgImage
    }

    @Test("Corners are the right fifth at the top and bottom", arguments: [
        (CGPoint(x: 290, y: 10), CardCorner?.some(.topTrailing)), (CGPoint(x: 240, y: 80), .topTrailing),
        (CGPoint(x: 295, y: 390), .bottomTrailing), (CGPoint(x: 240, y: 320), .bottomTrailing),
        (CGPoint(x: 239, y: 10), nil), (CGPoint(x: 290, y: 200), nil), (CGPoint(x: 10, y: 390), nil)
    ])
    func corners(location: CGPoint, corner: CardCorner?) {
        #expect(CardCorner(at: location, in: size) == corner)
    }

    @Test("Before the card is laid out, nothing is a corner")
    func noSize() {
        #expect(CardCorner(at: .zero, in: .zero) == nil)
    }

    @Test("A tap shows every icon; the pointer shows the icon of its corner")
    func controls() {
        var controls = CardControls(size: size)
        #expect(!controls.isShowing(.topTrailing))
        controls.hover(at: CGPoint(x: 290, y: 390))
        #expect(controls.isShowing(.bottomTrailing) && !controls.isShowing(.topTrailing))
        controls.hover(at: nil)
        #expect(!controls.isShowing(.bottomTrailing))
        controls.showsIcons = true
        #expect(controls.isShowing(.topTrailing) && controls.isShowing(.bottomTrailing))
    }

    @Test("A pinch past 1.2 opens full screen, under 0.8 closes it")
    func pinches() {
        #expect(CardPinch.opens(1.3) && !CardPinch.opens(1.2))
        #expect(CardPinch.closes(0.7) && !CardPinch.closes(0.8))
    }

    @Test("The full-screen icon opens or closes")
    func fullScreenActions() {
        var opened = false
        var closed = false
        let open = FullScreenAction.open { opened = true }
        let close = FullScreenAction.close { closed = true }
        open.perform()
        close.perform()
        #expect(opened && closed)
        #expect(open.systemImage == "arrow.up.left.and.arrow.down.right")
        #expect(close.systemImage == "arrow.down.right.and.arrow.up.left")
        #expect(close.label == "Exit Full Screen")
    }

    @Test("Cards with and without a back draw, inside a host and outside one")
    func draws() {
        let creature = Creature(key: "test.ogre", name: "Test Ogre", game: .pathfinder)
        let flippable = InteractiveBattleCard {
            BattleCard(creature: creature, scrolls: false)
        } back: {
            CardBack(name: creature.name, game: .pathfinder, traits: []) { ArtPicture(path: "ogre") }
        }
        let frontOnly = InteractiveBattleCard { BattleCard(creature: creature, scrolls: false) }
        #expect(render(flippable) != nil)
        #expect(render(frontOnly.battleCardFullScreenHost()) != nil)
    }

    @Test("Faces draw with their icons for each action")
    func faces() {
        for action in [FullScreenAction.open {}, .close {}] {
            let faces = CardFaces(front: Color.white, back: Color.black, hasBack: true,
                                  isFlipped: .constant(true), fullScreenAction: action,
                                  controls: CardControls(showsIcons: true))
            #expect(render(faces) != nil)
        }
    }

    @Test("Full screen fills the host's window, or covers the screen without a host")
    func fullScreen() async throws {
        let card = InteractiveBattleCard(front: Color.white, back: Color.black, hasBack: true, isFullScreen: true)
        let hosted = try await showInWindow(card.battleCardFullScreenHost())
        #expect(hosted.contentView != nil)
        let covered = try await showInWindow(card)
        #expect(covered.contentView != nil)
        var closed = false
        let faces = FullScreenCard(front: Color.white, back: Color.black, hasBack: false,
                                   isFlipped: .constant(false)) { closed = true }
        #expect(render(faces) != nil)
        #expect(!closed)
    }

    @Test("Art loads from the app's loader once the picture is on screen")
    func loadsArt() async throws {
        let picture = ArtPicture(path: "ogre")
            .environment(\.artPictureLoader, ArtPictureLoader { $0 == "ogre" ? squareImage(side: 4) : nil })
        let window = try await showInWindow(picture)
        #expect(window.contentView != nil)
        let missing = try await showInWindow(ArtPicture(path: "missing"))
        #expect(missing.contentView != nil)
    }

    @Test("Without a loader there's no art")
    func noLoader() async {
        #expect(await ArtPictureLoader.none.load("anything") == nil)
        let loader = ArtPictureLoader { $0 == "ogre" ? squareImage(side: 4) : nil }
        #expect(await loader.load("ogre") != nil)
    }
}
