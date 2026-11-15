import CoreGraphics
import Foundation
import ImageIO
@testable import TablesideShared
import Testing
import UniformTypeIdentifiers

/// The bridge with the library Scrollkeeper shares in the App Group (R5.1, R5.4, R5.6).
@MainActor @Suite struct ScrollkeeperBridgeLibraryTests {
    let launcher = FakeLauncher()
    let folder = FakeScrollkeeperFolder()

    private func loadedBridge(_ configuration: ScrollkeeperBridgeConfiguration) -> ScrollkeeperBridge {
        let bridge = ScrollkeeperBridge(configuration: configuration, launcher: launcher, libraryFolder: folder.url)
        bridge.requestIndex()
        return bridge
    }

    @Test func listsTheTitlesThatMayHoldAnAcceptedFileWithoutAskingScrollkeeper() throws {
        try folder.write(makeLibrary(titles: [
            makeTitle("BOOK", kind: "Adventures", cover: "Covers/BOOK.jpg", editions: [makeEdition("Book/Book.pdf")]),
            makeTitle("PACK", kind: "Society Scenarios", editions: [makeEdition("Pack/Pack", isFolder: true)]),
            makeTitle("AUDIO", kind: "Adventures", editions: [makeEdition("Audio/Audio.mp3")]),
            makeTitle("BARE", kind: "Adventures")
        ]))

        let entries = try loadedBridge(.reader).loadedIndex().titles
        #expect(entries.map(\.sku) == ["BOOK", "PACK"])
        #expect(entries[1].subtitle == "Society Scenarios")
        #expect(entries[0].coverURL == folder.url.appending(path: "Covers/BOOK.jpg"))
        #expect(launcher.backgroundURLs.isEmpty)
    }

    @Test func listsOnlyTheTitlesTheAppAsksForAndHidesTheirKind() throws {
        try folder.write(makeLibrary(titles: [
            makeTitle("MAP", editions: [makeEdition("Map/Map.pdf")]),
            makeTitle("BOOK", kind: "Adventures", editions: [makeEdition("Book/Book.pdf")])
        ]))

        let entries = try loadedBridge(.mapper).loadedIndex().titles
        #expect(entries.map(\.sku) == ["MAP"])
        #expect(entries[0].kind == nil)
    }

    @Test func opensTheAcceptedFilesOnDiskStraightFromTheSharedFolder() throws {
        try folder.addFile("Pack/Pack/map.jpg")
        try folder.addFile("Pack/Pack/notes.txt")
        try folder.write(makeLibrary(titles: [makeTitle("PACK", editions: [makeEdition("Pack/Pack", isFolder: true)])]))
        let bridge = loadedBridge(.mapper)
        var opened: [URL] = []
        bridge.openDocuments = { opened += $0 }

        bridge.open(try #require(try bridge.loadedIndex().titles.first))

        #expect(opened.map(\.lastPathComponent) == ["map.jpg"])
        #expect(launcher.backgroundURLs.isEmpty)
        #expect(bridge.requests.isEmpty)
    }

    @Test func asksScrollkeeperForTitlesNotInTheSharedFolder() throws {
        try folder.write(makeLibrary(isShared: false,
                                     titles: [makeTitle("MAP", editions: [makeEdition("Map/Map.pdf")])]))
        let bridge = loadedBridge(.mapper)

        bridge.open(try #require(try bridge.loadedIndex().titles.first))

        #expect(launcher.backgroundURLs.map(\.absoluteString) == ["scrollkeeper://open?sku=MAP&app=mapper"])
    }

    @Test(arguments: ["", "not json", #"{"formatVersion": 99}"#])
    func asksScrollkeeperForTheListWhenThereIsNoneItCanRead(list: String) throws {
        if !list.isEmpty { try folder.writeRaw(list) }
        let bridge = loadedBridge(.reader)
        #expect(bridge.state == .waiting)
        #expect(launcher.backgroundURLs.map(\.absoluteString) == ["scrollkeeper://index?app=reader"])
    }

    @Test func followsTheLibraryOnlyWhileShowingIt() throws {
        try folder.write(makeLibrary(titles: [makeTitle("OLD", editions: [makeEdition("Old/Old.pdf")])]))
        let bridge = loadedBridge(.reader)
        try folder.write(makeLibrary(titles: [makeTitle("NEW", editions: [makeEdition("New/New.pdf")])]))

        bridge.refreshLibrary()
        #expect(try bridge.loadedIndex().titles.map(\.sku) == ["NEW"])

        bridge.receive(try HandedOverIndex.write(titles: [HandedOverIndex.core]))
        try folder.write(makeLibrary(titles: []))
        bridge.refreshLibrary()
        #expect(try bridge.loadedIndex().titles.map(\.sku) == ["PZO2101E"])
    }

    @Test func doesNotReadTheLibraryWhileWaitingForScrollkeeper() throws {
        let bridge = loadedBridge(.reader)
        try folder.write(makeLibrary(titles: [makeTitle("NEW", editions: [makeEdition("New/New.pdf")])]))

        bridge.refreshLibrary()

        #expect(bridge.state == .waiting)
    }
}

/// The bridge where Scrollkeeper takes no requests, as on the iPad: only the shared library is read (R5.7).
@MainActor @Suite struct ScrollkeeperBridgeSharedLibraryOnlyTests {
    let launcher: FakeLauncher = {
        let launcher = FakeLauncher()
        launcher.takesRequests = false
        return launcher
    }()
    let folder = FakeScrollkeeperFolder()

    private func bridge() -> ScrollkeeperBridge {
        ScrollkeeperBridge(configuration: .mapper, launcher: launcher, libraryFolder: folder.url)
    }

    @Test func saysThereIsNoSharedLibraryInsteadOfAsking() {
        let bridge = bridge()
        bridge.requestIndex()
        #expect(bridge.state == .noSharedLibrary)
        #expect(launcher.backgroundURLs.isEmpty)
        #expect(!bridge.takesRequests)
    }

    @Test func readsTheLibraryOnceScrollkeeperSharesIt() throws {
        let bridge = bridge()
        bridge.requestIndex()
        try folder.write(makeLibrary(titles: [makeTitle("MAP1")]))

        bridge.refreshLibrary()

        #expect(try bridge.loadedIndex().titles.map(\.sku) == ["MAP1"])
    }

    @Test func bringsScrollkeeperForwardForATitleNotDownloaded() {
        let bridge = bridge()
        let entry = ScrollkeeperIndex.Entry(sku: "PZO1", title: "Forest", downloaded: false)

        bridge.open(entry)
        bridge.download(entry)

        #expect(launcher.launched == [ScrollkeeperBridge.bundleIdentifier, ScrollkeeperBridge.bundleIdentifier])
        #expect(launcher.backgroundURLs.isEmpty)
        #expect(bridge.request(for: entry) == nil)
    }

    @Test func checksThatScrollkeeperIsInstalledFirst() {
        launcher.installed = false
        let bridge = bridge()
        bridge.requestIndex()
        #expect(bridge.state == .notInstalled)
    }

    @Test func saysWhenTheLibraryIsNewerThanItKnows() throws {
        try folder.writeRaw(#"{"formatVersion": 99}"#)
        let bridge = bridge()
        bridge.requestIndex()
        #expect(bridge.state == .unsupportedVersion)
    }
}

/// The bridge of an app that chooses not to ask for the list, where Scrollkeeper does take requests (R5.7).
@MainActor @Suite struct ScrollkeeperBridgeWithoutIndexTests {
    let launcher = FakeLauncher()
    let folder = FakeScrollkeeperFolder()

    private func askedBridge() -> ScrollkeeperBridge {
        let bridge = ScrollkeeperBridge(configuration: .libraryOnlyMapper, launcher: launcher,
                                        libraryFolder: folder.url)
        bridge.requestIndex()
        return bridge
    }

    @Test(arguments: [("", ScrollkeeperBridge.State.noSharedLibrary), ("not json", .unreadable),
                      (#"{"formatVersion": 99}"#, .unsupportedVersion)])
    func saysWhatItFoundInsteadOfAskingForTheList(list: String, expected: ScrollkeeperBridge.State) throws {
        if !list.isEmpty { try folder.writeRaw(list) }

        let bridge = askedBridge()

        #expect(bridge.state == expected)
        #expect(launcher.backgroundURLs.isEmpty)
    }

    @Test func readsTheLibraryOnceScrollkeeperWritesOneItCanRead() throws {
        try folder.writeRaw("not json")
        let bridge = askedBridge()
        try folder.write(makeLibrary(titles: [makeTitle("MAP1")]))

        bridge.refreshLibrary()

        #expect(try bridge.loadedIndex().titles.map(\.sku) == ["MAP1"])
    }

    @Test func keepsTheListShownWhenTheLibraryCanNoLongerBeRead() throws {
        try folder.write(makeLibrary(titles: [makeTitle("MAP1")]))
        let bridge = askedBridge()
        try folder.writeRaw("not json")

        bridge.refreshLibrary()

        #expect(try bridge.loadedIndex().titles.map(\.sku) == ["MAP1"])
    }

    @Test func stillAsksScrollkeeperForATitle() {
        let bridge = askedBridge()
        let entry = ScrollkeeperIndex.Entry(sku: "MAP1", title: "Forest", downloaded: false)

        bridge.download(entry)

        #expect(bridge.takesRequests)
        #expect(launcher.backgroundURLs.map(\.absoluteString) == ["scrollkeeper://download?sku=MAP1&app=mapper"])
        #expect(bridge.request(for: entry)?.phase == .requested)
    }
}

@Suite struct ScrollkeeperCoverThumbnailTests {
    @Test func readsACoverAndNothingFromAFileThatIsNotAnImage() throws {
        let folder = FakeScrollkeeperFolder()
        let cover = folder.url.appending(path: "cover.png")
        let context = try #require(CGContext(data: nil, width: 4, height: 6, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let image = try #require(context.makeImage())
        let destination = try #require(CGImageDestinationCreateWithURL(cover as CFURL,
                                                                       UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))

        #expect(ScrollkeeperCoverThumbnail.loadImage(cover)?.height == 6)
        #expect(ScrollkeeperCoverThumbnail.loadImage(folder.url.appending(path: "missing.png")) == nil)
    }
}
