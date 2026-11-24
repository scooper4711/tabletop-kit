import SharedLibraries
import SwiftUI
import TablesideSync

/// An app's sync settings, as a section of a `Form` (library sync R2.5, R4.3, R4.7, R4.9): whether the library
/// syncs, a way to turn syncing back on after its iCloud data was deleted (R5.3), how many downloaded pictures this
/// device keeps, and how much room they take, with a way to remove them.
public struct SyncSettingsSection: View {
    private let app: TablesideApp
    private let sync: LibrarySync?
    @Binding private var picturesChanged: Int
    @State private var status: SyncStatus
    @State private var keeping = PictureKeeping.shown
    /// What the device keeps as last read, to tell the user's choice from the picker being filled in.
    @State private var keptNow = PictureKeeping.shown
    @State private var downloadedBytes = 0
    @State private var failure: String?

    /// `sync` is nil while the library doesn't sync. `picturesChanged` counts changes to the downloaded pictures:
    /// their size is read again when it changes, and removing them adds one, so that what shows them draws again.
    public init(app: TablesideApp, sync: LibrarySync?, picturesChanged: Binding<Int>) {
        self.app = app
        self.sync = sync
        _picturesChanged = picturesChanged
        _status = State(initialValue: .withoutSync(containerIdentifier: LibrarySync.bundleContainer))
    }

    public var body: some View {
        Section("iCloud") {
            Text(SyncSettingsText.summary(of: status, app: app))
                .fixedSize(horizontal: false, vertical: true)
            if status == .paused, let sync {
                Button("Turn Syncing Back On") { Task { await sync.resume() } }
            }
            if let failure { note(failure) }
            if let sync { pictures(sync) }
        }
        .task(id: sync.map(ObjectIdentifier.init)) { await followStatus() }
        .task(id: Shown(isSyncing: sync != nil, picturesChanged: picturesChanged)) { await read() }
    }

    @ViewBuilder private func pictures(_ sync: LibrarySync) -> some View {
        Picker("Keep on this device", selection: $keeping) {
            ForEach(PictureKeeping.choices(including: keeping), id: \.self) { choice in
                Text(choice.title).tag(choice)
            }
        }
        .onChange(of: keeping) { _, chosen in
            guard chosen != keptNow else { return }
            keptNow = chosen
            Task { await keep(chosen, in: sync) }
        }
        note(SyncSettingsText.keepingNote(app: app))
        LabeledContent("Downloaded pictures") {
            Text(SyncSettingsText.size(ofBytes: downloadedBytes)).monospacedDigit()
        }
        Button("Remove Downloaded Pictures") { Task { await removePictures(from: sync) } }
            .disabled(downloadedBytes == 0)
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func followStatus() async {
        guard let sync else {
            status = .withoutSync(containerIdentifier: LibrarySync.bundleContainer)
            return
        }
        for await update in await sync.statusUpdates() { status = update }
    }

    /// Reads what the device keeps and how much it has downloaded.
    private func read() async {
        guard let sync else { return }
        if let policy = try? await sync.picturePolicy() {
            keptNow = PictureKeeping(policy)
            keeping = keptNow
        }
        downloadedBytes = (try? await sync.fetchedPicturesByteCount()) ?? 0
    }

    private func keep(_ chosen: PictureKeeping, in sync: LibrarySync) async {
        do {
            try await sync.setPicturePolicy(chosen.policy)
            failure = nil
        } catch {
            failure = "Changing how many pictures are kept failed: \(error.localizedDescription)"
        }
        picturesChanged += 1
    }

    private func removePictures(from sync: LibrarySync) async {
        do {
            try await sync.clearFetchedPictures()
            failure = nil
        } catch {
            failure = "Removing the downloaded pictures failed: \(error.localizedDescription)"
        }
        picturesChanged += 1
    }

    /// What the section shows: read again once syncing starts and when the pictures change.
    private struct Shown: Hashable {
        let isSyncing: Bool
        let picturesChanged: Int
    }
}
