import ArtExtraction
import SharedLibraries
import Bestiary
import CoreGraphics
import Foundation

/// A PDF in the art library, as the settings show it.
public struct ArtSourceSummary: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    /// Where it is: "Kept in the app", or the file's path.
    public let place: String
    public let isMissing: Bool
    /// True when art this PDF prints can't be shown: it has no picture, here or in iCloud, and no PDF is reachable.
    public let hasLostArt: Bool
    /// How many pieces of art the library has from it.
    public let artCount: Int
}

/// What the art library holds, for matching creatures and for the settings.
public struct ArtCatalog: Sendable {
    public var art: [LibraryArt] = []
    public var sources: [ArtSourceSummary] = []
    /// The folders whose new PDFs are added, such as Scrollkeeper's downloads.
    public var watchedFolders: [String] = []

    public init(art: [LibraryArt] = [], sources: [ArtSourceSummary] = [], watchedFolders: [String] = []) {
        self.art = art
        self.sources = sources
        self.watchedFolders = watchedFolders
    }

    public var missingSources: [ArtSourceSummary] { sources.filter(\.isMissing) }
    /// The PDFs that need the user's attention, because art depends on them. A PDF on another device whose pictures
    /// are in iCloud isn't one.
    public var sourcesWithLostArt: [ArtSourceSummary] { sources.filter(\.hasLostArt) }
}

/// What adding PDFs did, for a status message.
public struct ArtImportSummary: Sendable {
    public var pdfs = 0
    public var added = 0
    public var failures: [String] = []

    public var message: String {
        var text = pdfs == 0 ? "No new PDFs of creature art." : "Read \(pdfs) PDF\(pdfs == 1 ? "" : "s"): \(added) "
            + "new pieces of creature art."
        if !failures.isEmpty { text += " Could not read: \(failures.joined(separator: "; "))." }
        return text
    }
}

private extension ArtImportReport {
    /// True when this app read the PDF: the library didn't have it already (a watched folder then only links it
    /// to this app), and no other app was reading it.
    var wasReadHere: Bool { !wasImported && !isReadByAnotherApp }
}

/// The creature art from the user's own Paizo PDFs, and the catalog the apps match creatures against
/// (`LibraryArtMatcher`): kept in the library the three apps share (`SharedLibrary`), or in an art library of the
/// app's own (`ArtLibrary`) until the app moves into the shared one. Reading PDFs and drawing art take a while, so
/// they happen here, off the main thread.
public actor CreatureArtStore {
    /// Products whose art is the remastered art.
    public static let remasteredProducts = ["Monster Core", "NPC Core", "Alien Core", "Howl of the Wild",
                                            "Rage of Elements"]

    enum Library {
        case own(ArtLibrary)
        case shared(SharedLibrary)
    }

    let library: Library
    private let pictures = NSCache<NSString, CGImage>()

    /// The app's own art library in `folder`.
    public init(folder: URL) throws {
        library = .own(try ArtLibrary(folder: folder))
    }

    /// The shared library in `folder` (shared libraries R1), for `app`.
    public init(sharedLibraryIn folder: URL, app: TablesideApp) throws {
        library = .shared(try SharedLibrary(folder: folder, app: app))
    }

    /// The shared library in the App Group's `Tableside` folder, or in `fallback` outside the group (R1.2).
    public init(sharedLibraryFor app: TablesideApp, fallback: URL) throws {
        library = .shared(try SharedLibrary.standard(app: app, fallback: fallback))
    }

    /// Moves the app's own library into the shared one (R6); nil when it has moved in already, or when this store
    /// keeps the app's own library.
    public func moveIn(_ move: LibraryMove) throws -> MoveReport? {
        guard case .shared(let library) = library else { return nil }
        pictures.removeAllObjects()
        return try library.moveIn(move)
    }

    /// Closes the shared library's database while the app is in the background (R5.4).
    public func close() {
        if case .shared(let library) = library { library.close() }
    }

    /// What the library holds now, each PDF checked again for whether it is still there.
    public func catalog() -> ArtCatalog {
        switch library {
        case .own(let library): Self.catalog(of: library)
        case .shared(let library): Self.catalog(of: library)
        }
    }

    /// Watches `folder` (Scrollkeeper's downloads) and adds its PDFs of art by reference.
    public func importFolder(_ folder: URL, progress: @Sendable (String) -> Void) -> ArtImportSummary {
        let accessing = folder.startAccessingSecurityScopedResource()
        defer { if accessing { folder.stopAccessingSecurityScopedResource() } }
        do {
            switch library {
            case .own(let library): try library.watch(folder)
            case .shared(let library): try library.watch(folder)
            }
        } catch {
            return ArtImportSummary(failures: [error.localizedDescription])
        }
        return addNewFiles(progress: progress)
    }

    /// Adds the PDFs that have appeared in the watched folders since they were last read.
    public func addNewFiles(progress: @Sendable (String) -> Void = { _ in }) -> ArtImportSummary {
        let results = switch library {
        case .own(let library): library.addNewFiles(progress: progress)
        case .shared(let library): library.addNewFiles(progress: progress)
        }
        var summary = ArtImportSummary()
        for result in results {
            switch result {
            case .success(let report):
                if report.wasReadHere { summary.pdfs += 1 }
                summary.added += report.added
            case .failure(let error):
                summary.pdfs += 1
                summary.failures.append(error.localizedDescription)
            }
        }
        return summary
    }

    /// Adds PDFs the user chose, keeping copies of them.
    public func addFiles(_ files: [URL], progress: @Sendable (String) -> Void) -> ArtImportSummary {
        var summary = ArtImportSummary()
        for file in files {
            progress(file.lastPathComponent)
            let accessing = file.startAccessingSecurityScopedResource()
            defer { if accessing { file.stopAccessingSecurityScopedResource() } }
            do {
                let report = switch library {
                case .own(let library): try library.add(file, keeping: true)
                case .shared(let library): try library.add(file, keeping: true)
                }
                if report.wasReadHere { summary.pdfs += 1 }
                summary.added += report.added
            } catch {
                summary.failures.append("\(file.lastPathComponent): \(error.localizedDescription)")
            }
        }
        return summary
    }

    /// Takes a PDF and the art only it prints out of the library.
    public func removeSource(id: String) throws {
        switch library {
        case .own(let library):
            guard let source = library.source(id: id) else { return }
            try library.remove(source)
        case .shared(let library):
            try library.remove(sourceID: id)
        }
        pictures.removeAllObjects()
    }

    public func unwatch(_ path: String) throws {
        switch library {
        case .own(let library):
            for folder in library.watchedFolders where folder.path == path { try library.unwatch(folder) }
        case .shared(let library):
            try library.unwatch(path: path)
        }
    }

    /// A piece of art drawn alone and upright, at most `maxPixels` on its long side; nil when it can't be drawn.
    /// In the shared library, `id` can be an ID the app gave the art before it moved in.
    public func picture(id: UUID, maxPixels: Int) -> CGImage? {
        let key = "\(id.uuidString)#\(maxPixels)" as NSString
        if let cached = pictures.object(forKey: key) { return cached }
        let image: CGImage? = switch library {
        case .own(let library):
            library.entries.first { $0.id == id }.flatMap { library.picture(of: $0, maxPixels: maxPixels) }
        case .shared(let library):
            (try? library.artEntry(id: id)).flatMap { $0 }.flatMap { library.picture(of: $0, maxPixels: maxPixels) }
        }
        if let image { pictures.setObject(image, forKey: key) }
        return image
    }
}
