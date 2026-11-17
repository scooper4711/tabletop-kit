import notify
import TablesideShared

/// The Darwin notification the shared library posts after each change (shared libraries R5.2). It carries no data:
/// a reader asks `SharedLibrary.changes(since:)` what changed.
public enum SharedLibraryChange {
    public static let notificationName = "io.github.scooper4711.tableside.shared-library-changed"

    /// Tells the other apps the library has changed.
    static func post() {
        notify_post(notificationName)
    }

    /// Calls `onChange` on the main actor after each change, in any app, until the observer is released.
    public static func observe(_ onChange: @escaping @MainActor @Sendable () -> Void) -> LibraryChangeObserver {
        LibraryChangeObserver(name: notificationName, onChange: onChange)
    }
}
