import Foundation

/// A notice file an app ships in its `Licenses` folder, which the About screen lists by name.
public struct NoticeFile: Hashable, Sendable {
    public let name: String
    public let text: String
}

/// Writes the ORC and OGL notices for the sources an import used: each license's text with an attribution notice
/// (ORC) or Section 15 (OGL) that names every one of them. Fails, listing them all, when a source isn't in the
/// catalog, lacks facts, or is covered by neither license: unknown sources never ship silently.
public enum NoticeWriter {
    public static let orcFileName = "ORC License.md"
    public static let oglFileName = "Open Game License.md"
    static let oglOwnNotice = "Open Game License v 1.0 Copyright 2000, Wizards of the Coast, Inc."

    /// The notices the sources need: only the licenses at least one of them is under.
    public static func notices(for tally: SourceTally, catalog: SourceCatalog) throws -> [NoticeFile] {
        let entries = try attributedEntries(for: tally, in: catalog)
        let orc = entries.filter { $0.license == .orc }
        let ogl = entries.filter { $0.license == .ogl }
        var files: [NoticeFile] = []
        if !orc.isEmpty {
            let text = try render("orc-notice", replacing: "{{ATTRIBUTION}}", with: orc.map(\.noticeLine))
            files.append(NoticeFile(name: orcFileName, text: text))
        }
        if !ogl.isEmpty {
            let text = try render("open-game-license", replacing: "{{COPYRIGHT}}", with: copyrightLines(ogl))
            files.append(NoticeFile(name: oglFileName, text: text))
        }
        return files
    }

    /// Writes the notices into `folder` and removes a notice file the sources no longer need.
    @discardableResult
    public static func write(for tally: SourceTally, catalog: SourceCatalog, to folder: URL) throws -> [URL] {
        let files = try notices(for: tally, catalog: catalog)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for name in [orcFileName, oglFileName] where !files.contains(where: { $0.name == name }) {
            try? FileManager.default.removeItem(at: folder.appending(path: name))
        }
        return try files.map { file in
            let url = folder.appending(path: file.name)
            try Data(file.text.utf8).write(to: url, options: .atomic)
            return url
        }
    }

    /// The catalog entry of every source, sorted by title, or every problem at once.
    static func attributedEntries(for tally: SourceTally, in catalog: SourceCatalog) throws -> [CatalogEntry] {
        var entries: [String: CatalogEntry] = [:]
        var problems: [AttributionError.Problem] = []
        for source in tally.sources {
            guard let entry = catalog.entry(for: source.title) else {
                problems.append(.init(title: source.title, reason: "not in the catalog"))
                continue
            }
            if let reason = problem(with: entry) {
                problems.append(.init(title: source.title, reason: reason))
            } else {
                entries[entry.title] = entry
            }
        }
        guard problems.isEmpty else { throw AttributionError.unattributedSources(problems) }
        return entries.values.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    private static func problem(with entry: CatalogEntry) -> String? {
        let missing = entry.missingFacts
        if !missing.isEmpty { return "the catalog lacks its \(missing.joined(separator: ", "))" }
        guard entry.license == SourceLicense.none else { return nil }
        let basis = entry.note.map { " (\($0))" } ?? ""
        return "covered by neither the ORC License nor the OGL\(basis)"
    }

    private static func copyrightLines(_ entries: [CatalogEntry]) -> [String] {
        let included = Set(entries.flatMap(\.includes))
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        return [oglOwnNotice] + entries.map(\.noticeLine) + included
    }

    /// The template with `marker` replaced by the lines as a bulleted list.
    private static func render(_ template: String, replacing marker: String, with lines: [String]) throws -> String {
        let list = lines.map { "* \($0)" }.joined(separator: "\n")
        return try templateText(template).replacingOccurrences(of: marker, with: list)
    }

    private static func templateText(_ name: String) throws -> String {
        guard let url = Bundle.module.url(forResource: name, withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            throw AttributionError.unreadableCatalog("\(name).md", "not in the bundle")
        }
        return text
    }
}
