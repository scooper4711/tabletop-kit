import Foundation

/// The source books an import actually used, with how many records came from each.
///
/// Titles are counted under `SourceTitle.key`, keeping the first spelling seen. As text, a tally is one
/// `title<TAB>count` line per source, sorted by title: the form the command-line tool reads and the
/// `docs/source-usage` files keep.
public struct SourceTally: Hashable, Sendable {
    public struct Source: Hashable, Sendable {
        public let title: String
        public let count: Int
    }

    private var counts: [String: Source] = [:]

    public init() {}

    public init(text: String) throws {
        for (number, line) in text.split(whereSeparator: \.isNewline).enumerated() {
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard fields.count == 2, let count = Int(fields[1].trimmingCharacters(in: .whitespaces)) else {
                throw AttributionError.malformedTally(line: number + 1, String(line))
            }
            add(String(fields[0]), count: count)
        }
    }

    public mutating func add(_ title: String, count: Int = 1) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = SourceTitle.key(trimmed)
        let total = (counts[key]?.count ?? 0) + count
        counts[key] = Source(title: counts[key]?.title ?? trimmed, count: total)
    }

    /// Every source, sorted by title the way Finder sorts ("#9" before "#10").
    public var sources: [Source] {
        counts.values.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    public var text: String {
        sources.map { "\($0.title)\t\($0.count)\n" }.joined()
    }
}
