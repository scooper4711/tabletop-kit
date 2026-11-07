# Tableside Shared: design

A library target with no dependencies, `TablesideShared`, for macOS 14 and
iOS 17 like Scrollkeeper (the package's platforms were lowered from macOS 15
and iOS 18 for it; the other libraries build there unchanged).

- **`ToolkitGroup`.** `containerURL()` gives
  `FileManager.containerURL(forSecurityApplicationGroupIdentifier:)` for the
  group: on the Mac the one among the app's
  `com.apple.security.application-groups` (read with
  `SecTaskCopyValueForEntitlement`) that ends in
  `.io.github.scooper4711.tableside`; on iOS
  `group.io.github.scooper4711.tableside`. `scrollkeeperFolder()` is its
  `Scrollkeeper/`. Both are nil outside the group. Each app's
  `scripts/build-app.sh` puts the team ID in place of `TEAM_ID` in its
  entitlements and leaves the group out of an ad hoc build.
- **`ScrollkeeperLibrary`.** The `Codable` model of `library.json`: `Title`,
  `Levels`, `Edition` and `DownloadFolder`, with public initializers for the
  writer. `encoded()` writes ISO 8601 dates and sorted keys, leaving out empty
  optionals. `downloadFolderURL(in:)` is the shared `Files/`, or nil for a
  folder the user chose; `Title.coverURL(in:)` the cover.
- **Reading.** `ScrollkeeperLibrary.read(from:)` returns a
  `ScrollkeeperLibraryReading`: `missing`, `unreadable`, `newerFormat` (decided
  from `formatVersion` alone, before the rest is decoded) or `loaded`.
- **Choosing files.** `Title.filesToOpen(in:accepting:)` takes the reader's
  test of a `UTType`: Mapsmith accepts PDFs and images, Pluck PDFs. Archive
  folders are listed recursively, skipping hidden files, in
  `localizedStandardCompare` order.
- **Changes.** `LibraryChange.post()` sends the Darwin notification
  `io.github.scooper4711.tableside.library-changed` (`notify_post`).
  `LibraryChangeObserver(onChange:)` registers for it with
  `notify_register_dispatch` on the main queue and cancels the registration
  when released; the app keeps it for as long as it wants to hear.
