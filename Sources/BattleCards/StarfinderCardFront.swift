import Bestiary
import SwiftUI

let starfinderCyan = Color(hex: 0x3FD4F0)
let starfinderSteel = Color(hex: 0xC9D3D8)

/// A Starfinder card's front: a dark panel in steel corner brackets, the name on a cyan bar, the level in a bronze
/// hexagon, and cyan section headings.
struct StarfinderCardFront: View {
    let content: CardContent
    var textSize: CGFloat = 15
    var scrolls = true
    @Environment(\.cardArt) private var art

    var body: some View {
        Scrollable(scrolls: scrolls) {
            VStack(alignment: .leading, spacing: 4) {
                header
                TraitChips(traits: content.traits, links: content.links, game: .starfinder, style: style)
                ConditionTags(conditions: content.conditions, style: style)
                lines(content.hazard)
                lines(content.senses)
                section("DEFENSE", (content.hitPoints.isEmpty ? [] : [CardLine(content.hitPoints)])
                        + content.defense + content.defensive)
                section("OFFENSE", content.offense + content.offensive)
                section("STATISTICS", content.statistics)
                section("SPECIAL ABILITIES", content.interaction)
                SourceLine(text: content.source, color: starfinderSteel.opacity(0.6))
            }
            .padding(.horizontal, 30)
            .padding(.vertical, 28)
        }
        .background { panel }
        .overlay { CornerBrackets(size: 56) }
    }

    @ViewBuilder
    private var panel: some View {
        if let piece = art.image("panel") {
            piece.resizable()
        } else {
            Color(hex: 0x1C2326)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text(content.name.uppercased())
                .font(.custom(FontName.condensedBold, size: textSize * 1.7))
                .foregroundStyle(Color(hex: 0x06222B))
                .padding(.horizontal, 18)
                .frame(maxWidth: .infinity, minHeight: textSize * 3, alignment: .leading)
                .background { nameBar }
            TemplateBadge(template: content.template, color: Color(hex: 0x0B6E85))
            levelHexagon
        }
    }

    @ViewBuilder
    private var nameBar: some View {
        if let piece = art.image("name-bar") {
            piece.resizable()
        } else {
            Capsule().fill(starfinderCyan)
        }
    }

    private var levelHexagon: some View {
        Group {
            if let piece = art.image("level-hexagon") {
                piece.resizable().scaledToFit()
            } else {
                Hexagon().stroke(Color(hex: 0xB08A4A), lineWidth: 4)
            }
        }
        .frame(width: textSize * 3.6, height: textSize * 3.6)
        .overlay {
            Text(content.levelNumber)
                .font(.custom(FontName.condensedBold, size: textSize * 1.6))
                .foregroundStyle(starfinderSteel)
        }
    }

    @ViewBuilder
    private func section(_ title: String, _ lines: [CardLine]) -> some View {
        if !lines.isEmpty {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.custom(FontName.condensedBold, size: textSize * 1.1))
                    .foregroundStyle(starfinderCyan)
                Rectangle().fill(starfinderCyan.opacity(0.6)).frame(height: 1)
                ForEach(lines) { CardLineView(line: $0, style: style) }
            }
            .padding(.top, 4)
        }
    }

    private func lines(_ lines: [CardLine]) -> some View {
        ForEach(lines) { CardLineView(line: $0, style: style) }
    }

    private var style: CardTextStyle {
        CardTextStyle(body: FontName.condensed, bold: FontName.condensedBold, italic: FontName.condensedItalic,
                      size: textSize, ink: Color(hex: 0xE6EEF1), paper: Color(hex: 0x1C2326),
                      worse: Color(hex: 0xFF6B6B), better: Color(hex: 0x7CE38B))
    }
}

/// Space Depot UI's four steel corner brackets; cyan corner strokes without them.
struct CornerBrackets: View {
    let size: CGFloat
    @Environment(\.cardArt) private var art

    var body: some View {
        ZStack {
            corner("corner-top-left", .topLeading)
            corner("corner-top-right", .topTrailing)
            corner("corner-bottom-left", .bottomLeading)
            corner("corner-bottom-right", .bottomTrailing)
        }
        .padding(6)
    }

    @ViewBuilder
    private func corner(_ name: String, _ alignment: Alignment) -> some View {
        Group {
            if let piece = art.image(name) {
                piece.resizable().scaledToFit()
            } else {
                Rectangle().fill(.clear).frame(height: size).overlay(alignment: alignment) {
                    Rectangle().stroke(starfinderCyan.opacity(0.7), lineWidth: 2)
                        .frame(width: size / 2, height: size / 2)
                }
            }
        }
        .frame(width: size)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
    }
}

/// A regular hexagon with flat top and bottom, filling its frame.
struct Hexagon: Shape {
    func path(in rect: CGRect) -> Path {
        let inset = rect.width / 4
        return Path { path in
            path.move(to: CGPoint(x: rect.minX + inset, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - inset, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX - inset, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX + inset, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
            path.closeSubpath()
        }
    }
}
