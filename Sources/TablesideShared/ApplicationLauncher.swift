import Foundation
#if os(macOS)
import AppKit
#endif

/// What the Scrollkeeper bridge needs from the system to work with another app. The Mac apps use
/// `WorkspaceLauncher`, an iPad app its own on `UIApplication`; tests use a fake.
@MainActor
public protocol ApplicationLauncher {
    /// Whether Scrollkeeper here answers requests from other apps in the background and reports how they go. Only
    /// the Mac's does; on the iPad a request brings Scrollkeeper forward to download the title, and the app reads
    /// the shared library for the rest.
    var takesRequests: Bool { get }
    func isInstalled(_ bundleIdentifier: String) -> Bool
    /// Opens the URL without bringing its app to the front.
    func openInBackground(_ url: URL)
    /// Opens the URL, bringing its app to the front.
    func openInForeground(_ url: URL)
    func launch(_ bundleIdentifier: String)
}

extension ApplicationLauncher {
    public var takesRequests: Bool { true }

    /// A launcher that can't open a link in the foreground brings Scrollkeeper forward without it.
    public func openInForeground(_: URL) {
        launch(ScrollkeeperBridge.bundleIdentifier)
    }
}

#if os(macOS)
/// The Mac's side of `ApplicationLauncher`.
public struct WorkspaceLauncher: ApplicationLauncher {
    public init() {}

    public func isInstalled(_ bundleIdentifier: String) -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) != nil
    }

    public func openInBackground(_ url: URL) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        NSWorkspace.shared.open(url, configuration: configuration)
    }

    public func openInForeground(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    public func launch(_ bundleIdentifier: String) {
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else { return }
        NSWorkspace.shared.openApplication(at: app, configuration: .init())
    }
}
#endif
