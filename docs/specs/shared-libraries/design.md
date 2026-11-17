# Shared libraries: design

## What the libraries hold today
Measured on 2026-11-17 on the author's Mac, whose apps have read every pawn, token and Battle Cards PDF
Scrollkeeper holds.
- Turnkeeper's and Field Guide's `ArtLibrary`: 85 PDFs (64 Pathfinder, 21 Starfinder), about 10,300 entries in a
  12 MB `art-library.json`, with 12,814 prints: 8,544 pawns, 3,360 figures, 570 items, 340 tokens. 1,734 entries
  are printed by more than one product.
- Pawn Shop's `PawnLibrary`: 9,848 pawns in a 14 MB `library.json`, 2.7 GB of kept PDFs, 44 MB of token pictures.
- Every entry and pawn already stores `ArtFingerprint.imageDigests`: the SHA-256 of each image of at least 20 points
  drawn inside the art's front face. All but 2 entries have exactly one digest (one has two). The 2 without (4 in
  Pawn Shop, besides its 78 custom pawns) come from *Age of Ashes Pawn Collection* and *Player Character Pawn
  Collection*, which print some pages flattened.
- About 1% of digest sets are shared by more than one entry (105 in Turnkeeper, 86 in Pawn Shop): one product
  printing one picture under several names or sizes (23 numbered-token sets in *Murder in Metal City*, "Mantis,
  Deadly" and "Mantis, Giant", "Terra-Cotta Soldier" and "Terra-Cotta Garrison", Large and Huge elementals); a
  reprint under another name ("Bat, Skaveling" in *Bestiary 2*, "Skaveling" in *Shattered Star*); and names read
  two ways ("Sister of the Bloodshot Eye", "Bloodshot Eye Sister of the").

So the digests, with the name, are the art IDs' key: no PDF has to be read again to give existing art its new ID.

## Art IDs (R2)
`ArtKey` in `ArtExtraction/Library` makes the keys (`keys(for:)`, `entryID(among:)`), as name-based UUIDs
(version 5, RFC 9562: SHA-1 of the namespace `2A674007-7209-4190-AA36-612838B41B5F` followed by the name in UTF-8,
with the version and variant bits set). CryptoKit's `Insecure.SHA1` hashes; the name is the contract, so it is
listed here exactly.

- **Picture and name.** `image:`, the print's `imageDigests` (sorted, unique, lowercase hex) joined with `,`, then
  `|` and the folded name: lowercase, without diacritics, only letters and digits. A digest is the one
  `ImageIdentity.digest` makes today: SHA-256 of what `CGPDFStreamCopyData` returns, which is a JPEG or JPEG 2000
  image's bytes as stored and other images' samples with their filters undone. Recompressing a Flate stream doesn't
  change it, and the soft mask isn't part of it. The name keeps apart art that shares a picture (R2.3), such as a
  named enemy in an adventure's pawns drawn with a bestiary creature's picture; on the real libraries every key
  is then one piece of art, and the 6 keys shared by two entries are names read with different spacing ("Demon,
  Brimorak" and "Demon,brimorak"), which now merge as they should.
- **Size** (R2.3). Within one PDF, when prints with the same picture and folded name differ in size, each of them
  adds `|` and the size (`PawnSize.rawValue`). None of the real libraries needs it today.
- **A new reader.** A PDF read again by a newer reader can read a name differently, which changes the key. A new
  print in the same source, with the same picture and face as an old one, records the old key as an alias.
- **Fallback** (R2.4). Art without digests: `place:`, the PDF's SHA-256 (`ArtSource.id`), `|`, the zero-based page,
  `|`, and the center of the front face in page space on a 30-point grid (about 1/20 of a Letter page; no page
  size is needed, so a library moves in without opening its PDFs), written `x,y` as whole cells rounded to the
  nearest. Two such pieces of art in one cell add `#2`, `#3` in reading order (top to bottom, then left to right).
  A detector that moves a face by a few points usually keeps its key; the fallback covers only the flattened
  pages above.
- **The entry's ID** (R2.5). An `ArtEntry` keeps the key of each `ArtPrint` (`ArtPrint.key`). Its `id` is the first
  of them, ordering prints by kind for this purpose as pawn, token, figure, item, then by the key's string. A pawn
  comes first so that a pawn keeps its ID when a Battle Card adds a sharper picture (Pawn Shop's `SharperArt`).
  Importing a product can change an entry's `id`; nothing saved points only at it (below).
- **Finding art.** `ArtLibrary.entry(id:)` looks for an entry whose `id` or one of whose print keys is `id`, then in
  the aliases (R2.7): the random UUIDs each app gave the art before, recorded at the move (R6) with the app's name.
- **Merging** (`ArtMerger`). Art merges first by key: a print whose key is already in the library joins that entry.
  The existing rules follow: the same folded name and game with matching fingerprints, or palettes when one is a
  figure (a Battle Card's picture of a pawn's painting). Art under another name never merges, so a reprint renamed
  "Skaveling" stays apart from "Bat, Skaveling", as today.
- **References** (R2.8). What saves a reference to extracted art (a Pawn Shop sheet, Turnkeeper's `library:` path,
  Field Guide's chosen art) saves an `ArtReference`: the ID, the name, and the product's title, so a device without
  the art can say what is missing. Custom art keeps its random UUID and needs no label.

## The store (R1, R3, R4, R5)
`SharedLibrary`, in the new `SharedLibraries` target of tabletop-kit (the module isn't named after the type, which
would hide the module's name), opens `Tableside/Library.sqlite` in the group folder, or
`<app folder>/Library.sqlite` outside it (R1.2), with its files beside it:

| Folder | Holds |
|---|---|
| `Sources/<sha256>.pdf` | PDFs the library keeps |
| `Pictures/<key>.heic` | each entry's picture, named by the key of the print drawn (R3.2); a token's or item's picture drawn at import keeps its format (`<key>.png`) |
| `Custom/<uuid>.<ext>` | images the user pasted or dropped, and custom pawns' art |

It uses the system's SQLite (`import SQLite3`), so the package keeps no dependencies. The tables:

| Table | Rows |
|---|---|
| `sources` | `ArtSource` without its location: id, title, game, byte count, reader version, art found, whether kept |
| `sourceAccess` | how each app reaches a referenced PDF: source, app, encoded `SourceLocation` |
| `watchedFolders` | each app's watched folders (bookmarks only work for the app that made them) |
| `art` | `ArtEntry`: id, name, game, size, traits, fingerprint, palette, picture key |
| `prints` | `ArtPrint` by key: entry, source, kind, front and back face, image index, copies |
| `aliases` | old ID, app, entry |
| `notes` | what is learned about art, by entry: user name, tags, tag model, suggested name, whether corrected |
| `creatureArt` | the art chosen for a creature (bestiary key or `custom.<id>`): an entry ID or custom art |
| `customCreatures` | Turnkeeper's `CustomCreature` as JSON, with id, the campaign it was made in, `sharedVersion` |
| `customArt` | Turnkeeper's `CustomArt` as JSON, with id, image file, `sharedVersion` |
| `claims` | a PDF being read: source, app, until when |
| `counter` | the change counter |
| `deletions` | each deleted row's table and key, with the counter when it went |
| `moves` | each app's move (R6): rows recorded, or finished |

The toolkit doesn't know Turnkeeper's types, so `CustomCreatureRecord` and `CustomArtRecord` carry them as the app
encodes them, with the columns the library needs. `notes` comes with Pawn Shop's move (#27, #33), as schema
version 2 (`PRAGMA user_version`).

`ArtLibrary` keeps its API and becomes a view over the store; `CreatureArtStore` and Pawn Shop's `PawnLibrary` build
on it. `ArtPrint` gains `back: PawnFace?`, which Pawn Shop's pawns need.

- **Writing** (R5.1). WAL mode, a busy timeout of 5 seconds, and each change one short `BEGIN IMMEDIATE`
  transaction. Reading a PDF happens before, outside any transaction (`prepare`, then `commit`). Every changed row
  gets the next value of the change counter.
- **Changes** (R5.2). After a commit the store posts the Darwin notification
  `io.github.scooper4711.tableside.shared-library-changed`, observed as `LibraryChangeObserver` does. A reader
  keeps the last counter it saw and reads only the rows changed, and the deletions recorded, since then. The
  counter also gives #44 its list of changes to upload.
- **Claims** (R5.3). Before reading a PDF an app claims it for 10 minutes; another app skips a claimed PDF and
  picks up its art when the change arrives.
- **The iPad** (R5.4). The system ends a suspended app that holds a lock on a file in an App Group container. No
  transaction stays open, and the app calls `close()` when it goes to the background, wrapping any write still
  running in a background task (UIKit's, which the apps own); the store opens its connection again when needed.
- **Pictures** (R3.2). When a PDF is read, each new entry's picture is drawn as `ArtLibrary.picture(of:)` does and
  saved as HEIC with alpha, at the size the PDF embeds it, at most 1,024 pixels on its long side. A sharper print
  replaces it. Field Guide #40 measures the size on the real library before the cap is settled. Entries moved in
  (R6) have no picture yet: the first app that can open their PDF draws them in the background.
- **Reach** (R3.6). An app shows art from its picture; it needs the PDF only to draw a missing picture or read the
  PDF again for a newer reader. `sources` records which app reads it (`sourceAccess`), and the others name that app.

Why SQLite: the libraries are 12 to 14 MB of JSON. Rewritten whole for each tag or name, and read again whole by
every app at each change notice, under `NSFileCoordinator`, they would be slow, and they would give #44 no list of
what changed. Core Data or SwiftData across processes needs persistent history tracking and more setup for the
same result; GRDB would be the package's first dependency.

## Moving in (R6)
`SharedLibrary.moveIn(from:app:)`, which each app calls at launch until it succeeds:
1. Skip it when `moves` records the move for this app as finished. Otherwise read the app's old library (`art-library.json`
   or Pawn Shop's `library.json`).
2. Give each print its key from its fingerprint, name and face, grouping by source for sizes. No PDF is read.
   Pawn Shop's `library.json` version 2 (pawn-shop#46) already keys its pawns: they keep their IDs, and its
   `aliases` (old ID or another print's key → pawn ID) move into `aliases`.
3. In one transaction, add the sources, art and prints, merging by key (above); record each old UUID in `aliases`;
   merge `notes` and `creatureArt`. The user's corrections win over what was read and the later over the earlier;
   today's libraries record no correction times, so Pawn Shop's corrected names and tags go first, then the others.
   Add Turnkeeper's custom creatures and art. Record the move's rows (`moves`: recorded), so a move cut short
   doesn't write them twice.
4. Move the files: kept PDFs into `Sources` (a rename on the same volume; a PDF already there is deleted after its
   SHA-256 is checked), token, item and custom pictures into `Pictures` and `Custom` under their new names.
   A file already moved is skipped, so a move cut short finishes at the next launch (R6.5).
5. Rename the old library file to `<name>.moved`, kept for one version and then deleted, and record the move as
   finished.

Art chosen for a creature by an app that moved in before is kept. On copies of Turnkeeper's and Field Guide's real
libraries (in the gitignored `TestData/RealLibraries`), each move takes about 2 seconds; Turnkeeper's 10,280
entries become 10,274 (the 6 names read with different spacing), and every old ID of both apps finds its art.
Field Guide's copy adds 223: 8 PDFs Turnkeeper hasn't read, and PDFs an older reader read, whose art merges by
thumbnail once #33 merges as `ArtMerger` does.

Pawn Shop sheets keep `.pawn(UUID)`: an old UUID finds its pawn through `aliases`, and a sheet saved again stores
`ArtReference`s. Tests run on copies of the real libraries above and on sheets saved before the change (R6.4).

## Reading PDFs into the store (#33)
`ArtLibrary`, the JSON library, stays only as the format apps move in from: `ArtExtraction` can't depend on the
store, which depends on it. `SharedLibrary` gains what `ArtLibrary` does, and `CreatureArtStore` moves onto it,
keeping its API so Turnkeeper and Field Guide change only how they create it. Pawn Shop never used `ArtLibrary`.

- **Adding a PDF.** `ArtLibrary.prepare` reads it outside any transaction. The app claims it first (R5.3) and
  skips it when another app holds the claim. `commit` then writes, in one transaction, the source, its access
  for this app, and each piece of art found; a PDF read by the current reader is skipped, one read by an older
  reader is read afresh, its old prints replaced and their keys kept as aliases of the entries they joined.
- **Merging** (`ArtMerger`'s rules over the store). A print whose key the library has joins that entry.
  Otherwise, among the entries with the same folded name, game and kind of art (item or creature): one whose
  fingerprint matches, or, when either is a figure, whose colors match (`Figure.palette`, measured once and kept).
  `art.foldedName`, indexed, finds them (schema version 2).
- **Pictures** (R3.2). Each new entry's picture is drawn from the print that made it and saved as
  `Pictures/<key>.heic`, at most 1,024 pixels on its long side; a token's or item's picture drawn at import is
  kept as `<key>.png`. A figure added later (a Battle Card) draws the picture again, sharper. `picture(of:)` reads
  the file, else draws it from a PDF this app can reach and saves it, so moved-in entries get theirs on first use.
  Pictures are drawn after the write, a page per core: the *Monster Core Pawn Box* (415 pawns) reads in about
  9 seconds and draws in 5.
- **Watched folders, removing a PDF, missing PDFs** work as in `ArtLibrary`, per app: each app watches its own
  folders, and a PDF counts as missing for an app that can't reach it and has no picture.
- **`CreatureArtStore`** keeps the app's own library (`init(folder:)`) or opens the shared one
  (`init(sharedLibraryFor:fallback:)`), whose `moveIn` an app calls at launch; an app whose move fails keeps its
  own (R6.5). On the shared library, `picture(id:)` also finds art by an alias, and a PDF this app can't reach is
  listed as read by the apps that can (R3.6), its art shown from its pictures.
- **Pawn Shop's move.** `LibraryMove` also takes art already keyed (`keyedArt`, `keyedSources`), `aliases` (old
  ID to the ID or print key of its art), `notes` and the files to move (`keptPDFs`, `pictureFiles`), which Pawn
  Shop makes from `library.json` version 2 in pawn-shop#27. A note the user corrected wins over one they didn't.
- **Notes** (R3.3), schema version 3: `ArtNote` by entry, set by any ID of the art (`setNote(_:forArt:)`). When
  entries merge, the note moves with its art, a corrected note winning; art removed takes its note with it.

## Who does what
| Issue | Part |
|---|---|
| tabletop-kit#16 | `SharedLibrary`: the store, change notices, claims, creature library, Turnkeeper's and Field Guide's move |
| tabletop-kit#33 | `ArtKey`, `ArtReference`, merging by key, pictures, `ArtLibrary` over the store, Pawn Shop's move |
| pawn-shop#46 | pawn IDs from `ArtKey` in Pawn Shop's own library, with aliases; sheets with `ArtReference` |
| pawn-shop#27 | pawns over shared art, the move with #46's aliases |
| turnkeeper#18, field-guide#17 | each app on `SharedLibrary`; Field Guide shows custom creatures (R4.3) |
| field-guide#40 | picture size and format (R3.2) |
| tabletop-kit#44 | sync of `art`, `prints`, `notes`, `creatureArt` and the creature library by change counter |

## Decisions
Settled for pawn-shop#46's and the suite's open questions:
- **The key** is the embedded image, confirmed across pawn boxes with and without cut outlines, round tokens,
  Battle Cards in one PDF and in two, Pathfinder and Starfinder: all but the flattened pages above have one image.
- **Composite art.** The front face's images make the key. A back draws the same image (NPC Codex draws one image
  object on both faces) or a mirrored copy of it (`ArtFingerprint.matchesBack`), so it adds nothing. A second image
  on the front is part of the key.
- **What is hashed:** the stream as `CGPDFStreamCopyData` gives it, which every library already stores. A reissue
  that encodes the art again merges by its thumbnail, as today, and the entry answers to both keys.
- **The fallback place** is the face's center on a 30-point grid, with reading order for ties.
- **The same picture twice:** the folded name is always part of the key, so a picture shared by different
  creatures, in one product or across products, gives each its own ID (R2.3); size is added only where one product
  prints a picture under one name in two sizes.
- **A Battle Card's sharper picture** joins the pawn's entry, which keeps the pawn's ID.
- **A custom creature's pawn size** is `TraitLine.size` mapped to `PawnSize` (case ignored): Tiny becomes `.small`,
  and an empty or unknown size `.medium`.
- **Custom creatures without art** are left out of Pawn Shop. **Field Guide** shows custom creatures but doesn't edit
  them. The **art chosen for a creature** is shared by Turnkeeper and Field Guide.
