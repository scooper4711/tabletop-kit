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
- **Image decks** (R2.2a). An item cut from a deck sold as JPGs (`ImageDeck`, the *Weapons & Armor Deck*) has
  one digest: SHA-256 of its back file as stored, never of the pixels decoded from it, which differ between Mac and
  iPad. Its key is the picture alone, `image:<digest>|`, as for nameless art: each back file is one card, and the
  name, read off the front by text recognition, differs between devices too ("Flail" and "Plail"). The entry keeps
  the name read for display. Image decks are read by `PawnExtractor.imageDeckVersion` (7), PDFs by
  `PawnExtractor.version` (6); `PawnExtractor.version(of:)` picks, so raising one doesn't read the other again
  (pawn-shop#61).
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
| `Pictures/<key>.heic` | each entry's picture, named by the key of the print drawn (R3.2); a token's or item's picture drawn at import keeps its format (`<key>.png`), and a token's back with art of its own is `<key>-back.png` (schema version 5), which Pawn Shop prints |
| `Custom/<uuid>.<ext>` | images the user pasted, dropped or chose for a creature in any of the apps (R4.2), custom pawns' art among them |

It uses the system's SQLite (`import SQLite3`), so the package keeps no dependencies. The tables:

| Table | Rows |
|---|---|
| `sources` | `ArtSource` without its location: id, title, game, byte count, reader version, art found, whether kept |
| `sourceAccess` | how each app reaches a referenced PDF: source, app, encoded `SourceLocation` |
| `watchedFolders` | each app's watched folders (bookmarks only work for the app that made them) |
| `art` | `ArtEntry`: id, name, game, size, traits, fingerprint, palette, picture key and its size in pixels (schema version 6), whether it needs a name |
| `prints` | `ArtPrint` by key and source (two products printing one picture under one name share a key; schema version 5, which older apps only read): entry, kind, front and back face, image index, copies, a token's back picture |
| `aliases` | old ID, app, entry |
| `notes` | what is learned about art, by entry: user name, tags, tag model, suggested name, whether corrected, when changed (schema version 6) |
| `creatureArt` | the art chosen for a creature (bestiary key or `custom.<id>`): an entry ID or custom art |
| `customCreatures` | Turnkeeper's `CustomCreature` as JSON (empty for a creature without a stat block), with id, the campaign it was made in, `sharedVersion`, and its name, game and pawn size (schema version 7) |
| `customArt` | Turnkeeper's `CustomArt` as JSON (empty for art added in Pawn Shop), with id, image file, `sharedVersion` |
| `claims` | a PDF being read: source, app, until when |
| `counter` | the change counter |
| `deletions` | each deleted row's table and key, with the counter when it went |
| `moves` | each app's move (R6): rows recorded, or finished |
| `cloudRecords`, `parkedRecords`, `syncState`, `fetchedPictures` | what this device knows of its sync (schema version 6, library sync design); never synced, and written outside the change counter |

The toolkit doesn't know Turnkeeper's types, so `CustomCreatureRecord` and `CustomArtRecord` carry them as the app
encodes them, with the columns the library and the other apps need ("Custom pawns are custom creatures", below).
`notes` comes with Pawn Shop's move (#27, #33), as schema version 2 (`PRAGMA user_version`).

`ArtLibrary` keeps its API and becomes a view over the store; `CreatureArtStore` and Pawn Shop's `PawnLibrary` build
on it. `ArtPrint` gains `back: PawnFace?`, which Pawn Shop's pawns need.

- **Writing** (R5.1). WAL mode, a busy timeout of 5 seconds, and each change one short `BEGIN IMMEDIATE`
  transaction. Reading a PDF happens before, outside any transaction (`prepare`, then `commit`). Every changed row
  gets the next value of the change counter.
- **Versions.** The apps update one at a time, so one can open a library a newer app has changed. A new
  schema version only adds tables and columns with defaults; writes update only the columns they name, so an
  older app keeps what a newer one added, and it never lowers `PRAGMA user_version`. A version that changes what
  existing rows mean raises `compatibility.oldestWriter`; an older app then only reads the library
  (`canWrite`) and asks the user to update it.
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
  saved as HEIC with alpha, at the size the PDF embeds it, at most 2,048 pixels on its long side. A sharper print
  replaces it. Field Guide #40 measured a full library at 1,024: 10,650 pictures, 401 MB, 690 of them at the cap
  (mostly Battle Card art, which the card draws at up to 1,600 px); 2,048 adds at most about 207 MB, on those
  alone. Pictures saved under the old cap aren't drawn again. Entries moved in
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
  reader is read afresh, its old prints replaced and their keys kept as aliases of the entries they joined. Art an
  old print leaves without prints hands its note, aliases and creatures to the art printed in its place, so a
  pawn whose ID is that print's key keeps its tags. In an image deck only, an old print no new print shares a
  place with (same page, centers within 15 points) pairs instead with the new print in the source whose art has
  the same folded name: a card moved in from Pawn Shop's own library was stored without its place (page 0). A PDF
  doesn't, since one name there can be several pieces of art, such as a goblin in two sizes, and art a newer
  reader no longer finds should go rather than answer for other art. Applying another device's reading pairs by
  place alone: the reading carries the aliases its device recorded.
- **Merging** (`ArtMerger`'s rules over the store). A print whose key the library has joins that entry.
  Otherwise, among the entries with the same folded name, game and kind of art (item or creature): one whose
  fingerprint matches, or, when either is a figure, whose colors match (`Figure.palette`, measured once and kept);
  with a figure only the same images count as a matching fingerprint, since the thumbnails of any two paintings
  of one shape look alike. `art.foldedName`, indexed, finds them (schema version 2). When a figure is involved, the colors are also compared
  with named creature art whose name gives more or less of the creature's family (`CreatureName.matches`, as Pawn
  Shop merged Battle Cards: "Imp" and "Devil, Imp", but not "Giant, Wood" and "Golem, Wood"), found by
  `art.nameKey`, the folded part after the name's last comma (schema version 5).
- **Pictures** (R3.2). Each new entry's picture is drawn from the print that made it and saved as
  `Pictures/<key>.heic`, at most 2,048 pixels on its long side; a token's or item's picture drawn at import is
  kept as `<key>.png`. A figure added later (a Battle Card) draws the picture again, and the art takes it when it is
  the sharper one (library sync design, "Pictures"). `picture(of:)` reads
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

## Art printed without a name (R2.3a)
Pawn Shop's own library kept nameless pawns; the store dropped them (`report.unnamed`), so a PDF Turnkeeper or
Field Guide read first would never give Pawn Shop its *Heroes & Villains* pawns (171 of the author's 9,848 still
need names, all from that product; 242 pawns are printed in it). `StoreMerger` now keeps them, as Pawn Shop did:

- **Key.** The picture and an empty name: `image:<digests>|`, or the fallback place (R2.4). The stand-in name isn't
  in the key, so it doesn't depend on the product's title.
- **Entry.** Name `Unknown <title>` (`NamelessProducts.standInName(forTitle:)`) and `art.needsName` set (schema
  version 5, a column defaulting to 0; existing rows keep their meaning, so `oldestWriter` stays). An app shows a
  note's `userName` over the stand-in, and the art stops needing a name for that app once it has one.
- **Merging a nameless print**, after its key: in a product known to print no names (`NamelessProducts`: titles
  containing "Heroes & Villains"), the first named creature art of the same game and size whose fingerprint is the
  same art (`ArtFingerprint.isSameArt`: the same digests, or thumbnails at most `namingDistance` 15 apart, stricter
  than `matchingDistance`, measured on Pawn Shop's library), counted in `report.namedFromOtherProducts`. Else art
  still needing a name, same game and size, whose fingerprint `matches`. Else a new entry, counted in
  `report.added` and `report.needingNames`.
- **Merging a named print**, after its key and the same name: art still needing a name from a nameless product,
  same game and size, the same art by `isSameArt`, takes the print's name and stops needing one.
- **Items** printed without a name are still left out (`report.unnamed`).
- **PDFs read before.** No app has shipped on the store before this, so no library holds a PDF read without its
  nameless art, and nothing is read again.

`isSameArt` and `NamelessProducts` move here from Pawn Shop, which uses the toolkit's.

## Custom pawns are custom creatures (R4.4, R4.6 to R4.10, R6.6)
A pawn the user makes in Pawn Shop and a creature the user makes in Turnkeeper are one thing, a row of
`customCreatures`, so each app shows what the other made. Pawn Shop never reads or writes a stat block, and
Turnkeeper never reads how art sits on a pawn.

- **What every app reads.** Schema version 7 adds three columns to `customCreatures`, on `CustomCreatureRecord` as
  `name: String`, `game: GameSystem?` and `size: CreatureSize?`. They only add, with defaults (`''`, NULL, NULL), so
  `oldestWriter` stays. `record` stays Turnkeeper's and is empty for a creature without a stat block
  (`hasStatBlock`). The columns are the truth for what they hold: an app that reads a stat block (Turnkeeper,
  Field Guide) puts the row's name and size over the ones in the record (`Creature.applying(name:size:)` in
  `CreatureArt`, which knows both modules), and Turnkeeper writes both when it saves one.
- **A pawn made in Pawn Shop** (R4.6) is written in one transaction, `addCustomCreature(_:art:image:)`: the creature
  (a new UUID, its name and size, no game, an empty record), its art (`customArt` with the same UUID, an empty
  record, the image written to `Custom/<uuid>.png` first), and the choice (`creatureArt`: `custom.<uuid>` to
  `.custom(<uuid>)`). The pawn's ID is the creature's.
- **Pawn Shop's pawns** (R4.4). Each creature with a row in `creatureArt` under `custom.<id>` is a pawn with the
  creature's ID, its name and its size's pawn (Medium without one): drawn from `Custom/<file>` for custom art, or
  as the entry's pawn is for art chosen from the library. Pawn Shop reads the columns only, so it doesn't decode `record` and the
  store doesn't depend on `Bestiary`. It follows changes as it does for art (`customCreatures(changedSince:)`,
  `customArt(changedSince:)`, `creatureArt()`, and `deletions`).
- **Turnkeeper's creatures** (R4.6, R4.10). A row with an empty record becomes a `CustomCreature` named by the row,
  with nothing else filled in, as `CustomCreature.init(campaignID:game:name:)` makes one, and without a campaign.
  Giving it a stat block saves the record, the campaign and the game.
- **Size** (R4.4a, R4.4b). `CreatureSize` (in `SharedLibraries`) is Paizo's six sizes, `tiny` to `gargantuan`, with
  the word a trait line prints (`init?(trait:)`, case ignored, and `trait`: "Tiny") and its pawn (`pawnSize`: Tiny
  and Small are both `.small`). `PawnSize`, which art read from PDFs keeps, gains nothing: no PDF prints a Tiny
  pawn, and a sixth pawn size would reach `ArtKey`, every size switch and every synced reading. The column holds
  the creature's size, so it and the trait say the same thing and neither is rounded: Turnkeeper writes it from
  `TraitLine.size` whenever it saves a creature with a stat block (NULL for a word that isn't one of the six, which
  prints as Medium and leaves the trait alone), and Pawn Shop changes it at any time with
  `setCustomCreatureSize(_:id:)`, which writes the column alone. Turnkeeper saves the record with the new trait
  the next time it saves the creature; until then every read applies the column, so the stat block already shows
  it.
- **Renaming** (R4.7). `renameCustomCreature(id:to:)` writes the name alone, as every write names its columns, so
  Pawn Shop renames a creature without touching its record.
- **Pawn Shop's own** (R4.8). The art's placement and scaling, whether the name is printed, and the tags stay in
  `pawn-shop.json`, by the creature's ID, with defaults for a creature Turnkeeper made (filled, centered, name
  printed). They sync in Pawn Shop's zone as before, without the image, which now syncs with its `customArt`.
  Shared framing (tabletop-kit#27) would move the placement and scaling here later.
- **Removing** (R4.9). Turnkeeper calls `removeCustomCreature(id:)`, which now also takes out the creature's
  `creatureArt` row and the custom art nothing else is chosen for. Pawn Shop calls it for a creature without a stat
  block, after asking, and otherwise records the ID in its `hidden` list. Pawn Shop can't see Turnkeeper's
  encounters, so its question names Turnkeeper and its encounters whenever Turnkeeper has moved in on this device
  (`hasMovedIn(.turnkeeper)`), and is a plain confirmation otherwise. Turnkeeper reads the deletion (`deletions`,
  here or synced from another device) and removes the creature from every encounter, as its own delete does.
  Always hiding was the alternative: a hidden pawn doesn't sync, so it would stay on the user's other devices,
  and someone with Pawn Shop alone could never delete one.
- **Moving Pawn Shop's custom pawns in** (R6.6) is a step of its own, not part of `moveIn`: Pawn Shop's move (#27)
  left them in `pawn-shop.json`, and libraries that moved in before this have that move recorded as finished. While
  `pawn-shop.json` lists custom pawns, Pawn Shop adds each as above under its own ID (one already there is
  skipped, which is what a move cut short, or a pawn another device moved and synced, leaves), moves
  `Custom/<id>.png` from its folder into the store's `Custom` (a rename; a file already there is skipped), and
  then saves `pawn-shop.json` with only what is Pawn Shop's own. Tested on the copy of the real library (78 custom
  pawns, 17 of them on the Iconics sheet).
- **Sync.** `CustomCreaturePayload` gains `name`, `game` and `size` as optionals, by the rule for later versions
  (library sync design), and `format` stays 1: no released app has the store or its sync. A record without a name
  comes from a build before this and leaves the row's name, game and size alone (`upsertKeepingName`); one with a
  name sets all three, a missing game or size included. A creature made by such a build has an empty name until
  Turnkeeper next saves it; Turnkeeper fills the columns of such rows when it opens the library.

## Pasted art of other creatures (R4.11 to R4.13)

- **The label.** A custom art row's `record` is the JSON the app that pasted the art encodes, Turnkeeper's
  `CustomArt`, and syncs as it is. `ArtSubjectLabel` names two keys in it, `subjectName` and `subjectSize` (a
  `CreatureSize`'s raw value). `ArtSubjectLabel(record:)` reads them leniently: nil for an empty record, one that
  isn't JSON or one without a name, and no size for a word that isn't one of the six. No column and no sync field
  is added, so builds before this carry the label without knowing it; one that encodes the art again from its own
  model drops it, and Turnkeeper puts it back when it next reads the library.
- **The pawn's ID.** `SharedLibrary.pawnID(forSubject:)`: the ID in a `custom.<id>` key, else
  `ArtKey.nameBasedUUID("creature:" + subject)`, a version 5 UUID in the art keys' namespace. It comes from the
  creature's key and not from the art, because pasting again makes new art under a new ID.

## Who does what
| Issue | Part |
|---|---|
| tabletop-kit#65, pawn-shop#63, turnkeeper#18 | custom pawns as custom creatures: the columns, `CreatureSize` and `addCustomCreature` here; Pawn Shop's pawns over custom creatures and its move (R6.6), before its Quick Look previews (pawn-shop#58); Turnkeeper's creatures without a stat block |
| tabletop-kit#16 | `SharedLibrary`: the store, change notices, claims, creature library, Turnkeeper's and Field Guide's move |
| tabletop-kit#33 | `ArtKey`, `ArtReference`, merging by key, pictures, `ArtLibrary` over the store, Pawn Shop's move |
| pawn-shop#46 | pawn IDs from `ArtKey` in Pawn Shop's own library, with aliases; sheets with `ArtReference` |
| pawn-shop#27 | pawns over shared art, the move with #46's aliases |
| turnkeeper#18, field-guide#17 | each app on `SharedLibrary`; Field Guide shows custom creatures (R4.3) |
| field-guide#40 | picture size and format (R3.2) |
| tabletop-kit#44 | sync of the art read from PDFs, `notes`, `creatureArt` and the creature library through the suite's iCloud container (`docs/specs/library-sync`) |

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
- **A custom creature's size** is a `CreatureSize`, shared by its stat block and its pawn, rather than a
  `PawnSize` worked out from the trait: Tiny is a size of its own that prints as Small, so a size set in Pawn Shop
  can be written back to the stat block without guessing. An empty or unknown size prints as Medium.
- **Custom creatures without art** are left out of Pawn Shop, and those **without a stat block** out of Field
  Guide. **Field Guide** shows custom creatures but doesn't edit them. The **art chosen for a creature** is shared
  by Turnkeeper and Field Guide.
- **A custom pawn is a custom creature**, not custom art with a name: one row has the name both apps show, so a
  rename in either reaches the other, and a sheet's pawn and an encounter's creature are the same ID.
- **Pasted art on a bestiary creature** (Turnkeeper R3.5c) is not a pawn in Pawn Shop: the store doesn't hold a
  bestiary creature's name or size. Only custom creatures are.
