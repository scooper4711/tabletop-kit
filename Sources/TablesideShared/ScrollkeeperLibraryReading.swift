import Foundation
import UniformTypeIdentifiers

/// What a reader found when it looked for Scrollkeeper's library list.
public enum ScrollkeeperLibraryReading: Equatable, Sendable {
    /// No list: Scrollkeeper isn't in the group, or hasn't synced yet.
    case missing
    case unreadable
    /// The list is in a format newer than this reader understands; it may ask Scrollkeeper some other way.
    case newerFormat
    case loaded(ScrollkeeperLibrary)
}

extension ScrollkeeperLibrary {
    /// Reads the list in Scrollkeeper's `folder`, checking its format version before trusting the rest.
    public static func read(from folder: URL) -> ScrollkeeperLibraryReading {
        guard let data = try? Data(contentsOf: folder.appending(path: fileName)) else { return .missing }
        return decoded(from: data)
    }

    static func decoded(from data: Data) -> ScrollkeeperLibraryReading {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let header = try? decoder.decode(FormatHeader.self, from: data) else { return .unreadable }
        guard header.formatVersion <= currentFormatVersion else { return .newerFormat }
        guard let library = try? decoder.decode(ScrollkeeperLibrary.self, from: data) else { return .unreadable }
        return .loaded(library)
    }

    private struct FormatHeader: Decodable {
        var formatVersion: Int
    }
}

extension ScrollkeeperLibrary.Title {
    /// The files of the title to open from `downloadFolder`, chosen as Scrollkeeper chooses them for a handoff (its
    /// app-handoff requirements 2.3 and 2.5): an up-to-date single file of an accepted type first; otherwise the
    /// accepted files under the first up-to-date unpacked archive, and of those only the PDFs when there are any.
    /// Empty when nothing suitable is on disk.
    public func filesToOpen(in downloadFolder: URL, accepting accepts: (UTType) -> Bool) -> [URL] {
        func isAccepted(_ file: URL) -> Bool {
            UTType(filenameExtension: file.pathExtension).map(accepts) ?? false
        }
        let ready = editions.filter { $0.downloaded && !$0.outdated }
        if let single = ready.first(where: { !$0.isFolder && isAccepted(URL(filePath: $0.path)) }) {
            return [downloadFolder.appending(path: single.path)]
        }
        guard let archive = ready.first(where: \.isFolder) else { return [] }
        let accepted = Self.regularFiles(under: downloadFolder.appending(path: archive.path)).filter(isAccepted)
        let pdfs = accepted.filter { UTType(filenameExtension: $0.pathExtension)?.conforms(to: .pdf) == true }
        return pdfs.isEmpty ? accepted : pdfs
    }

    private static func regularFiles(under folder: URL) -> [URL] {
        let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey],
                                                        options: .skipsHiddenFiles)
        let files = (enumerator?.compactMap { $0 as? URL } ?? []).filter { url in
            (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        }
        return files.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }
}
