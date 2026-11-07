import Foundation
import notify

/// The Darwin notification Scrollkeeper sends after it writes its library list, so readers can refresh without
/// polling. Darwin notifications carry no data and work in the App Sandbox.
public enum LibraryChange {
    public static let notificationName = "io.github.scooper4711.tableside.library-changed"

    /// Tells the readers the list has changed.
    public static func post() {
        notify_post(notificationName)
    }
}

/// Calls `onChange` on the main actor each time Scrollkeeper's library list changes, until it is released.
public final class LibraryChangeObserver {
    private var token: Int32 = NOTIFY_TOKEN_INVALID

    public init(onChange: @escaping @MainActor @Sendable () -> Void) {
        notify_register_dispatch(LibraryChange.notificationName, &token, .main) { _ in
            MainActor.assumeIsolated { onChange() }
        }
    }

    deinit {
        notify_cancel(token)
    }
}
