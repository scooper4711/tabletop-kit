import Foundation
import UniformTypeIdentifiers

/// How one app uses the Scrollkeeper bridge: who it is to Scrollkeeper, what it lists and what it opens.
public struct ScrollkeeperBridgeConfiguration: Sendable {
    /// The app's name in its requests (`app=`), such as "pluck".
    public var appKey: String
    /// The scheme of the status links Scrollkeeper sends the app, such as "pluck".
    public var statusScheme: String
    /// Whether a library title is one the app lists.
    public var lists: @Sendable (ScrollkeeperLibrary.Title) -> Bool
    /// Whether the app opens files of a type.
    public var opens: @Sendable (UTType) -> Bool
    /// Whether a title's kind shows under it and is searched; false where every title is of one kind.
    public var showsKind = true
    /// True when a new request replaces the one before; false when several run side by side.
    public var sendsOneRequestAtATime = false
    /// Whether the app asks Scrollkeeper to hand the list over when there is no library list it can read; false
    /// for an app that reads only the library list.
    public var asksForIndex = true

    /// A configuration whose status links use the app's key as their scheme.
    public init(appKey: String, lists: @escaping @Sendable (ScrollkeeperLibrary.Title) -> Bool,
                opens: @escaping @Sendable (UTType) -> Bool) {
        self.appKey = appKey
        self.statusScheme = appKey
        self.lists = lists
        self.opens = opens
    }
}

/// A title the app asked Scrollkeeper for, and how that is going.
public struct ScrollkeeperRequest: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        case requested
        case downloading(Double)
        /// Downloaded; when the title was asked to open, its files are on their way.
        case done
        case failed(String)

        public var isFailure: Bool {
            if case .failed = self { true } else { false }
        }

        /// True while Scrollkeeper is still working on the request.
        var isUnderWay: Bool {
            switch self {
            case .requested, .downloading: true
            case .done, .failed: false
            }
        }
    }

    public var sku: String
    /// True for Open and Download and Open; false when the title is only downloaded.
    public var opens: Bool
    public var phase: Phase

    public init(sku: String, opens: Bool, phase: Phase) {
        self.sku = sku
        self.opens = opens
        self.phase = phase
    }
}

extension ScrollkeeperLibrary {
    /// The titles the app lists, with their covers in Scrollkeeper's `folder` and, for those on disk in the
    /// shared download folder, the files the app opens.
    public func index(in folder: URL, for configuration: ScrollkeeperBridgeConfiguration) -> ScrollkeeperIndex {
        let files = downloadFolderURL(in: folder)
        let listed = titles.filter(configuration.lists).map { title in
            var entry = ScrollkeeperIndex.Entry(sku: title.sku, title: title.title,
                                                kind: configuration.showsKind ? title.kind : nil,
                                                series: title.series, number: title.number,
                                                downloaded: title.downloaded)
            entry.coverURL = title.coverURL(in: folder)
            entry.localFiles = files.map { title.filesToOpen(in: $0, accepting: configuration.opens) } ?? []
            return entry
        }
        return ScrollkeeperIndex(formatVersion: formatVersion, generatedAt: generatedAt, titles: listed)
    }
}

extension ScrollkeeperLibrary.Title {
    /// True when an edition is a file of an accepted type, or an archive Scrollkeeper unpacks, which may hold some.
    public func mayHold(_ accepts: (UTType) -> Bool) -> Bool {
        editions.contains { edition in
            let type = UTType(filenameExtension: URL(filePath: edition.path).pathExtension)
            return edition.isFolder || type.map(accepts) == true
        }
    }
}
