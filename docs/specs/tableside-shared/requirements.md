# Tableside Shared: requirements

The Tableside Toolkit apps share files through one App Group. This library is
the one place that says where that is and what Scrollkeeper puts there, so the
writer (Scrollkeeper) and every reader (Mapsmith, Pluck, Pawn Shop, Field
Guide, Turnkeeper) agree. Scrollkeeper's `docs/specs/app-handoff`
(requirements 5 and 6) says what Scrollkeeper shares and when. The library also
holds the one bridge through which an app lists and opens Scrollkeeper's titles
(R5), so the handoff contract is defined once, and the request another app
sends Pawn Shop for a sheet of pawns (R6).

## R1 The App Group
- R1.1 An app finds the group's folder without the team ID in its code: on the
  Mac the group is `<team ID>.io.github.scooper4711.tableside`, read from the
  app's own entitlements; on iOS it is `group.io.github.scooper4711.tableside`.
- R1.2 An app outside the group (an ad hoc development build, the tests) finds
  no folder, and carries on without it.
- R1.3 Scrollkeeper's part of the group is its `Scrollkeeper` folder: the
  downloads in `Files`, the covers in `Covers`, and `library.json`. Only
  Scrollkeeper writes there.
- R1.4 The shared art and creature libraries are its `Tableside` folder, written by Pawn Shop, Turnkeeper and
  Field Guide (`docs/specs/shared-libraries`).

## R2 The library list
- R2.1 `library.json` has a format version and the time it was written, says
  whether the downloads are in the shared folder or in a folder the user chose
  (with its path), and lists the titles with their SKU, title, kind, game,
  series, number, levels, cover, whether they are on disk, and their editions:
  name, kind, path relative to the download folder, whether that is a folder,
  whether it is on disk and whether it is out of date.
- R2.2 A reader checks the format version before reading the rest, and tells a
  missing list, an unreadable one and one newer than it knows apart, so it can
  fall back to asking Scrollkeeper. Fields added later are ignored.
- R2.3 A reader that opens a title's files chooses them as Scrollkeeper does
  for a handoff: an up-to-date single file of a type the reader accepts first;
  otherwise the accepted files in the first up-to-date unpacked archive, only
  its PDFs when it has any.

## R3 Changes
- R3.1 After writing the list Scrollkeeper tells the readers, and a reader can
  follow those changes on the main thread for as long as it wants, without
  polling. This works in the App Sandbox.

## R4 Showing where files are
- R4.1 Wherever an app shows a folder or a file's folder, Scrollkeeper's downloads read as "Scrollkeeper", with
  the title folders inside after it ("Scrollkeeper ▸ Murder in Metal City") and where they are ("On this Mac",
  "On My iPad"), never as a path into the App Group or a container. This holds for the shared folder, for
  Scrollkeeper's folder before it ran in the sandbox, and on the iPad for an app's Documents folder.
- R4.2 Other folders show their name and where they are, with the home folder shortened to `~`.

## R5 The Scrollkeeper bridge
- R5.1 An app lists the titles it can open from Scrollkeeper. It reads them from the library list (R2) when there
  is one it understands, and otherwise asks Scrollkeeper, which stays in the background, to hand the list over as
  a file (`scrollkeeper://index?app=<key>`). It refuses a handed-over list in a newer format, and tells apart a
  list it can't read, a Scrollkeeper that isn't installed and one that couldn't send the list (with its reason).
- R5.2 Each app configures the bridge: its key (`app=`), the scheme of the status links Scrollkeeper sends it,
  which library titles it lists, which file types it opens, whether a title's kind shows under it, whether it
  sends one request at a time or several, and whether it asks Scrollkeeper for the list when there is no library
  list to read (R5.1) or reads only the library list (R5.7).
- R5.3 The list is searched by title, kind (where shown) and series: every word must match, ignoring case and
  accents.
- R5.4 A title whose files are up to date in the shared download folder opens straight from there (R2.3), with no
  request. Any other title is asked for by SKU: opened (`scrollkeeper://open?sku=…&app=<key>`), which downloads it
  first when needed, or only downloaded (`scrollkeeper://download?…`).
- R5.5 The bridge follows each request through Scrollkeeper's status links
  (`<scheme>://handoff?sku=…&state=downloading|done|failed`, with a `fraction` or a `reason`): requested,
  downloading with its progress, done or failed. A title whose download is done counts as on disk. Asking for the
  list again forgets the requests that are done or failed and keeps those under way. An app that sends one request
  at a time forgets the earlier one when it sends the next.
- R5.6 A list read from the library list is read again when Scrollkeeper says it changed (R3); a handed-over list
  is left alone.
- R5.7 Where Scrollkeeper takes no requests (the iPad), or the app chooses not to ask for the list (Mapsmith), the
  bridge only reads the library list: without one it says there is no shared library, and it tells apart a list
  newer than it knows and one it can't read; in each case it looks again when asked to refresh. Where Scrollkeeper
  takes no requests, asking for a title that isn't on disk opens its download link
  (`scrollkeeper://download?sku=…&app=<key>`) in the foreground, whether the app asked to open or only to
  download it: Scrollkeeper comes forward and downloads it there, and the title shows up in the library list once
  it is on disk. Such a request isn't followed (R5.5). An app that only chooses not to ask for the list still asks
  for titles (R5.4).
- R5.8 Each app keeps its own window. The library gives it the bridge's state, the system side of launching
  Scrollkeeper on the Mac, and a small cover thumbnail with a symbol to show when a title has no cover.

## R6 The pawn sheet request
- R6.1 An app asks Pawn Shop for a new sheet with a link, `pawnshop://sheet?request=<payload>`: a title for the
  sheet and, in order, its lines. Each line names a creature, says how many pawns of it to print and, when the
  sender knows which pawn it means, gives that pawn's ID (the art's ID in the shared library, or a custom
  creature's ID). The payload is the request as JSON, in URL-safe Base64 without padding.
- R6.2 Reading a link gives back the request it was made from, whatever characters its names hold. A link that
  isn't a sheet request (another scheme or host) is told apart from one whose payload can't be read.
- R6.3 On the Mac an app can ask whether anything installed opens a link, so it offers the request only when a Pawn
  Shop that takes it is there. This works in the App Sandbox.
- R6.4 A request says which format it is written in; one that doesn't is in format 1. A reader checks the format
  before reading the rest and refuses a newer one than it knows with an error of its own, so the app can tell the
  user to update. Fields added later are ignored, and adding them doesn't change the format's number: it rises only
  for a change an older reader would get wrong.
