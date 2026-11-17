import ArtExtraction
import ArtExtractionTestSupport
import Foundation
@testable import SharedLibraries
import Testing

/// A watched folder on a device that syncs (library sync R3.9, and PDFs iCloud Drive hasn't downloaded).
@Suite struct SyncWatchingTests {
    let devices: SyncedDevices

    init() throws {
        devices = try SyncedDevices()
    }

    /// The same pawn box PDF in the folder `Scrollkeeper/Files/<product>` of each device.
    func downloads(of device: SyncDevice, named name: String) throws -> (root: URL, pdf: URL) {
        let root = device.root.appending(path: "Scrollkeeper/Files", directoryHint: .isDirectory)
        let product = root.appending(path: "Pathfinder Test Pawn Box", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: product, withIntermediateDirectories: true)
        return (root, product.appending(path: name))
    }

    @Test func linksAPDFAnotherDeviceReadWithoutReadingItsArt() throws {
        let name = "Pathfinder Test Pawn Box PDF.pdf"
        let sender = try downloads(of: devices.first, named: name)
        try FileManager.default.copyItem(at: try devices.first.pawnBox(), to: sender.pdf)
        try devices.firstLibrary.add(sender.pdf, keeping: false)
        try devices.exchange()
        let receiver = try downloads(of: devices.second, named: name)
        try FileManager.default.copyItem(at: sender.pdf, to: receiver.pdf)
        let library = devices.secondLibrary
        try library.watch(receiver.root)
        let source = try #require(try library.sources().first)
        #expect(source.access.isEmpty)
        let counter = try library.changeCounter()

        let results = library.addNewFiles()
        #expect(results.count == 1)
        let report = try #require(try results.first?.get())
        #expect(report.wasImported && report.added == 0)
        let linked = try #require(try library.sources().first)
        guard case .inFolder(_, let path) = linked.access[.fieldGuide] else {
            Issue.record("expected the PDF reached through the watched folder")
            return
        }
        #expect(path == "Pathfinder Test Pawn Box/\(name)" && library.status(of: linked) == .available)
        #expect(try library.changes(since: counter).changedTables == [.sources, .sourceAccess])
        #expect(try library.artEntries().count == 2 && library.addNewFiles().isEmpty)
    }

    @Test func leavesAPDFAlreadyReachableAlone() throws {
        let name = "Pathfinder Test Pawn Box PDF.pdf"
        let files = try downloads(of: devices.first, named: name)
        try FileManager.default.copyItem(at: try devices.first.pawnBox(), to: files.pdf)
        try devices.firstLibrary.add(files.pdf, keeping: false)
        try devices.firstLibrary.watch(files.root)
        #expect(devices.firstLibrary.addNewFiles().isEmpty)
    }

    @Test func readsAPDFNoDeviceHasReadYet() throws {
        let files = try downloads(of: devices.first, named: "Pathfinder Test Pawn Box PDF.pdf")
        try FileManager.default.copyItem(at: try devices.first.pawnBox(), to: files.pdf)
        try devices.firstLibrary.watch(files.root)

        let results = devices.firstLibrary.addNewFiles()
        #expect(try results.first?.get().added == 2)
    }

    @Test(arguments: [
        (nil as URLUbiquitousItemDownloadingStatus?, true), (.current, true), (.downloaded, false),
        (.notDownloaded, false)
    ])
    func readsAFileOnlyOnceItsContentsAreOnTheDevice(status: URLUbiquitousItemDownloadingStatus?, expected: Bool) {
        #expect(SharedLibrary.isDownloaded(status) == expected)
    }
}
