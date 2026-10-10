import Bestiary
import SwiftUI

/// A creature's battle card in its game's look, with the template and conditions applied. Its UI art comes from
/// the `cardArt` environment value, its links from `glossary`.
public struct BattleCard: View {
    let creature: Creature
    let template: CreatureTemplate
    let conditions: [AppliedCondition]
    let textSize: CGFloat
    /// Off for snapshots, which need the whole card laid out at once.
    let scrolls: Bool

    @Environment(\.glossary) private var glossary

    public init(creature: Creature, template: CreatureTemplate = .normal, conditions: [AppliedCondition] = [],
                textSize: CGFloat = 15, scrolls: Bool = true) {
        self.creature = creature
        self.template = template
        self.conditions = conditions
        self.textSize = textSize
        self.scrolls = scrolls
    }

    public var body: some View {
        let presenter = StatBlockPresenter(creature: creature, template: template, conditions: conditions)
        let content = CardContent(presenter: presenter)
        Group {
            if creature.game == .starfinder {
                StarfinderCardFront(content: content, textSize: textSize, scrolls: scrolls)
            } else {
                PathfinderCardFront(content: content, textSize: textSize, scrolls: scrolls)
            }
        }
        .environment(\.glossary, cardGlossary(presenter))
    }

    private func cardGlossary(_ presenter: StatBlockPresenter) -> GlossaryContext {
        var context = glossary
        context.presenter = presenter
        return context
    }
}

/// Wraps content in a scroll view, or not.
struct Scrollable<Content: View>: View {
    let scrolls: Bool
    @ViewBuilder let content: Content

    var body: some View {
        if scrolls {
            ScrollView { content }
        } else {
            content
        }
    }
}
