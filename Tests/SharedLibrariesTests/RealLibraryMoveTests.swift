import ArtExtraction
import ArtExtractionTestSupport
import Foundation
@testable import SharedLibraries
import Testing

/// Copies of Turnkeeper's and Field Guide's real art libraries moving in (R6.4), without their kept PDFs. The copies
/// are in the gitignored `TestData/RealLibraries`, since they name the author's Paizo products; the tests are
/// skipped without them.
@Suite(.enabled(if: RealLibraries.areCopied)) struct RealLibraryMoveTests {

    @Test func movesBothAppsLibrariesInAndKeepsEveryOldID() throws {
        let copy = temporaryFolder()
        try FileManager.default.createDirectory(at: copy, withIntermediateDirectories: true)
        let library = try SharedLibrary(folder: copy.appending(path: "Tableside"), app: .turnkeeper)
        var oldEntries: [ArtEntry] = []
        for app in [TablesideApp.turnkeeper, .fieldGuide] {
            let folder = copy.appending(path: app.rawValue)
            try FileManager.default.copyItem(at: RealLibraries.folder.appending(path: app.rawValue), to: folder)
            oldEntries += try ArtLibrary(folder: folder).entries
            let start = Date()
            let report = try #require(try library.moveIn(LibraryMove(app: app, artFolder: folder)))
            print("\(app.rawValue): \(report) in \(Date().timeIntervalSince(start)) s")
        }

        let entries = try library.artEntries()
        let ids = Set(entries.map(\.id))
        let unresolved = try oldEntries.filter { old in
            try library.artEntry(id: old.id).map { !ids.contains($0.id) } ?? true
        }
        #expect(unresolved.isEmpty)
        #expect(entries.allSatisfy { $0.id == $0.keyedID })
        let tokens = entries.flatMap(\.prints).compactMap(\.print.tokenFile)
        #expect(tokens.allSatisfy { FileManager.default.fileExists(atPath: library.pictureFile($0).path) })
        print("Shared art: \(entries.count) from \(oldEntries.count) old entries, \(tokens.count) pictures")
    }
}

enum RealLibraries {
    static let folder = URL(filePath: #filePath).deletingLastPathComponent()
        .appending(path: "../../TestData/RealLibraries").standardized
    static var areCopied: Bool { FileManager.default.fileExists(atPath: folder.path) }
}
