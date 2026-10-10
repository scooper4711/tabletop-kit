import Bestiary
import SwiftUI

/// "ELITE" or "WEAK" next to the level, when a template applies.
struct TemplateBadge: View {
    let template: CreatureTemplate
    let color: Color

    var body: some View {
        if template != .normal {
            Text(template.rawValue.uppercased())
                .font(.custom(FontName.condensedBold, size: 12))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(template == .elite ? color : Color(hex: 0x4A5A6A), in: Capsule())
        }
    }
}

/// The book a creature comes from, small and quiet at the foot of the card.
struct SourceLine: View {
    let text: String
    let color: Color

    var body: some View {
        if !text.isEmpty {
            Text(text)
                .font(.custom(FontName.condensedItalic, size: 11))
                .foregroundStyle(color)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.top, 6)
        }
    }
}

extension Color {
    /// A color from a hex value such as 0x2B1D10, in sRGB.
    public init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: opacity)
    }
}
