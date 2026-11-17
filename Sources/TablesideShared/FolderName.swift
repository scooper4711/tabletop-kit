import Foundation

/// How a folder, or the folder of a file, is shown in the Tableside Toolkit apps: by a name and where it is, rather
/// than by its path. Scrollkeeper's downloads read "Scrollkeeper ▸ <title folder>", wherever they are: the App
/// Group folder the toolkit shares (on the Mac or the iPhone and iPad), Scrollkeeper's folder before it ran in the
/// sandbox, or on the iPhone and iPad an app's Documents folder, which the system names only "Documents" and the apps
/// only watch through Import from Scrollkeeper.
public struct FolderName: Equatable, Sendable {
    public let title: String
    public let location: String

    public init(title: String, location: String) {
        self.title = title
        self.location = location
    }

    /// The name of `folder`; `homeDirectory` is shortened to `~` in the location of other folders.
    public init(url folder: URL, homeDirectory: String = NSHomeDirectory()) {
        self.init(path: folder.path(percentEncoded: false), homeDirectory: homeDirectory)
    }

    /// The name of the folder at `path`; `homeDirectory` is shortened to `~` in the location of other folders.
    public init(path: String, homeDirectory: String = NSHomeDirectory()) {
        let components = path.split(separator: "/").map(String.init)
        if let inside = Self.components(of: components, after: Self.iOSDocuments)
            ?? Self.components(of: components, after: Self.iOSSharedDownloads) {
            self = Self.scrollkeeper(inside, location: Self.onThisDevice)
        } else if let inside = Self.components(of: components, after: Self.sharedDownloads)
                    ?? Self.components(of: components, after: Self.macDownloads) {
            self = Self.scrollkeeper(inside, location: "On this Mac")
        } else {
            let folder = URL(filePath: path, directoryHint: .isDirectory)
            let parent = folder.deletingLastPathComponent().path(percentEncoded: false)
            self.init(title: folder.lastPathComponent, location: Self.shortened(parent, homeDirectory: homeDirectory))
        }
    }

    /// Where a file is, as its folder's name and place; `place` is returned as it is when it isn't a path.
    public static func place(ofFile place: String, homeDirectory: String = NSHomeDirectory()) -> String {
        guard place.hasPrefix("/") else { return place }
        let folder = URL(filePath: place).deletingLastPathComponent().path(percentEncoded: false)
        let name = FolderName(path: folder, homeDirectory: homeDirectory)
        return "\(name.title) · \(name.location)"
    }

    /// Where the iPhone and iPad keep the apps' own folders, as the Files app names it: "On My iPhone" or
    /// "On My iPad".
    public static let onThisDevice = deviceLocation(machine: hardwareModel())

    /// "On My iPhone" for an iPhone's hardware model (such as `iPhone17,1`), otherwise "On My iPad".
    static func deviceLocation(machine: String) -> String {
        machine.hasPrefix("iPhone") ? "On My iPhone" : "On My iPad"
    }

    /// An app's Documents folder on the iPhone and iPad: `…/Containers/Data/Application/<app>/Documents`; nil stands
    /// for the app's own component.
    private static let iOSDocuments: [String?] = ["Containers", "Data", "Application", nil, "Documents"]
    /// Scrollkeeper's download folder in the App Group the toolkit shares on the iPhone and iPad.
    private static let iOSSharedDownloads: [String?] = [
        "Containers", "Shared", "AppGroup", nil, "Scrollkeeper", "Files"
    ]
    /// Scrollkeeper's download folder in the App Group the toolkit shares on the Mac (`ToolkitGroup`).
    private static let sharedDownloads: [String?] = ["Group Containers", nil, "Scrollkeeper", "Files"]
    /// Scrollkeeper's download folder on the Mac before it ran in the sandbox, or a build outside the App Group.
    private static let macDownloads: [String?] = ["Library", "Application Support", "Scrollkeeper", "Files"]

    private static func scrollkeeper(_ inside: [String], location: String) -> FolderName {
        FolderName(title: (["Scrollkeeper"] + inside).joined(separator: " ▸ "), location: location)
    }

    /// The components after the first run matching `pattern`, or nil when no run matches.
    private static func components(of components: [String], after pattern: [String?]) -> [String]? {
        guard components.count >= pattern.count else { return nil }
        for start in 0...(components.count - pattern.count) {
            let run = components[start..<(start + pattern.count)]
            if zip(run, pattern).allSatisfy({ component, expected in expected.map { $0 == component } ?? true }) {
                return Array(components[(start + pattern.count)...])
            }
        }
        return nil
    }

    /// The hardware model, such as `iPhone17,1`; the simulator reports the model it simulates. Empty off iOS.
    private static func hardwareModel() -> String {
        #if os(iOS)
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] { return simulated }
        var size = 0
        guard sysctlbyname("hw.machine", nil, &size, nil, 0) == 0, size > 0 else { return "" }
        var model = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.machine", &model, &size, nil, 0) == 0 else { return "" }
        return String(cString: model)
        #else
        return ""
        #endif
    }

    private static func shortened(_ path: String, homeDirectory: String) -> String {
        let home = homeDirectory.hasSuffix("/") ? String(homeDirectory.dropLast()) : homeDirectory
        let trimmed = path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
        guard !home.isEmpty, trimmed == home || trimmed.hasPrefix(home + "/") else { return trimmed }
        return "~" + trimmed.dropFirst(home.count)
    }
}
