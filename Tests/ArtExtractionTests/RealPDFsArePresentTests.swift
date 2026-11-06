import Foundation
import Testing

/// Where the sample PDFs are expected (CI names their folder in `TOOLKIT_TEST_PDFS`), the tests that read them must
/// run, not be skipped for want of them.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["TOOLKIT_TEST_PDFS"] != nil))
struct RealPDFsArePresent {
    @Test(arguments: ["Starfinder Core Rulebook Pawn", "Skull & Shackles", "Bestiary Pawn Box",
                      "Monster Core 2 Pawn Box"])
    func samplePDFIsPresent(named fragment: String) {
        #expect(RealPDFs.named(fragment) != nil, "\(fragment) is missing from \(RealPDFs.folder.path)")
    }
}
