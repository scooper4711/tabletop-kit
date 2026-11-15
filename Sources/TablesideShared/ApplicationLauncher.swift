import Foundation
#if os(macOS)
import AppKit
#endif

/// What the Scrollkeeper bridge needs from the system to work with another app. The Mac apps use
/// `WorkspaceLauncher`, an iPad app its own on `UIApplication`; tests use a fake.
@MainActor
public protocol ApplicationLauncher {
    /// Whether Scrollkeeper here answers requests from other apps. Only the Mac's does; on the iPad an app reads
    /// the shared library and nothing else.
    var takesRequests: Bool { get }
    func isInstalled(_ bundleIdentifier: String) -> Bool
    /// Opens the URL without bringing its app to the front.
    func openInBackground(_ url: URL)
    func launch(_ bundleIdentifier: String)
}

extension ApplicationLauncher {
    public var takesRequests: Bool { true }
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

    public func launch(_ bundleIdentifier: String) {
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else { return }
        NSWorkspace.shared.openApplication(at: app, configuration: .init())
    }
}
#endif
