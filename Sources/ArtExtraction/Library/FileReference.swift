import Foundation

/// A file or folder outside the app's own folders, remembered by a bookmark so it can be found again after the
/// app restarts or the file is renamed: a PDF in Scrollkeeper's downloads, or the folder they are in.
public struct FileReference: Codable, Hashable, Sendable {
    public let bookmark: Data
    /// Where it was when remembered, for showing and for recognizing it again.
    public let path: String

    /// Remembers `url`, with access granted across launches where the system grants it (sandboxed apps, and every
    /// app on the iPad).
    public init(_ url: URL) throws {
        bookmark = try Self.bookmark(for: url)
        path = url.path
    }

    init(bookmark: Data, path: String) {
        self.bookmark = bookmark
        self.path = path
    }

    /// Runs `body` with the file's current location and access to it; nil when the file can't be found.
    public func withAccess<Result>(_ body: (URL) throws -> Result) rethrows -> Result? {
        guard let url = resolved() else { return nil }
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        guard FileManager.default.isReadableFile(atPath: url.path) else { return nil }
        return try body(url)
    }

    /// The file's current location, or nil when its bookmark no longer leads to it.
    func resolved() -> URL? {
        var stale = false
        for options in Self.resolutionOptions {
            if let url = try? URL(resolvingBookmarkData: bookmark, options: options, relativeTo: nil,
                                  bookmarkDataIsStale: &stale) {
                return url
            }
        }
        return nil
    }

    private static func bookmark(for url: URL) throws -> Data {
        #if os(macOS)
        // Outside the sandbox there is no security scope to keep; a plain bookmark still follows the file.
        if let scoped = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil,
                                              relativeTo: nil) {
            return scoped
        }
        #endif
        return try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    private static var resolutionOptions: [URL.BookmarkResolutionOptions] {
        #if os(macOS)
        [.withSecurityScope, []]
        #else
        [[]]
        #endif
    }
}
