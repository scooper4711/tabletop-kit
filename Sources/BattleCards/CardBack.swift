import Bestiary
import SwiftUI

/// What the players see of a creature: its art in a card back of the game's look, with its name. The app supplies
/// the art, from the user's own PDFs.
public struct CardBack<Art: View>: View {
    let name: String
    let game: Game
    let traits: [String]
    let art: Art

    public init(name: String, game: Game, traits: [String], @ViewBuilder art: () -> Art) {
        self.name = name
        self.game = game
        self.traits = traits
        self.art = art()
    }

    public var body: some View {
        Group {
            if game == .starfinder {
                StarfinderCardBack(name: name) { art }
            } else {
                PathfinderCardBack(name: name, backdrop: CardBackdrop(traits: traits)) { art }
            }
        }
        .aspectRatio(0.7, contentMode: .fit)
    }
}

/// The landscape behind a Pathfinder creature, by its traits: the first that applies.
enum CardBackdrop: String, CaseIterable {
    case ruins, lava, snow, canyon, meadow

    init(traits: [String]) {
        let traits = Set(traits.map { $0.lowercased() })
        let rules: [(Set<String>, CardBackdrop)] = [
            (["undead", "spirit", "ghost", "incorporeal"], .ruins),
            (["fiend", "fire", "demon", "devil", "daemon"], .lava),
            (["cold", "ice"], .snow),
            (["earth", "dragon", "giant"], .canyon)
        ]
        self = rules.first { !$0.0.isDisjoint(with: traits) }?.1 ?? .meadow
    }

    var pieceName: String { "backdrop-\(rawValue)" }

    /// A gradient of the landscape's colors, without the art.
    var colors: [Color] {
        switch self {
        case .ruins: [Color(hex: 0x3B4A63), Color(hex: 0x1C2333)]
        case .lava: [Color(hex: 0x8C2A14), Color(hex: 0x2B0F0A)]
        case .snow: [Color(hex: 0xC9DCEA), Color(hex: 0x6E8AA3)]
        case .canyon: [Color(hex: 0xC98B4A), Color(hex: 0x5A3A22)]
        case .meadow: [Color(hex: 0xA8D7E6), Color(hex: 0x5C8F3A)]
        }
    }
}

/// A Pathfinder back: the creature in a painted landscape, inside the stone frame, its name on a parchment ribbon.
struct PathfinderCardBack<Art: View>: View {
    let name: String
    let backdrop: CardBackdrop
    @ViewBuilder let art: Art
    @Environment(\.cardArt) private var pieces

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack {
                landscape.frame(width: width, height: geometry.size.height).clipped()
                LinearGradient(colors: [.clear, .black.opacity(0.4)], startPoint: .center, endPoint: .bottom)
                art.padding(.horizontal, width * 0.1).padding(.top, width * 0.1).padding(.bottom, width * 0.3)
                    .shadow(color: .black.opacity(0.6), radius: 14, y: 6)
                NameRibbon(name: name, width: width)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, width * 0.06)
            }
            .cardPiece(pieces.image("back-frame"),
                       capInsets: EdgeInsets(top: 60, leading: 60, bottom: 60, trailing: 60))
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private var landscape: some View {
        if let piece = pieces.image(backdrop.pieceName) {
            piece.resizable().scaledToFill()
        } else {
            LinearGradient(colors: backdrop.colors, startPoint: .top, endPoint: .bottom)
        }
    }
}

/// The creature's name on Fantasy GUI's ribbon. The ribbon's banner is its top 55% (rows 0–123 of 225), the
/// tails below, so the name is centered at 27% of its height.
struct NameRibbon: View {
    static let bannerCenter: CGFloat = 0.27
    let name: String
    let width: CGFloat
    @Environment(\.cardArt) private var pieces

    var body: some View {
        if let ribbon = pieces.image("name-ribbon") {
            ribbon.resizable().aspectRatio(1018 / 225, contentMode: .fit)
                .frame(width: width * 0.86)
                .overlay {
                    GeometryReader { geometry in
                        label.frame(width: geometry.size.width * 0.7)
                            .position(x: geometry.size.width / 2, y: geometry.size.height * Self.bannerCenter)
                    }
                }
        } else {
            label.padding(.horizontal, width * 0.08).padding(.vertical, width * 0.025)
                .background(Color(hex: 0xEBD8B0), in: Capsule())
        }
    }

    private var label: some View {
        Text(name.uppercased())
            .font(.custom(FontName.condensedBold, size: width * 0.062))
            .foregroundStyle(Color(hex: 0x2B1D10))
            .lineLimit(1)
            .minimumScaleFactor(0.5)
    }
}

/// A Starfinder back: the creature glowing on a dark texture inside steel corner brackets, its name on a terminal
/// plate: an elongated hexagon of near-black glass with scanlines, a cyan edge and glowing monospaced type.
struct StarfinderCardBack<Art: View>: View {
    let name: String
    @ViewBuilder let art: Art
    @Environment(\.cardArt) private var pieces

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack {
                texture.frame(width: width, height: geometry.size.height).clipped()
                RadialGradient(colors: [starfinderCyan.opacity(0.28), .clear], center: .center, startRadius: 10,
                               endRadius: width * 0.6)
                art.padding(.horizontal, width * 0.1).padding(.top, width * 0.14).padding(.bottom, width * 0.3)
                    .shadow(color: starfinderCyan.opacity(0.5), radius: 18)
                TerminalPlate(name: name, width: width)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, width * 0.1)
                CornerBrackets(size: width * 0.16)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private var texture: some View {
        if let piece = pieces.image("space-texture") {
            piece.resizable().scaledToFill()
        } else {
            LinearGradient(colors: [Color(hex: 0x1B2328), Color(hex: 0x07090B)], startPoint: .top, endPoint: .bottom)
        }
    }
}

/// The name on a terminal screen in the shape of an elongated hexagon.
struct TerminalPlate: View {
    let name: String
    let width: CGFloat

    var body: some View {
        Text(name.uppercased() + "_")
            .font(.system(size: width * 0.052, weight: .semibold, design: .monospaced))
            .kerning(width * 0.004)
            .foregroundStyle(starfinderCyan)
            .shadow(color: starfinderCyan, radius: 2)
            .shadow(color: starfinderCyan.opacity(0.8), radius: 6)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .padding(.horizontal, width * 0.1)
            .padding(.vertical, width * 0.035)
            .frame(maxWidth: width * 0.82)
            .background {
                ElongatedHexagon().fill(Color(hex: 0x061114).opacity(0.92))
                    .overlay { Scanlines().clipShape(ElongatedHexagon()) }
            }
            .overlay {
                ElongatedHexagon().stroke(starfinderCyan, lineWidth: max(1.5, width * 0.004))
                    .shadow(color: starfinderCyan, radius: width * 0.012)
            }
    }
}

/// A hexagon as wide as it needs to be, its left and right ends pointed at half its height.
struct ElongatedHexagon: Shape {
    func path(in rect: CGRect) -> Path {
        let point = rect.height / 2
        return Path { path in
            path.move(to: CGPoint(x: rect.minX + point, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - point, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX - point, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX + point, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
            path.closeSubpath()
        }
    }
}

/// Faint horizontal lines, as on an old screen.
struct Scanlines: View {
    var body: some View {
        Canvas { context, size in
            var line: CGFloat = 0
            while line < size.height {
                context.fill(Path(CGRect(x: 0, y: line, width: size.width, height: 1)),
                             with: .color(starfinderCyan.opacity(0.08)))
                line += 3
            }
        }
    }
}
