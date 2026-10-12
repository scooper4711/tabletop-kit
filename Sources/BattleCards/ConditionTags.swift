import Bestiary
import SwiftUI

/// The creature's conditions as colored tags under its traits. A tag opens the condition's rules text.
struct ConditionTags: View {
    let conditions: [AppliedCondition]
    let style: CardTextStyle

    var body: some View {
        if !conditions.isEmpty {
            FlowLayout(spacing: 3) {
                ForEach(conditions) { ConditionTag(condition: $0, style: style) }
            }
        }
    }
}

/// A condition tag, a button when the bestiary defines the condition.
private struct ConditionTag: View {
    let condition: AppliedCondition
    let style: CardTextStyle
    @Environment(\.glossary) private var glossary
    @State private var shownEntry: GlossaryEntry?

    var body: some View {
        if let entry = glossary.conditionEntry(condition.slug) {
            Button { shownEntry = entry } label: { label }
                .buttonStyle(.plain)
                .popover(item: $shownEntry) { entry in
                    GlossaryPopover(entry: entry, style: style).environment(\.glossary, glossary.deeper)
                }
        } else {
            label
        }
    }

    private var label: some View {
        Text(ConditionLabel.short(condition))
            .font(.custom(FontName.condensedBold, size: 11))
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(ConditionLabel.color(condition), in: Capsule())
            .overlay { Capsule().strokeBorder(.white.opacity(0.5), lineWidth: 0.5) }
    }
}

/// How a condition reads and is colored on cards and on Combat Pad's strips.
public enum ConditionLabel {
    /// "Frightened 2", "Bleed 1d6", or a custom reminder's text.
    public static func short(_ condition: AppliedCondition) -> String {
        if let damage = condition.persistentDamage { return "\(damage.type.capitalized) \(damage.formula)" }
        if condition.slug == ConditionSlug.customReminder { return "⏰ " + condition.note }
        let name = condition.slug.replacingOccurrences(of: "-", with: " ").capitalized
        return condition.value.map { "\(name) \($0)" } ?? name
    }

    /// Penalties red, losing actions purple, good things green, the rest gray.
    public static func color(_ condition: AppliedCondition) -> Color {
        switch condition.slug {
        case "frightened", "sickened", "clumsy", "enfeebled", "drained", "stupefied", "off-guard", "fatigued":
            return Color(hex: 0x8E1B1B)
        case "slowed", "stunned", "paralyzed", "restrained", "grabbed", "immobilized", "prone":
            return Color(hex: 0x5B2A86)
        case "quickened", "hidden", "invisible", "concealed":
            return Color(hex: 0x1F6E3A)
        case "dying", "unconscious", "persistent-damage", "doomed", "wounded":
            return .black
        default:
            return Color(hex: 0x4A4A4A)
        }
    }
}

extension GlossaryContext {
    /// A condition's rules text as a glossary entry, while popovers may open.
    func conditionEntry(_ slug: String) -> GlossaryEntry? {
        guard depth < Self.maximumDepth, let condition = bestiary.condition(slug) else { return nil }
        return GlossaryEntry(id: "condition.\(slug)", name: condition.name, category: "Condition", text: condition.text)
    }
}
