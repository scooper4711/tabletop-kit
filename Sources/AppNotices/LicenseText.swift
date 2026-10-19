import Foundation

/// A license the app's bundled content requires it to ship in full, such as the Open Game License.
public struct LicenseText: Hashable, Sendable {
    public let title: String
    public let text: String

    public init(title: String, text: String) {
        self.title = title
        self.text = text
    }

    /// Every `.md` and `.txt` file in the folder, sorted by name and titled by it ("Open Game License.md" is
    /// "Open Game License"), with Markdown turned into plain text; none when the folder is missing.
    public static func all(in folder: URL) -> [LicenseText] {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { ["md", "txt"].contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .compactMap { file in
                guard let text = try? String(contentsOf: file, encoding: .utf8) else { return nil }
                let isMarkdown = file.pathExtension.lowercased() == "md"
                return LicenseText(title: file.deletingPathExtension().lastPathComponent,
                                   text: isMarkdown ? MarkdownPlainText.convert(text) : text)
            }
    }
}
