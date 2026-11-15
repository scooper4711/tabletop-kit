import Foundation
@testable import TablesideShared
import Testing

/// The bridge without the App Group (R5): asking Scrollkeeper for the list, reading it, and asking for titles.
@MainActor @Suite struct ScrollkeeperBridgeTests {
    let launcher = FakeLauncher()

    private func bridge(_ configuration: ScrollkeeperBridgeConfiguration = .mapper) -> ScrollkeeperBridge {
        ScrollkeeperBridge(configuration: configuration, launcher: launcher)
    }

    private func status(_ query: String, scheme: String = "mapper") throws -> URL {
        try #require(URL(string: "\(scheme)://handoff?\(query)"))
    }

    @Test func asksScrollkeeperInTheBackgroundForTheList() {
        let bridge = bridge(.reader)
        bridge.requestIndex()
        #expect(bridge.state == .waiting)
        #expect(bridge.takesRequests)
        #expect(launcher.backgroundURLs.map(\.absoluteString) == ["scrollkeeper://index?app=reader"])
    }

    @Test func saysWhenScrollkeeperIsNotInstalled() {
        launcher.installed = false
        let bridge = bridge()
        bridge.requestIndex()
        #expect(bridge.state == .notInstalled)
        #expect(launcher.backgroundURLs.isEmpty)
    }

    @Test func readsTheListScrollkeeperHandsOver() throws {
        let bridge = bridge(.reader)
        bridge.receive(try HandedOverIndex.write())
        let index = try bridge.loadedIndex()
        #expect(index.titles.map(\.sku) == ["PZO90200E", "PZO2101E"])
        #expect(index.titles[0].subtitle == "Adventure Paths · Seven Dooms #200")
        #expect(index.titles[1].subtitle == "Rulebooks")
        #expect(index.titles.map(\.downloaded) == [true, false])
        #expect(index.generatedAt == Date(timeIntervalSince1970: 1_792_346_400))
    }

    @Test func leavesTheKindOutWhereTheAppDoesNotShowIt() throws {
        let bridge = bridge(.mapper)
        bridge.receive(try HandedOverIndex.write())
        let index = try bridge.loadedIndex()
        #expect(index.titles.map(\.subtitle) == ["Seven Dooms #200", ""])
        #expect(index.search("rulebooks").isEmpty)
    }

    @Test func refusesAListInANewerFormat() throws {
        let bridge = bridge()
        bridge.receive(try HandedOverIndex.write(version: 2))
        #expect(bridge.state == .unsupportedVersion)
    }

    @Test func saysWhenTheListCannotBeRead() throws {
        let bridge = bridge()
        bridge.receive(try HandedOverIndex.write("not json"))
        #expect(bridge.state == .unreadable)
        bridge.receive(try HandedOverIndex.write(#"{"formatVersion": 1}"#))
        #expect(bridge.state == .unreadable)
        bridge.receive(URL(filePath: "/nowhere/list.scrollkeeperindex"))
        #expect(bridge.state == .unreadable)
    }

    @Test func asksScrollkeeperInTheBackgroundToOpenATitle() {
        let bridge = bridge()
        let entry = ScrollkeeperIndex.Entry(sku: "PZO 31&005", title: "Odd")
        bridge.open(entry)

        #expect(launcher.backgroundURLs.map(\.absoluteString)
            == ["scrollkeeper://open?sku=PZO%2031%26005&app=mapper"])
        #expect(bridge.request(for: entry) == ScrollkeeperRequest(sku: "PZO 31&005", opens: true, phase: .requested))
    }

    @Test func asksScrollkeeperToDownloadWithoutOpening() {
        let bridge = bridge()
        let entry = ScrollkeeperIndex.Entry(sku: "PZO31005", title: "Forest", downloaded: false)
        bridge.download(entry)

        #expect(launcher.backgroundURLs.map(\.absoluteString) == ["scrollkeeper://download?sku=PZO31005&app=mapper"])
        #expect(bridge.request(for: entry)?.opens == false)
    }

    @Test func followsTheStatusScrollkeeperReports() throws {
        let bridge = bridge()
        let entry = ScrollkeeperIndex.Entry(sku: "PZO1", title: "Forest", downloaded: false)
        bridge.open(entry)

        bridge.receiveStatus(try status("sku=PZO1&state=downloading&fraction=0.42"))
        #expect(bridge.request(for: entry)?.phase == .downloading(0.42))
        bridge.receiveStatus(try status("sku=OTHER&state=done"))
        bridge.receiveStatus(try status("sku=PZO1&state=sideways"))
        #expect(bridge.request(for: entry)?.phase == .downloading(0.42))
        bridge.receiveStatus(try status("sku=PZO1&state=done"))
        #expect(bridge.request(for: entry)?.phase == .done)
        #expect(bridge.request(for: entry)?.phase.isFailure == false)
        bridge.receiveStatus(try status("sku=PZO1&state=failed&reason=Signed%20out"))
        #expect(bridge.request(for: entry)?.phase == .failed("Signed out"))
        #expect(bridge.request(for: entry)?.phase.isFailure == true)
    }

    @Test func marksADownloadedTitleOnDisk() throws {
        let bridge = bridge()
        bridge.receive(try HandedOverIndex.write())
        let core = try #require(try bridge.loadedIndex().titles.last)
        bridge.download(core)

        bridge.receiveStatus(try status("sku=PZO2101E&state=done"))

        #expect(try bridge.loadedIndex().titles.map(\.downloaded) == [true, true])
    }

    @Test func keepsSeveralRequestsSideBySide() {
        let bridge = bridge(.mapper)
        bridge.download(ScrollkeeperIndex.Entry(sku: "A", title: "A"))
        bridge.download(ScrollkeeperIndex.Entry(sku: "B", title: "B"))
        #expect(bridge.requests.keys.sorted() == ["A", "B"])
    }

    @Test func replacesTheRequestWhenTheAppSendsOneAtATime() throws {
        let bridge = bridge(.reader)
        bridge.open(ScrollkeeperIndex.Entry(sku: "A", title: "A"))
        bridge.open(ScrollkeeperIndex.Entry(sku: "B", title: "B"))
        bridge.receiveStatus(try status("sku=A&state=done", scheme: "reader"))

        #expect(bridge.requests == ["B": ScrollkeeperRequest(sku: "B", opens: true, phase: .requested)])
    }

    @Test func forgetsSettledRequestsWhenTheListIsAskedForAgain() throws {
        let bridge = bridge()
        for sku in ["WAITING", "LOADING", "DONE", "FAILED"] {
            bridge.open(ScrollkeeperIndex.Entry(sku: sku, title: sku))
        }
        bridge.receiveStatus(try status("sku=LOADING&state=downloading&fraction=0.5"))
        bridge.receiveStatus(try status("sku=DONE&state=done"))
        bridge.receiveStatus(try status("sku=FAILED&state=failed&reason=No"))

        bridge.requestIndex()

        #expect(bridge.requests.keys.sorted() == ["LOADING", "WAITING"])
    }

    @Test func showsWhyScrollkeeperCouldNotSendTheList() throws {
        let bridge = bridge()
        bridge.requestIndex()
        bridge.receiveStatus(try status("sku=&state=failed&reason=Sign%20in"))
        #expect(bridge.state == .failed("Sign in"))
    }

    @Test func tellsItsOwnStatusLinksFromOtherLinks() throws {
        let bridge = bridge(.reader)
        #expect(bridge.isStatusLink(try status("sku=A&state=done", scheme: "reader")))
        #expect(!bridge.isStatusLink(try status("sku=A&state=done", scheme: "mapper")))
        #expect(!bridge.isStatusLink(try #require(URL(string: "reader://other"))))
        #expect(!bridge.isStatusLink(URL(filePath: "/x/core.pdf")))
    }

    @Test func usesTheStatusSchemeTheAppSets() throws {
        var configuration = ScrollkeeperBridgeConfiguration.reader
        configuration.statusScheme = "reader-status"
        let bridge = bridge(configuration)
        #expect(bridge.isStatusLink(try status("sku=A&state=done", scheme: "reader-status")))
        #expect(!bridge.isStatusLink(try status("sku=A&state=done", scheme: "reader")))
    }

    @Test func bringsScrollkeeperForward() {
        bridge().launchScrollkeeper()
        #expect(launcher.launched == [ScrollkeeperBridge.bundleIdentifier])
    }

    @Test func takesRequestsUnlessTheLauncherSaysOtherwise() {
        struct PlainLauncher: ApplicationLauncher {
            func isInstalled(_ bundleIdentifier: String) -> Bool { true }
            func openInBackground(_ url: URL) {}
            func launch(_ bundleIdentifier: String) {}
        }
        #expect(PlainLauncher().takesRequests)
    }

    #if os(macOS)
    @Test func findsTheAppsTheMacHasInstalled() {
        #expect(WorkspaceLauncher().isInstalled("com.apple.finder"))
        #expect(!WorkspaceLauncher().isInstalled("io.github.scooper4711.NoSuchApp"))
    }
    #endif
}

@Suite struct ScrollkeeperIndexTests {
    let index = ScrollkeeperIndex(generatedAt: .now, titles: [
        .init(sku: "A", title: "Flip-Mat Classics: Forest", kind: "Maps", series: "Flip-Mat Classics"),
        .init(sku: "B", title: "Flip-Mat: Haunted Dungeons", kind: "Maps"),
        .init(sku: "C", title: "Seven Dooms for Sandpoint", kind: "Adventure Paths", series: "Seven Dooms"),
        .init(sku: "D", title: "Flip-Tiles: Château Ruins")
    ])

    @Test(arguments: [("  ", ["A", "B", "C", "D"]), ("flip forest", ["A"]), ("flip", ["A", "B", "D"]),
                      ("CHATEAU", ["D"]), ("classics", ["A"]), ("adventure dooms", ["C"]), ("maps", ["A", "B"]),
                      ("starship", [])])
    func searchesTitleKindAndSeries(query: String, expected: [String]) {
        #expect(index.search(query).map(\.sku) == expected)
    }

    @Test func tellsTheListFromADocument() {
        #expect(ScrollkeeperIndex.isIndexFile(URL(filePath: "/x/pluck.SCROLLKEEPERINDEX")))
        #expect(!ScrollkeeperIndex.isIndexFile(URL(filePath: "/x/core.pdf")))
    }

    @Test func describesATitleByKindSeriesAndNumber() {
        #expect(index.titles[2].subtitle == "Adventure Paths · Seven Dooms")
        #expect(ScrollkeeperIndex.Entry(sku: "E", title: "Tavern", number: 3).subtitle == "#3")
        #expect(index.titles[3].subtitle.isEmpty)
    }
}
