import ArtExtraction
import ArtExtractionTestSupport
import Foundation
@testable import SharedLibraries
import Testing

/// Copies of the real libraries synced to an empty device (library sync), skipped without the gitignored
/// `TestData/RealLibraries`.
@Suite(.enabled(if: RealLibraries.areCopied)) struct RealLibrarySyncTests {
    @Test func syncsBothMovedInLibrariesToAnEmptyDevice() throws {
        let devices = try SyncedDevices()
        for app in [TablesideApp.turnkeeper, .fieldGuide] {
            let folder = devices.first.root.appending(path: app.rawValue)
            try FileManager.default.copyItem(at: RealLibraries.folder.appending(path: app.rawValue), to: folder)
            try devices.firstLibrary.moveIn(LibraryMove(app: app, artFolder: folder))
        }
        let start = Date()
        try devices.exchange()
        let entries = try devices.firstLibrary.artEntries()
        print("Synced \(entries.count) pieces of art in \(Date().timeIntervalSince(start)) s")
        #expect(try devices.secondLibrary.artEntries().count == entries.count)
        let aliases = try devices.firstLibrary.connection().rows("SELECT oldID FROM aliases")
            .compactMap { $0.uuid("oldID") }
        for alias in aliases {
            let expected = try devices.firstLibrary.artEntry(id: alias)?.id
            #expect(try devices.secondLibrary.artEntry(id: alias)?.id == expected)
        }
        #expect(try devices.firstLibrary.syncCandidates().isEmpty && devices.secondLibrary.syncCandidates().isEmpty)
    }
}
