import DemoLibrary
import Foundation

// DemoLibraryTool <output folder> [--art <community-use-artwork folder>]
// Writes the demo library's PDFs. Scrollkeeper's `make demo-pdfs` runs it and commits what it writes.
let arguments = Array(CommandLine.arguments.dropFirst())
guard let output = arguments.first else {
    FileHandle.standardError.write(Data("Usage: DemoLibraryTool <output folder> [--art <folder>]\n".utf8))
    exit(2)
}
let artFolder = arguments.firstIndex(of: "--art").flatMap { index in
    arguments.indices.contains(index + 1) ? arguments[index + 1] : nil
}
do {
    try DemoLibrary.write(to: URL(fileURLWithPath: output, isDirectory: true),
                          communityUseFolder: artFolder.map { URL(fileURLWithPath: $0, isDirectory: true) })
    print("Wrote the demo library's PDFs to \(output)")
} catch {
    FileHandle.standardError.write(Data("Writing the demo library failed: \(error)\n".utf8))
    exit(1)
}
