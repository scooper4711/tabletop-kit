import Foundation
import SharedLibraries

/// A library an actor keeps to itself, as `SharedLibrary` isn't safe to share. After `close()`, as when the app goes
/// to the background on the iPad, every use closes the database again when it is done, until `open()`: a suspended
/// app holding a lock on a file in the group's container is ended (shared libraries R5.4).
final class LibraryHandle {
    private let library: SharedLibrary
    private var closesAfterUse = false

    init(folder: URL, app: TablesideApp) throws {
        library = try SharedLibrary(folder: folder, app: app)
    }

    /// Runs `body` on the library.
    func use<Result>(_ body: (SharedLibrary) throws -> Result) rethrows -> Result {
        defer { if closesAfterUse { library.close() } }
        return try body(library)
    }

    func close() {
        closesAfterUse = true
        library.close()
    }

    func open() {
        closesAfterUse = false
    }
}
