import Foundation
import Observation

/// Scrollkeeper as another toolkit app sees it: the app reads the list of titles from Scrollkeeper's folder in the
/// App Group, or, unless it reads nothing else, asks for it and has it handed over as a file (which a sandboxed
/// app may then read), and asks
/// Scrollkeeper to download or open a title. A title already in the shared folder opens straight from there.
/// Scrollkeeper stays in the background and reports how each request goes with status links.
@MainActor
@Observable
public final class ScrollkeeperBridge {
    public enum State: Equatable, Sendable {
        case idle
        case notInstalled
        /// Scrollkeeper isn't asked for the list and hasn't shared its library (yet).
        case noSharedLibrary
        /// Asked for the list; Scrollkeeper may still be starting or loading its library.
        case waiting
        case unsupportedVersion
        case unreadable
        /// Scrollkeeper couldn't send the list, for the reason it gives.
        case failed(String)
        case loaded(ScrollkeeperIndex)
    }

    public static let bundleIdentifier = "io.github.scooper4711.Scrollkeeper"
    public static let downloadPage = URL(string: "https://github.com/scooper4711/scrollkeeper/releases/latest")!

    public private(set) var state = State.idle
    /// The requests sent and not yet forgotten, by SKU.
    public private(set) var requests: [String: ScrollkeeperRequest] = [:]
    /// Opens the files of a title that is on disk, which needs no request.
    @ObservationIgnored public var openDocuments: ([URL]) -> Void = { _ in }
    @ObservationIgnored private let configuration: ScrollkeeperBridgeConfiguration
    @ObservationIgnored private let launcher: ApplicationLauncher
    /// Scrollkeeper's folder in the App Group; nil when the app isn't in the group.
    @ObservationIgnored private let libraryFolder: URL?
    /// True while what is shown came from the library list, which is read again when it changes.
    @ObservationIgnored private var followsLibrary = false

    /// Three arguments: who the app is, the system it runs on, and where Scrollkeeper's folder is, if anywhere.
    public init(configuration: ScrollkeeperBridgeConfiguration, launcher: ApplicationLauncher,
                libraryFolder: URL? = nil) {
        self.configuration = configuration
        self.launcher = launcher
        self.libraryFolder = libraryFolder
    }

    /// Whether Scrollkeeper can be asked to download a title; when not, the user downloads it in Scrollkeeper.
    public var takesRequests: Bool { launcher.takesRequests }

    /// Reads the list of titles from Scrollkeeper's library list, or when there is none it can show, asks
    /// Scrollkeeper, staying in the background, to hand it over; an app that doesn't ask says what it found
    /// instead. Forgets the requests that are done or failed.
    public func requestIndex() {
        requests = requests.filter(\.value.phase.isUnderWay)
        guard launcher.isInstalled(Self.bundleIdentifier) else {
            state = .notInstalled
            return
        }
        let reading = readLibrary()
        if case .loaded = reading { return }
        followsLibrary = !asksForIndex
        guard asksForIndex else {
            state = Self.state(without: reading)
            return
        }
        state = .waiting
        launcher.openInBackground(requestURL(host: "index", sku: nil))
    }

    /// Reads the library list again after Scrollkeeper says it changed, or the app comes back to the foreground,
    /// while what is shown came from it: a list, or the lack of one where Scrollkeeper isn't asked for it.
    public func refreshLibrary() {
        guard followsLibrary else { return }
        _ = readLibrary()
    }

    /// Reads the list Scrollkeeper handed over.
    public func receive(_ file: URL) {
        followsLibrary = false
        guard let data = try? Data(contentsOf: file),
              let header = try? Self.decoder.decode(FormatHeader.self, from: data) else {
            state = .unreadable
            return
        }
        guard header.formatVersion <= ScrollkeeperIndex.supportedFormatVersion else {
            state = .unsupportedVersion
            return
        }
        guard let index = try? Self.decoder.decode(ScrollkeeperIndex.self, from: data) else {
            state = .unreadable
            return
        }
        state = .loaded(configuration.showsKind ? index : index.withoutKinds())
    }

    /// Opens the title's files when they are in the shared folder; otherwise asks Scrollkeeper to download the
    /// title when needed and open it in the app, or where Scrollkeeper takes no requests, brings it forward.
    public func open(_ entry: ScrollkeeperIndex.Entry) {
        guard entry.localFiles.isEmpty else {
            openDocuments(entry.localFiles)
            return
        }
        send(ScrollkeeperRequest(sku: entry.sku, opens: true, phase: .requested))
    }

    /// Asks Scrollkeeper to download the title without opening it, or where it takes no requests, brings it
    /// forward to download it there.
    public func download(_ entry: ScrollkeeperIndex.Entry) {
        send(ScrollkeeperRequest(sku: entry.sku, opens: false, phase: .requested))
    }

    /// The request for the title, if one was sent.
    public func request(for entry: ScrollkeeperIndex.Entry) -> ScrollkeeperRequest? {
        requests[entry.sku]
    }

    /// True for a link in which Scrollkeeper reports how a request is going.
    public func isStatusLink(_ url: URL) -> Bool {
        url.scheme == configuration.statusScheme && url.host == "handoff"
    }

    /// Takes a status link: `<scheme>://handoff?sku=…&state=downloading|done|failed[&fraction=…][&reason=…]`.
    /// A failure with no SKU is the list's.
    public func receiveStatus(_ url: URL) {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let value = { (name: String) in items.first { $0.name == name }?.value ?? "" }
        let sku = value("sku")
        if sku.isEmpty, value("state") == "failed" {
            state = .failed(value("reason"))
            return
        }
        guard requests[sku] != nil, let phase = Self.phase(state: value("state"), items: value) else { return }
        requests[sku]?.phase = phase
        if phase == .done { markDownloaded(sku) }
    }

    /// Brings Scrollkeeper forward, so the user can sign in and load their library.
    public func launchScrollkeeper() {
        launcher.launch(Self.bundleIdentifier)
    }

    /// Whether Scrollkeeper is asked to hand the list over when there is no library list to show.
    private var asksForIndex: Bool { launcher.takesRequests && configuration.asksForIndex }

    /// Looks for the library list in the App Group and shows it when it is one this reader understands.
    private func readLibrary() -> ScrollkeeperLibraryReading {
        guard let folder = libraryFolder else { return .missing }
        let reading = ScrollkeeperLibrary.read(from: folder)
        if case let .loaded(library) = reading {
            state = .loaded(library.index(in: folder, for: configuration))
            followsLibrary = true
        }
        return reading
    }

    /// What to show for a library list that can't be shown, where Scrollkeeper isn't asked for the list.
    private static func state(without reading: ScrollkeeperLibraryReading) -> State {
        switch reading {
        case .newerFormat: .unsupportedVersion
        case .unreadable: .unreadable
        case .missing, .loaded: .noSharedLibrary
        }
    }

    private func send(_ request: ScrollkeeperRequest) {
        guard launcher.takesRequests else {
            launchScrollkeeper()
            return
        }
        if configuration.sendsOneRequestAtATime { requests = [:] }
        requests[request.sku] = request
        launcher.openInBackground(requestURL(host: request.opens ? "open" : "download", sku: request.sku))
    }

    private func markDownloaded(_ sku: String) {
        guard case var .loaded(index) = state else { return }
        index.markDownloaded(sku)
        state = .loaded(index)
    }

    private static func phase(state: String, items value: (String) -> String) -> ScrollkeeperRequest.Phase? {
        switch state {
        case "downloading": .downloading(Double(value("fraction")) ?? 0)
        case "done": .done
        case "failed": .failed(value("reason"))
        default: nil
        }
    }

    func requestURL(host: String, sku: String?) -> URL {
        var components = URLComponents()
        components.scheme = "scrollkeeper"
        components.host = host
        components.queryItems = (sku.map { [URLQueryItem(name: "sku", value: $0)] } ?? [])
            + [URLQueryItem(name: "app", value: configuration.appKey)]
        return components.url!
    }

    private struct FormatHeader: Decodable {
        var formatVersion: Int
    }

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
