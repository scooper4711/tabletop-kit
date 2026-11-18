import Foundation

/// Whether the library syncs, for an app to show (library sync R2.5).
public enum SyncStatus: Equatable, Sendable {
    /// The build names no iCloud container: the app works on this device only.
    case unsupported
    /// Nobody is signed in to iCloud, or iCloud is off for the app.
    case unavailable
    case syncing
    case upToDate
    /// The user deleted the library's iCloud data: syncing waits for `LibrarySync.resume()`.
    case paused
    /// iCloud is full: syncing carries on when there is room.
    case storageFull
    /// Syncing stopped until the app next starts, with the reason.
    case failed(String)

    /// The status of an app that isn't syncing, by the container its build names: none when it has no entitlement.
    public static func withoutSync(containerIdentifier: String) -> SyncStatus {
        containerIdentifier.isEmpty ? .unsupported : .unavailable
    }
}

/// What syncing is busy with.
enum SyncActivity: Hashable {
    case fetching, sending, pictures
}

/// Works out the status from what syncing is doing and what is wrong, and tells those following it.
struct SyncStatusTracker {
    private var activities: Set<SyncActivity> = []
    private var problem: SyncStatus?
    private var followers: [AsyncStream<SyncStatus>.Continuation] = []

    /// What is wrong, when something is; otherwise whether anything is under way.
    var status: SyncStatus {
        problem ?? (activities.isEmpty ? .upToDate : .syncing)
    }

    mutating func begin(_ activity: SyncActivity) {
        change { $0.activities.insert(activity) }
    }

    mutating func end(_ activity: SyncActivity) {
        change { $0.activities.remove(activity) }
    }

    /// Notes what is wrong, until it is cleared. A failure stays whatever is reported after it.
    mutating func report(_ problem: SyncStatus) {
        if case .failed = self.problem { return }
        change { $0.problem = problem }
    }

    /// Notes that `problem` is over, when it is the one reported.
    mutating func clear(_ problem: SyncStatus) {
        guard self.problem == problem else { return }
        change { $0.problem = nil }
    }

    /// The status now and after each change.
    mutating func updates() -> AsyncStream<SyncStatus> {
        let (stream, continuation) = AsyncStream.makeStream(of: SyncStatus.self, bufferingPolicy: .bufferingNewest(1))
        continuation.yield(status)
        followers.append(continuation)
        return stream
    }

    private mutating func change(_ body: (inout SyncStatusTracker) -> Void) {
        let before = status
        body(&self)
        guard status != before else { return }
        followers = followers.filter { follower in
            if case .terminated = follower.yield(status) { false } else { true }
        }
    }
}
