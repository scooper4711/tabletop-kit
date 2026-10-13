import CoreGraphics
import ImageIO
import SwiftUI

/// The UI art battle cards are drawn with: pieces of the Rexard packs the user owns, which each app copies into its
/// own folder at build time (`CardArtImport`), since the art may not be published. A missing piece is drawn as plain
/// color instead.
public struct CardArtPieces: Sendable {
    /// One piece: its name in the folder, and where it is among the user's packs.
    public struct Piece: Sendable, Equatable {
        public let name: String
        /// The file's path inside the folder of Rexard packs, as Humble Bundle's downloads unpack.
        public let packPath: String
    }

    /// Every piece the cards use.
    public static let manifest: [Piece] = [
        // Pathfinder fronts: Fantasy GUI's parchment and frames, Heroic UI's gold, a Shields Badges shield.
        Piece(name: "parchment", packPath: "fantasygui/fantasy_gui_png/bg_01.png"),
        Piece(name: "front-frame", packPath: "fantasygui/fantasy_gui_png/slot_04.png"),
        Piece(name: "back-frame", packPath: "fantasygui/fantasy_gui_png/slot_03.png"),
        Piece(name: "name-ribbon", packPath: "fantasygui/fantasy_gui_png/text_bg_03.png"),
        Piece(name: "gold-rule", packPath: "heroicui/Heroic_UI_png/el_28_01.png"),
        Piece(name: "elite-frame", packPath: "heroicui/Heroic_UI_png/el_29.png"),
        Piece(name: "level-shield", packPath: "shieldsbadges/ShieldsBadges_png/ShieldsBadges_04_a.png"),
        // Pathfinder backs: Legendary Battlegrounds' landscapes.
        Piece(name: "backdrop-lava", packPath: "legendarybattlegrounds/LegendaryBattlegrounds_bg/bg_01.png"),
        Piece(name: "backdrop-ruins", packPath: "legendarybattlegrounds/LegendaryBattlegrounds_bg/bg_02.png"),
        Piece(name: "backdrop-canyon", packPath: "legendarybattlegrounds/LegendaryBattlegrounds_bg/bg_03.png"),
        Piece(name: "backdrop-meadow", packPath: "legendarybattlegrounds/LegendaryBattlegrounds_bg/bg_04.png"),
        Piece(name: "backdrop-snow", packPath: "legendarybattlegrounds/LegendaryBattlegrounds_bg/bg_05.png"),
        // Starfinder: Space Depot UI.
        Piece(name: "panel", packPath: "spacedepotui/SpaceDepotUI_png/bg.png"),
        Piece(name: "space-texture", packPath: "spacedepotui/SpaceDepotUI_png/bg_big.png"),
        Piece(name: "corner-top-left", packPath: "spacedepotui/SpaceDepotUI_png/frame_01_03.png"),
        Piece(name: "corner-top-right", packPath: "spacedepotui/SpaceDepotUI_png/frame_01_04.png"),
        Piece(name: "corner-bottom-left", packPath: "spacedepotui/SpaceDepotUI_png/frame_01_05.png"),
        Piece(name: "corner-bottom-right", packPath: "spacedepotui/SpaceDepotUI_png/frame_01_06.png"),
        Piece(name: "name-bar", packPath: "spacedepotui/SpaceDepotUI_png/button_01_04.png"),
        Piece(name: "level-hexagon", packPath: "spacedepotui/SpaceDepotUI_png/ava_04_04.png")
    ]

    /// The folder holding the pieces as `<name>.png`; nil when there is none, so every card is drawn plainly.
    public let folder: URL?

    public init(folder: URL?) {
        self.folder = folder
    }

    /// A piece's image; nil when it is missing. A scale above 1 draws it smaller, shrinking a stretched frame's
    /// corners.
    public func image(_ name: String, scale: CGFloat = 1) -> Image? {
        guard let url = folder?.appendingPathComponent(name + ".png"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        return Image(decorative: image, scale: scale)
    }
}

private struct CardArtPiecesKey: EnvironmentKey {
    static let defaultValue = CardArtPieces(folder: nil)
}

extension EnvironmentValues {
    /// The UI art the cards are drawn with.
    public var cardArt: CardArtPieces {
        get { self[CardArtPiecesKey.self] }
        set { self[CardArtPiecesKey.self] = newValue }
    }
}

extension View {
    /// Draws a piece over the view's whole area, stretched, or nothing when it is missing.
    func cardPiece(_ piece: Image?, capInsets: EdgeInsets? = nil) -> some View {
        overlay {
            Group {
                if let piece {
                    if let capInsets {
                        piece.resizable(capInsets: capInsets, resizingMode: .stretch)
                    } else {
                        piece.resizable()
                    }
                }
            }
            // The piece covers the card, so taps go through it to the links and tags underneath.
            .allowsHitTesting(false)
        }
    }
}
