import Foundation
#if os(macOS)
import Security
#endif

/// The App Group the Tableside Toolkit apps share. On the Mac its identifier starts with the team ID,
/// `<team ID>.io.github.scooper4711.tableside`, which is never committed: each app's build fills it in, and this
/// reads it back from the app's own entitlements. iOS requires `group.io.github.scooper4711.tableside`.
public enum ToolkitGroup {
    /// The Mac group's name after the team ID.
    static let macSuffix = ".io.github.scooper4711.tableside"
    /// The iOS group's identifier.
    static let iOSIdentifier = "group.io.github.scooper4711.tableside"

    /// The group's container, or nil when the app isn't signed into the group: an ad hoc development build, or a
    /// run outside an app bundle such as the tests.
    public static func containerURL() -> URL? {
        identifier().flatMap(FileManager.default.containerURL(forSecurityApplicationGroupIdentifier:))
    }

    /// Scrollkeeper's folder in the container, holding its downloads, covers and library list
    /// (`ScrollkeeperLibrary`). Only Scrollkeeper writes there.
    public static func scrollkeeperFolder() -> URL? {
        containerURL()?.appending(path: "Scrollkeeper", directoryHint: .isDirectory)
    }

    /// The toolkit's Mac group among those an app is signed with.
    static func macIdentifier(among groups: [String]) -> String? {
        groups.first { $0.hasSuffix(macSuffix) }
    }

    private static func identifier() -> String? {
        #if os(macOS)
        macIdentifier(among: signedGroups())
        #else
        iOSIdentifier
        #endif
    }

    #if os(macOS)
    /// The App Groups in the app's own entitlements, which name the team the app was signed by.
    private static func signedGroups() -> [String] {
        guard let task = SecTaskCreateFromSelf(nil),
              let value = SecTaskCopyValueForEntitlement(task, "com.apple.security.application-groups" as CFString, nil)
        else { return [] }
        return value as? [String] ?? []
    }
    #endif
}
