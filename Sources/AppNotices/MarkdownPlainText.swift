import Foundation

/// A Markdown license or credits file as plain text for the About screen, which shows it as it is: headings, links,
/// emphasis and code lose their markup, a table becomes one line per row with its cells separated by " · ", list
/// bullets become "•", and lines of a paragraph that were wrapped in the file are joined, so the screen wraps them.
enum MarkdownPlainText {
    /// A line at least this long is taken to have been wrapped by hand, and the line after it continues it.
    static let wrappedLineLength = 72

    static func convert(_ markdown: String) -> String {
        var lines: [String] = []
        for line in markdown.components(separatedBy: .newlines) where !isTableSeparator(line) {
            let plain = plainLine(line)
            if let previous = lines.last, continues(previous: previous, with: line) {
                lines[lines.count - 1] = previous + " " + plain.trimmingCharacters(in: .whitespaces)
            } else {
                lines.append(plain)
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func plainLine(_ line: String) -> String {
        if isTableRow(line) {
            return tableCells(line).map(inlineText).joined(separator: " · ")
        }
        var text = line.replacing(/^#{1,6}\s+/, with: "")
        text = text.replacing(/^(\s*)[*+-]\s+/) { match in match.output.1 + "• " }
        return inlineText(text)
    }

    private static func inlineText(_ text: String) -> String {
        text.replacing(/\[([^\]]*)\]\(([^)\s]+)\)/) { match in "\(match.output.1) (\(match.output.2))" }
            .replacing(/(\*\*|__)(.+?)\1/) { match in String(match.output.2) }
            .replacing(/`([^`]*)`/) { match in String(match.output.1) }
    }

    /// Whether `line` continues `previous`, a plain paragraph line that was wrapped in the file.
    private static func continues(previous: String, with line: String) -> Bool {
        let isPlainText = !line.trimmingCharacters(in: .whitespaces).isEmpty && !startsBlock(line)
        return isPlainText && previous.count >= wrappedLineLength && !isTableRow(previous)
    }

    /// Headings, list items, numbered items, quotes and table rows start a line of their own.
    private static func startsBlock(_ line: String) -> Bool {
        line.contains(/^\s*(#{1,6}\s|[*+-]\s|\d+[.)]\s|>|\|)/)
    }

    private static func isTableRow(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("|") && trimmed.hasSuffix("|") && trimmed.count > 1
    }

    private static func isTableSeparator(_ line: String) -> Bool {
        isTableRow(line) && line.allSatisfy { "|-: \t".contains($0) }
    }

    private static func tableCells(_ line: String) -> [String] {
        line.trimmingCharacters(in: .whitespaces)
            .dropFirst().dropLast()
            .split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }
}
