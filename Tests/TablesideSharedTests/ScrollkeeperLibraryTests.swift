import Foundation
@testable import TablesideShared
import Testing
import UniformTypeIdentifiers

/// Scrollkeeper's folder in a temporary directory, as Scrollkeeper leaves it in the App Group, removed afterward.
final class FakeScrollkeeperFolder {
    let url = FileManager.default.temporaryDirectory.appending(path: "Scrollkeeper-" + UUID().uuidString)
    var files: URL { url.appending(path: "Files") }

    init() {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: url) }

    func write(_ library: ScrollkeeperLibrary) throws {
        try library.encoded().write(to: url.appending(path: ScrollkeeperLibrary.fileName))
    }

    func writeRaw(_ text: String) throws {
        try Data(text.utf8).write(to: url.appending(path: ScrollkeeperLibrary.fileName))
    }

    /// Creates an empty file at `path` in the download folder.
    func addFile(_ path: String) throws {
        let file = files.appending(path: path)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: file)
    }
}

func makeLibrary(isShared: Bool = true, titles: [ScrollkeeperLibrary.Title]) -> ScrollkeeperLibrary {
    ScrollkeeperLibrary(generatedAt: Date(timeIntervalSince1970: 1_800_000_000),
                        downloadFolder: .init(isShared: isShared, path: isShared ? nil : "/Chosen"), titles: titles)
}

func makeTitle(_ sku: String, kind: String = "Maps", cover: String? = nil,
               editions: [ScrollkeeperLibrary.Edition] = []) -> ScrollkeeperLibrary.Title {
    ScrollkeeperLibrary.Title(sku: sku, title: "Title \(sku)", kind: kind, gameSystem: "Pathfinder 2E",
                              cover: cover, editions: editions)
}

func makeEdition(_ path: String, isFolder: Bool = false, downloaded: Bool = true,
                 outdated: Bool = false) -> ScrollkeeperLibrary.Edition {
    ScrollkeeperLibrary.Edition(name: path, path: path, isFolder: isFolder, downloaded: downloaded,
                                outdated: outdated)
}

@Suite struct ScrollkeeperLibraryReadingTests {
    let folder = FakeScrollkeeperFolder()

    @Test func readsBackWhatScrollkeeperWrites() throws {
        let library = makeLibrary(titles: [
            ScrollkeeperLibrary.Title(sku: "PZO1", title: "Book", kind: "Adventures", gameSystem: "Pathfinder 2E",
                                      series: "Seven Dooms", number: 200,
                                      levels: .init(lowest: 1, highest: 4), cover: "Covers/PZO1.jpg",
                                      downloaded: true, editions: [
                                          .init(name: "Book PDF", kind: "Single File", path: "Book/Book PDF.pdf",
                                                downloaded: true)
                                      ])
        ])
        try folder.write(library)

        #expect(ScrollkeeperLibrary.read(from: folder.url) == .loaded(library))
    }

    @Test func saysWhenThereIsNoList() {
        #expect(ScrollkeeperLibrary.read(from: folder.url) == .missing)
    }

    @Test func saysWhenTheListCannotBeRead() throws {
        try folder.writeRaw("not json")
        #expect(ScrollkeeperLibrary.read(from: folder.url) == .unreadable)
        try folder.writeRaw(#"{"formatVersion": 1}"#)
        #expect(ScrollkeeperLibrary.read(from: folder.url) == .unreadable)
    }

    @Test func refusesANewerFormatBeforeReadingTheRest() throws {
        try folder.writeRaw(#"{"formatVersion": 2, "somethingNew": true}"#)
        #expect(ScrollkeeperLibrary.read(from: folder.url) == .newerFormat)
    }

    @Test func ignoresFieldsAddedLater() throws {
        try folder.writeRaw("""
            {"formatVersion": 1, "generatedAt": "2026-11-07T18:00:00Z", "downloadFolder": {"isShared": true},
             "titles": [], "somethingNew": [1, 2]}
            """)
        guard case let .loaded(library) = ScrollkeeperLibrary.read(from: folder.url) else {
            Issue.record("The list wasn't read")
            return
        }
        #expect(library.titles.isEmpty)
    }

    @Test func findsTheSharedDownloadFolderAndCovers() {
        let shared = makeLibrary(titles: [])
        let files = folder.url.appending(path: "Files", directoryHint: .isDirectory)
        #expect(shared.downloadFolderURL(in: folder.url) == files)
        #expect(makeLibrary(isShared: false, titles: []).downloadFolderURL(in: folder.url) == nil)
        let cover = folder.url.appending(path: "Covers/A.jpg")
        #expect(makeTitle("A", cover: "Covers/A.jpg").coverURL(in: folder.url) == cover)
        #expect(makeTitle("A").coverURL(in: folder.url) == nil)
    }
}

@Suite struct FilesToOpenTests {
    let folder = FakeScrollkeeperFolder()
    let pdfOrImage = { (type: UTType) in type.conforms(to: .pdf) || type.conforms(to: .image) }

    @Test func choosesAnUpToDateSingleFileFirst() throws {
        let title = makeTitle("A", editions: [
            makeEdition("A/Pack", isFolder: true),
            makeEdition("A/A.pdf")
        ])
        #expect(title.filesToOpen(in: folder.files, accepting: pdfOrImage) == [folder.files.appending(path: "A/A.pdf")])
    }

    @Test func choosesAnArchivesPDFsBeforeItsImages() throws {
        for path in ["A/Pack/b.pdf", "A/Pack/a.pdf", "A/Pack/a.jpg", "A/Pack/notes.txt", "A/Pack/.hidden.pdf"] {
            try folder.addFile(path)
        }
        let title = makeTitle("A", editions: [makeEdition("A/Pack", isFolder: true)])
        let names = title.filesToOpen(in: folder.files, accepting: pdfOrImage).map(\.lastPathComponent)
        #expect(names == ["a.pdf", "b.pdf"])
    }

    @Test func choosesAnArchivesImagesWhenItHasNoPDF() throws {
        try folder.addFile("A/Tiles/sub/2.png")
        try folder.addFile("A/Tiles/1.jpg")
        let title = makeTitle("A", editions: [makeEdition("A/Tiles", isFolder: true)])
        let names = title.filesToOpen(in: folder.files, accepting: pdfOrImage).map(\.lastPathComponent)
        #expect(names == ["1.jpg", "2.png"])
    }

    @Test func skipsFilesTheReaderDoesNotAccept() throws {
        try folder.addFile("A/Pack/a.jpg")
        let title = makeTitle("A", editions: [makeEdition("A/A.epub"), makeEdition("A/Pack", isFolder: true)])
        #expect(title.filesToOpen(in: folder.files) { $0.conforms(to: .pdf) }.isEmpty)
    }

    @Test func offersNothingThatIsOutdatedOrNotDownloaded() {
        let title = makeTitle("A", editions: [
            makeEdition("A/Old.pdf", outdated: true),
            makeEdition("A/New.pdf", downloaded: false)
        ])
        #expect(title.filesToOpen(in: folder.files, accepting: pdfOrImage).isEmpty)
    }
}

@Suite struct ToolkitGroupTests {
    @Test func findsTheToolkitGroupAmongTheSignedGroups() {
        let groups = ["T.io.github.scooper4711.other", "T.io.github.scooper4711.tableside"]
        #expect(ToolkitGroup.macIdentifier(among: groups) == "T.io.github.scooper4711.tableside")
        #expect(ToolkitGroup.macIdentifier(among: []) == nil)
    }

    @Test func testsRunOutsideTheGroup() {
        #expect(ToolkitGroup.containerURL() == nil)
        #expect(ToolkitGroup.scrollkeeperFolder() == nil)
    }
}

@MainActor
@Suite struct LibraryChangeTests {
    @Test func tellsObserversWhenTheListChanges() async throws {
        let heard = Heard()
        let observer = LibraryChangeObserver { heard.isHeard = true }

        LibraryChange.post()
        for _ in 0..<100 where !heard.isHeard {
            try await Task.sleep(for: .milliseconds(20))
        }

        #expect(heard.isHeard)
        withExtendedLifetime(observer) {}
    }
}

@MainActor
final class Heard {
    var isHeard = false
}
