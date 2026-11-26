#if os(macOS)
import AppKit

/// A Mac page setup (`NSPrintInfo`) as data, for an app to keep in a document or in its preferences.
///
/// The archive keeps the whole setup: the printer, the orientation and a paper only that printer has, such as a
/// borderless size. A paper size alone would come back formatted for "Any Printer", where such a paper doesn't exist.
public enum PageSetupArchive {
    /// The page setup as data; nil if it can't be archived.
    public static func data(from setup: NSPrintInfo) -> Data? {
        try? NSKeyedArchiver.archivedData(withRootObject: setup, requiringSecureCoding: true)
    }

    /// The page setup the data was made from; nil when the data isn't a page setup.
    public static func setup(from data: Data) -> NSPrintInfo? {
        try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSPrintInfo.self, from: data)
    }
}

/// The page setup the user last confirmed, kept in `UserDefaults`, so that the next window, document or launch
/// starts from it instead of the system's default.
public struct PageSetupStore {
    /// The preference key unless the app names another.
    public static let defaultKey = "pageSetup"

    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = Self.defaultKey) {
        self.defaults = defaults
        self.key = key
    }

    /// The page setup that was saved; nil when none was, or when the saved one can no longer be read.
    public var savedSetup: NSPrintInfo? {
        defaults.data(forKey: key).flatMap(PageSetupArchive.setup(from:))
    }

    public func save(_ setup: NSPrintInfo) {
        if let data = PageSetupArchive.data(from: setup) { defaults.set(data, forKey: key) }
    }
}
#endif
