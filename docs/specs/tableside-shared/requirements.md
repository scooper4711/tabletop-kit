# Tableside Shared: requirements

The Tableside Toolkit apps share files through one App Group. This library is
the one place that says where that is and what Scrollkeeper puts there, so the
writer (Scrollkeeper) and every reader (Mapsmith, Pluck, Pawn Shop, Field
Guide, Turnkeeper) agree. Scrollkeeper's `docs/specs/app-handoff`
(requirements 5 and 6) says what Scrollkeeper shares and when.

## R1 The App Group
- R1.1 An app finds the group's folder without the team ID in its code: on the
  Mac the group is `<team ID>.io.github.scooper4711.tableside`, read from the
  app's own entitlements; on iOS it is `group.io.github.scooper4711.tableside`.
- R1.2 An app outside the group (an ad hoc development build, the tests) finds
  no folder, and carries on without it.
- R1.3 Scrollkeeper's part of the group is its `Scrollkeeper` folder: the
  downloads in `Files`, the covers in `Covers`, and `library.json`. Only
  Scrollkeeper writes there.

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
