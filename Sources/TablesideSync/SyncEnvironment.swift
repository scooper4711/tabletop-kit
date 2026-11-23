import Foundation

/// The CloudKit environment a build syncs with (R6.3). The two hold separate data, while a device's shared library
/// is one: what it remembers of the cloud is valid for one environment only.
public enum SyncEnvironment: String, Sendable {
    case production = "Production"
    case development = "Development"

    /// The `Info.plist` key that names the environment. A build without it syncs with Production.
    public static let bundleKey = "TablesideSyncEnvironment"

    /// The environment this build names.
    public static var bundle: SyncEnvironment {
        named(Bundle.main.object(forInfoDictionaryKey: bundleKey) as? String)
    }

    static func named(_ name: String?) -> SyncEnvironment {
        SyncEnvironment(rawValue: name ?? "") ?? .production
    }

    /// The account as sync records it. Development's differs from Production's, so moving between them is an
    /// account change: what was known of the cloud is forgotten and the library merges afresh. Production keeps the
    /// plain name, so that released apps, which know nothing of environments, read it the same way.
    func accountName(of user: String) -> String {
        self == .production ? user : "\(rawValue):\(user)"
    }
}
