import Foundation
import SourceAttribution

/// `SourceAttributionTool write SOURCES OUTPUT_FOLDER`
///   Writes the ORC and OGL notices for the sources in SOURCES (`title<TAB>count` lines) into OUTPUT_FOLDER, such
///   as an app's `Generated/Licenses`. Fails, listing every source it can't attribute.
/// `SourceAttributionTool gaps USAGE_FOLDER REPORT`
///   Writes the gap list (REPORT) from the catalog and every app's source list (`<app>.txt`) in USAGE_FOLDER.
let usage = """
    Usage: SourceAttributionTool write SOURCES OUTPUT_FOLDER
           SourceAttributionTool gaps USAGE_FOLDER REPORT

    """
let arguments = Array(CommandLine.arguments.dropFirst())
guard arguments.count == 3, ["write", "gaps"].contains(arguments[0]) else {
    FileHandle.standardError.write(Data(usage.utf8))
    exit(2)
}
let input = URL(fileURLWithPath: arguments[1])
let output = URL(fileURLWithPath: arguments[2])
do {
    let catalog = try SourceCatalog.bundled()
    if arguments[0] == "write" {
        let tally = try SourceTally(text: String(contentsOf: input, encoding: .utf8))
        let files = try NoticeWriter.write(for: tally, catalog: catalog, to: output)
        print("Wrote \(files.map(\.lastPathComponent).joined(separator: " and ")) for \(tally.sources.count) sources.")
    } else {
        let lists = try FileManager.default.contentsOfDirectory(at: input, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "txt" }
        let tallies = try Dictionary(uniqueKeysWithValues: lists.map { list in
            let text = try String(contentsOf: list, encoding: .utf8)
            return (list.deletingPathExtension().lastPathComponent, try SourceTally(text: text))
        })
        try Data(GapReport.markdown(catalog: catalog, usage: tallies).utf8).write(to: output, options: .atomic)
        print("Wrote \(output.lastPathComponent) from \(tallies.count) source lists.")
    }
} catch {
    FileHandle.standardError.write(Data("\(error)\n".utf8))
    exit(1)
}
