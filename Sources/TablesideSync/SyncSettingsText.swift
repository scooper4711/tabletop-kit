import Foundation
import SharedLibraries

/// What an app's sync settings say (R2.5, R4.3): whether the library syncs, and how big the downloaded pictures are.
public enum SyncSettingsText {
    /// Whether `app`'s library syncs, in words, and why not when it doesn't.
    public static func summary(of status: SyncStatus, app: TablesideApp) -> String {
        let name = app.rawValue
        return switch status {
        case .unsupported:
            "This copy of \(name) was built without iCloud, so its library stays on this device."
        case .unavailable:
            "Not syncing. Sign in to iCloud and turn iCloud on for \(name) in the system's settings, then open "
                + "\(name) again."
        case .syncing:
            "Syncing…"
        case .upToDate:
            "The library is up to date with iCloud."
        case .paused:
            "Syncing is paused, because the library's iCloud data was deleted."
        case .storageFull:
            "iCloud is full. Syncing carries on when there is room."
        case .failed(let reason):
            "Syncing stopped, and starts again when \(name) next opens. \(reason)"
        }
    }

    /// What the picker of `PictureKeeping` is about, in `app`: the setting is the device's, for every app.
    public static func keepingNote(app: TablesideApp) -> String {
        let others = TablesideApp.allCases.filter { $0 != app }.map(\.rawValue)
        return "This setting is this device's, and \(others.joined(separator: " and ")) share it."
    }

    /// The size of the downloaded pictures, such as "38 MB".
    public static func size(ofBytes bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}

/// How many downloaded pictures a device keeps (R4.7, R4.9), over `PicturePolicy`, as the settings offer it.
public enum PictureKeeping: Hashable, Sendable {
    /// A picture downloads when it is first shown, and none is removed.
    case shown
    /// As `shown`, but past this many bytes the least recently shown are removed.
    case upTo(Int)
    /// Every picture is downloaded ahead of time, for use without a connection.
    case everything

    /// The limits offered: 250 MB, 500 MB, 1 GB and 2 GB.
    public static let limits = [250, 500, 1_000, 2_000].map { $0 * 1_000_000 }

    public init(_ policy: PicturePolicy) {
        switch policy {
        case .onDemand(nil): self = .shown
        case .onDemand(let limit?): self = .upTo(limit)
        case .everything: self = .everything
        }
    }

    public var policy: PicturePolicy {
        switch self {
        case .shown: .onDemand(limit: nil)
        case .upTo(let limit): .onDemand(limit: limit)
        case .everything: .everything
        }
    }

    public var title: String {
        switch self {
        case .shown: "The pictures shown"
        case .upTo(let limit): "Up to \(SyncSettingsText.size(ofBytes: limit))"
        case .everything: "Every picture"
        }
    }

    /// The choices to offer, in order; a limit another app set that isn't one of `limits` is listed as it is.
    public static func choices(including current: PictureKeeping) -> [PictureKeeping] {
        var sizes = limits
        if case .upTo(let limit) = current, !sizes.contains(limit) { sizes.append(limit) }
        return [.shown] + sizes.sorted().map(PictureKeeping.upTo) + [.everything]
    }
}
