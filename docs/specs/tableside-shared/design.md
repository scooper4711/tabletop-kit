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
- **`FolderName`** (R4, from Field Guide). `init(path:)` or `init(url:)` gives a `title` and a `location`. It
  looks for a run of path components: `Group Containers/<group>/Scrollkeeper/Files` or
  `Library/Application Support/Scrollkeeper/Files` (also inside Scrollkeeper's own container) is "On this Mac",
  and `Containers/Data/Application/<app>/Documents` is "On My iPad"; the title is "Scrollkeeper" and the
  components after the run, joined with " ▸ ". Any other folder is its last component, in its parent with the
  home folder shortened to `~`. `place(ofFile:)` gives "<title> · <location>" for a file's folder, and returns a
  place that isn't a path as it is.

## The Scrollkeeper bridge (R5)

Moved here from Mapsmith and Pluck, whose copies had grown apart.

- **`ScrollkeeperIndex`.** The titles an app lists: the `Decodable` mirror of the title index Scrollkeeper hands
  over (its `docs/specs/app-handoff/design.md`), `formatVersion`, `generatedAt` and `titles`. An `Entry` has the
  SKU, title, optional `kind`, series, number and `downloaded`, plus `coverURL` and `localFiles`, which are not in
  the handed-over file and are filled in from the library list. `subtitle` joins the kind and "series #number"
  with " · "; `search(_:)` folds case and accents and wants every word in the title, kind or series.
  `isIndexFile(_:)` tells the handed-over file (`.scrollkeeperindex`) from a document.
- **`ScrollkeeperBridgeConfiguration`.** `appKey`, `statusScheme` (the key unless set), `lists` (a test of a
  `ScrollkeeperLibrary.Title`), `opens` (a test of a `UTType`), `showsKind`, `sendsOneRequestAtATime` and `asksForIndex`.
  Mapsmith lists the titles of kind "Maps", opens PDFs and images, hides the kind and doesn't ask for the index; Pluck lists the titles that may hold
  a PDF (`Title.mayHold(_:)`: an edition of an accepted type, or an unpacked archive), opens PDFs and sends one
  request at a time.
- **`ScrollkeeperBridge`.** `@MainActor @Observable`, made with a configuration, an `ApplicationLauncher` and
  Scrollkeeper's folder (`ToolkitGroup.scrollkeeperFolder()`, nil outside the group). `state` is `idle`,
  `notInstalled`, `noSharedLibrary`, `waiting`, `unsupportedVersion`, `unreadable`, `failed(reason)` or
  `loaded(index)`; `requests` holds a `ScrollkeeperRequest` (SKU, whether it opens, phase) by SKU.
  `requestIndex()` reads `library.json` first (`ScrollkeeperLibrary.index(in:for:)`) and otherwise opens the
  index link in the background, or, where the launcher takes no requests or the configuration doesn't ask for the
  index, shows what the reading found: `noSharedLibrary`, `unsupportedVersion` or `unreadable`; `receive(_:)` reads the handed-over file, checking `formatVersion` before the
  rest; `refreshLibrary()` reads the library list again while what is shown came from it: a list, or the lack of
  one where the index isn't asked for.
  `open(_:)` passes `localFiles` to `openDocuments` when there are any, and otherwise sends a request, as
  `download(_:)` does; where the launcher takes no requests, both open the download link with `openInForeground`
  and record no request; `receiveStatus(_:)` takes the status links (`isStatusLink(_:)`), and an index failure
  arrives as one with an empty SKU.
- **`ApplicationLauncher`.** What the bridge needs from the system: `isInstalled`, `openInBackground`,
  `openInForeground` (which by default only launches Scrollkeeper), `launch` and `takesRequests` (true unless
  said otherwise). `WorkspaceLauncher` is the Mac's, on `NSWorkspace`; the iPad
  app supplies its own, and tests a fake.
- **`ScrollkeeperCoverThumbnail`.** A SwiftUI view of a cover, read with Image I/O off the main thread, or the
  app's symbol when there is none.
- **`PawnSheetRequest` (R6).** `Codable`, with `title` and `lines` (`Line`: `name`, `count`, `pawnID`). `url`
  encodes it with sorted keys, so the same request always gives the same link; `init(url:)` throws
  `PawnSheetRequestError.unrecognizedLink` for another scheme or host and `.unreadable` for a missing or damaged
  payload. `probeURL` is the bare `pawnshop://sheet`, for `WorkspaceLauncher.canOpen(_:)`, which asks
  `NSWorkspace.urlForApplication(toOpen:)`. It is on the Mac's launcher alone, not on `ApplicationLauncher`: an iPad
  app would need the scheme in `LSApplicationQueriesSchemes`, and none sends the request yet.
  `formatVersion` (R6.4) is written as `currentFormatVersion` and read first by a decoder of its own, which throws
  `.newerFormat(version)` before it looks at the title or the lines; `init(url:)` passes that error on and turns any
  other decoding failure into `.unreadable`. The number was added before any app with the request reached the App
  Store, because a reader that is already installed can't be taught to check.
- **The request as a sheet file (R6.5 to R6.7).** `PawnSheetRequest.sheetFile(readerVersion:)` encodes the keys
  Pawn Shop's `SheetFile` reads (`formatVersion`, `entries` with `id`, `pawnID`, `count` and a `label` of
  `ArtReference`'s keys, and `readerVersion`) from private structs of its own, so `TablesideShared` needs nothing
  of Pawn Shop's or of `ArtExtraction`. A test in Pawn Shop reads the kit's file with `SheetFile`, so the two can't
  drift apart unnoticed. `sheetFileName`, `sheetFileType` and `sheetFileExtension` name the file. Chosen over a
  second link for iOS because SwiftUI's document apps can't open a document from code there, while the system
  already hands a shared file to the app that owns its type.
- **`PageSetupArchive` and `PageSetupStore` (R7, macOS only).** The archive is the whole `NSPrintInfo`, written and
  read with secure coding: a paper size alone would come back formatted for "Any Printer", where a printer's own
  papers don't exist. `PageSetupStore` keeps one archive in `UserDefaults` under a key the app may name
  (`pageSetup` by default, the key Mapsmith used before the store moved here).
