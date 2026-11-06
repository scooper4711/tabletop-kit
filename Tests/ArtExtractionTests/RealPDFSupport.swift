import CoreGraphics
import Foundation

/// Sample pages of Paizo's pawn PDFs, which are copyrighted and kept out of this repository; empty when there are
/// none, and the tests that read them are skipped (`RealPDFsArePresent` makes that a failure where they're expected).
enum RealPDFs {
    /// Sample pages of Paizo's PDFs, kept in the private toolkit-artwork repository (`test-pdfs/`): the folder
    /// `TOOLKIT_TEST_PDFS` names, as CI sets it, else `test-pdfs` in a toolkit-artwork checkout next to this one.
    static let folder = ProcessInfo.processInfo.environment["TOOLKIT_TEST_PDFS"].map { URL(fileURLWithPath: $0) }
        ?? URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("toolkit-artwork/test-pdfs")

    static var all: [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.filter { $0.lowercased().hasSuffix(".pdf") }.sorted().map { folder.appendingPathComponent($0) }
    }

    static var isAvailable: Bool { !all.isEmpty }

    /// The first PDF whose name contains `fragment`.
    static func named(_ fragment: String) -> URL? {
        all.first { $0.lastPathComponent.contains(fragment) }
    }

    static func document(_ url: URL) -> CGPDFDocument? {
        CGPDFDocument(url as CFURL)
    }
}
