import Bestiary
import Foundation

/// Converts Foundry description HTML, enrichers included, into `RulesText`.
public struct RulesTextConverter {
    private var enrichers: EnricherConverter

    public init(localizer: Localizer) {
        self.init(localizer: localizer, links: LinkResolver())
    }

    init(localizer: Localizer, links: LinkResolver) {
        enrichers = EnricherConverter(localizer: localizer, links: links)
    }

    /// Where links in the text lead.
    var links: LinkResolver { enrichers.links }

    /// Enricher names that could not be converted so far, for the import report.
    public var unparsedEnrichers: [String] { enrichers.unparsed }

    /// The text as `RulesText`, with formulas worked out from `values` (R4.4).
    public mutating func convert(_ html: String, values: FormulaValues = FormulaValues()) -> RulesText {
        guard !html.isEmpty else { return RulesText() }
        return RulesText(HTMLFlattener.markup(from: enrichers.convert(html, values: values)))
    }
}
