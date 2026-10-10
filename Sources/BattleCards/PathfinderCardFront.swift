import Bestiary
import SwiftUI

private let ink = Color(hex: 0x2B1D10)

/// A Pathfinder card's front: parchment in a stone frame, the level on a heraldic shield, gold rules between the
/// sections, and for an elite a thin gold frame inside the stone one.
struct PathfinderCardFront: View {
    let content: CardContent
    var textSize: CGFloat = 15
    var scrolls = true
    @Environment(\.cardArt) private var art

    var body: some View {
        Scrollable(scrolls: scrolls) {
            VStack(alignment: .leading, spacing: 4) {
                header
                TraitChips(traits: content.traits, links: content.links, game: .pathfinder, style: style)
                lines(content.hazard)
                lines(content.senses + content.statistics + content.interaction)
                goldRule
                lines(content.defense)
                if !content.hitPoints.isEmpty { CardLineView(line: CardLine(content.hitPoints), style: style) }
                lines(content.defensive)
                goldRule
                lines(content.offense + content.offensive)
                SourceLine(text: content.source, color: ink.opacity(0.55))
            }
            .padding(.horizontal, 34)
            .padding(.vertical, 30)
        }
        .background { parchment }
        .cardPiece(art.image("front-frame"), capInsets: EdgeInsets(top: 60, leading: 60, bottom: 60, trailing: 60))
        .overlay {
            if art.image("front-frame") == nil { RoundedRectangle(cornerRadius: 10).strokeBorder(ink, lineWidth: 6) }
        }
        .overlay { eliteFrame }
    }

    @ViewBuilder
    private var parchment: some View {
        if let piece = art.image("parchment") {
            piece.resizable()
        } else {
            LinearGradient(colors: [Color(hex: 0xF4E8CC), Color(hex: 0xE6D2A6)], startPoint: .top, endPoint: .bottom)
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(content.name.uppercased())
                .font(.custom(FontName.condensedBold, size: textSize * 1.9))
                .foregroundStyle(ink)
            Spacer(minLength: 8)
            TemplateBadge(template: content.template, color: Color(hex: 0x6B1A12))
            LevelShield(level: content.levelNumber, shield: art.image("level-shield"), size: textSize * 4)
        }
    }

    @ViewBuilder
    private var eliteFrame: some View {
        if content.template == .elite {
            if let frame = art.image("elite-frame", scale: 3) {
                frame.resizable(capInsets: EdgeInsets(top: 66, leading: 66, bottom: 66, trailing: 66),
                                resizingMode: .stretch)
                    .padding(12)
            } else {
                RoundedRectangle(cornerRadius: 6).strokeBorder(Color(hex: 0xB8862E), lineWidth: 3).padding(14)
            }
        }
    }

    @ViewBuilder
    private var goldRule: some View {
        if let rule = art.image("gold-rule") {
            rule.resizable().frame(height: 6).padding(.vertical, 3)
        } else {
            Rectangle().fill(Color(hex: 0x8A6420)).frame(height: 2).padding(.vertical, 4)
        }
    }

    private func lines(_ lines: [CardLine]) -> some View {
        ForEach(lines) { CardLineView(line: $0, style: style) }
    }

    private var style: CardTextStyle {
        CardTextStyle(body: FontName.condensed, bold: FontName.condensedBold, italic: FontName.condensedItalic,
                      size: textSize, ink: ink, paper: Color(hex: 0xF0DDB4),
                      worse: Color(hex: 0xB00020), better: Color(hex: 0x1B6E20))
    }
}

/// The level in large type over a heraldic shield, or a dark disc without one.
struct LevelShield: View {
    let level: String
    let shield: Image?
    let size: CGFloat

    var body: some View {
        Group {
            if let shield {
                shield.resizable().scaledToFit()
            } else {
                Circle().fill(Color(hex: 0x6B1A12))
            }
        }
        .frame(width: size, height: size)
        .overlay {
            Text(level)
                .font(.custom(FontName.condensedBold, size: size * 0.42))
                .foregroundStyle(.white)
                .shadow(color: .black, radius: 2)
                .offset(y: -size * 0.04)
        }
    }
}

extension CardContent {
    /// The level alone: "4" of "CREATURE 4".
    var levelNumber: String {
        levelLabel.split(separator: " ").last.map(String.init) ?? levelLabel
    }
}
