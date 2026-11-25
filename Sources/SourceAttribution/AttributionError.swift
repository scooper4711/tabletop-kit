import Foundation

/// Why the attribution notices couldn't be made. Every problem source is listed, not just the first.
public enum AttributionError: Error, Equatable, CustomStringConvertible {
    /// A source the import used can't be attributed: unknown, missing facts, or covered by neither license.
    public struct Problem: Hashable, Sendable {
        public let title: String
        public let reason: String
    }

    case unattributedSources([Problem])
    case duplicateTitles([String])
    case unreadableCatalog(String, String)
    case malformedTally(line: Int, String)

    public var description: String {
        switch self {
        case .unattributedSources(let problems):
            let lines = problems.map { "  \($0.title): \($0.reason)" }.joined(separator: "\n")
            return "Writing the attribution notices failed: \(problems.count) sources can't be attributed. " +
                "Add them to tabletop-kit's source catalog, or leave their content out.\n\(lines)"
        case .duplicateTitles(let titles):
            return "Reading the source catalog failed: titles listed twice: \(titles.joined(separator: "; "))"
        case .unreadableCatalog(let name, let reason):
            return "Reading the source catalog \(name) failed: \(reason)"
        case .malformedTally(let line, let text):
            return "Reading the source list failed at line \(line), not \"title<TAB>count\": \(text)"
        }
    }
}
