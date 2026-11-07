import Foundation

/// Scrollkeeper's list of the library, `library.json` in its folder in the App Group (`ToolkitGroup`): every title
/// with a file to download, its editions and where they are kept. Scrollkeeper writes it whenever it changes; the
/// other toolkit apps read it.
///
/// Keys are stable and new fields may be added without a version change; a change that breaks readers raises
/// `formatVersion`.
public struct ScrollkeeperLibrary: Codable, Equatable, Sendable {
    public struct Title: Codable, Equatable, Sendable {
        public var sku: String
        public var title: String
        /// The product type, such as "Adventures", "Maps" or "Society Scenarios".
        public var kind: String
        /// The game, such as "Pathfinder 2E".
        public var gameSystem: String
        public var series: String?
        public var number: Int?
        public var levels: Levels?
        /// The cover's path in Scrollkeeper's folder, such as `Covers/PZO1E.jpg`; nil until one is stored.
        public var cover: String?
        /// True when an up-to-date copy is on disk.
        public var downloaded: Bool
        public var editions: [Edition]

        public init(sku: String, title: String, kind: String, gameSystem: String, series: String? = nil,
                    number: Int? = nil, levels: Levels? = nil, cover: String? = nil, downloaded: Bool = false,
                    editions: [Edition] = []) {
            self.sku = sku
            self.title = title
            self.kind = kind
            self.gameSystem = gameSystem
            self.series = series
            self.number = number
            self.levels = levels
            self.cover = cover
            self.downloaded = downloaded
            self.editions = editions
        }
    }

    public struct Levels: Codable, Equatable, Sendable {
        public var lowest: Int
        public var highest: Int

        public init(lowest: Int, highest: Int) {
            self.lowest = lowest
            self.highest = highest
        }
    }

    public struct Edition: Codable, Equatable, Sendable {
        public var name: String
        /// "Single File", "File per Chapter" and so on; nil when Paizo's name says nothing about it.
        public var kind: String?
        /// Where the edition is kept, relative to the download folder: `<title>/<edition>.<ext>`, or for an
        /// archive unpacked after download `<title>/<edition>`, a folder.
        public var path: String
        public var isFolder: Bool
        public var downloaded: Bool
        /// True when Paizo has updated the file since it was downloaded.
        public var outdated: Bool

        public init(name: String, kind: String? = nil, path: String, isFolder: Bool = false,
                    downloaded: Bool = false, outdated: Bool = false) {
            self.name = name
            self.kind = kind
            self.path = path
            self.isFolder = isFolder
            self.downloaded = downloaded
            self.outdated = outdated
        }
    }

    /// Where the downloads are: Scrollkeeper's folder's `Files`, or a folder the user chose, whose path is given
    /// (other apps can only reach it if the user picks it for them).
    public struct DownloadFolder: Codable, Equatable, Sendable {
        public var isShared: Bool
        public var path: String?

        public init(isShared: Bool, path: String? = nil) {
            self.isShared = isShared
            self.path = path
        }
    }

    /// Raised when a change would break readers.
    public static let currentFormatVersion = 1
    public static let fileName = "library.json"

    public var formatVersion = currentFormatVersion
    public var generatedAt: Date
    public var downloadFolder: DownloadFolder
    public var titles: [Title]

    public init(generatedAt: Date, downloadFolder: DownloadFolder, titles: [Title]) {
        self.generatedAt = generatedAt
        self.downloadFolder = downloadFolder
        self.titles = titles
    }

    /// The shared download folder in Scrollkeeper's `folder`; nil when the downloads are in a folder the user chose.
    public func downloadFolderURL(in folder: URL) -> URL? {
        downloadFolder.isShared ? folder.appending(path: "Files", directoryHint: .isDirectory) : nil
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(self)
    }
}

extension ScrollkeeperLibrary.Title {
    /// The cover in Scrollkeeper's `folder`, when one is stored.
    public func coverURL(in folder: URL) -> URL? {
        cover.map { folder.appending(path: $0) }
    }
}
