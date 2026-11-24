# Library sync: design

The store (`SharedLibrary`, shared libraries design) gains what sync needs, in `SharedLibraries` and without
CloudKit: what to upload, how a record from another device is merged in, and the bookkeeping for pictures. The
`TablesideSync` target puts a `CKSyncEngine` on top of it.

## Decisions

| Question | Decision |
|---|---|
| Container | `iCloud.io.github.scooper4711.tableside`, private database. Field Guide's lore stays in its own. |
| Zones | `Library` (rows, synced by the engine) and `Pictures` (one asset per picture, fetched on demand, never by the engine). |
| Unit of art | **One record per PDF read** (`Source`), holding that PDF's whole reading: its prints, the art they belong to, and that art's aliases. About 85 records instead of 23,000, and a newer reader's reading replaces an older one whole. |
| Other records | One per row: `Note`, `CreatureArt`, `CustomCreature`, `CustomArt` (its image as an asset in the record). |
| Not synced | `sourceAccess`, `watchedFolders`, `claims`, `moves`, `counter`, `deletions`, `compatibility`, `sources.kept`, the PDFs. |
| Conflicts | No separate rule set: a server record is merged in exactly as a fetched one is, and the result is uploaded only if it still differs. |
| What needs uploading | A device-local table, `cloudRecords`, shared by the apps on the device: each record's server change tag, the change counter it was last in step with, and the digest of its content. No echo, and two apps syncing at once are safe. |
| Engine state | In the SQLite database (`syncState`), one row per app, so a restored backup carries a matching state. |
| Picture names | A picture's name is opaque and its content never changes. A different rendering (a sharper print, a larger size cap later) is a new picture under a new name; the name syncs in the reading, so every device follows, and the old picture is deleted once nothing uses it. Nothing works out a picture's name from an art key: it reads the name from the row. |
| Two devices' pictures of one art | The sharper stays: the one with more pixels on its long side, kept with the picture's name in the art's row and in the reading; of two as sharp, the one whose name sorts first. Every device decides alike, whichever applies the other's record first. |
| Pictures on a device | One setting per device, `PicturePolicy`: `.onDemand(limit:)` downloads a picture when it is first shown and, with a limit in bytes, removes the least recently shown past it (nil: never removes); `.everything` downloads every picture ahead of time and never removes any. The default is `.onDemand(limit: nil)`; each app offers its own choices later. |
| Removing a PDF | Syncs: its art, pictures and kept copy go on every device. The cloud keeps no tombstone, so a device that first syncs later with that PDF brings it back. |
| iCloud data deleted by the user (`purged`) | Syncing pauses on the device until the app calls `resume()`. A zone deleted any other way is uploaded again, as Field Guide does. |
| A user's edits on two devices | The later `modified` time wins; for notes, a corrected note beats an uncorrected one first. |
| A record this version can't read | Kept aside, not an error: the rest of the batch is applied, this device doesn't send its own copy over it, and a later version of the app applies it. |
| One engine per database | `SyncEngine` hosts several zone handlers, so Turnkeeper (a zone per campaign) and Pawn Shop (custom pawns) add theirs to the same engine later. Only the library's handler is written now. |

## Schema version 6

Additive, so `compatibility.oldestWriter` stays 5. None of the new tables is a `LibraryTable`, and writes to them never
go through `SharedLibrary.write` (no counter, no Darwin notification), except inside the transaction of
`applyRemote`. `SourceClaims` is the precedent.

| Table | Rows |
|---|---|
| `cloudRecords` | What this device knows the server holds, by zone and record name: kind, the local row's key (`rowKey`), the record's archived system fields (NULL once the server is known not to have it), the change counter it was last in step with (`sentChanged`), and the SHA-256 of the content the server holds |
| `parkedRecords` | A note that arrived before its art, kept until the art does; and a record this version can't read (`unreadable` is 1), kept for a version that can |
| `syncState` | `engine.<app raw value>` (the engine's saved state), `paused` (present when paused), `picturePolicy` (JSON; absent means `.onDemand(limit: nil)`), `account` (the iCloud account `cloudRecords` describes) |
| `fetchedPictures` | The pictures this device downloaded: file size and when each was last shown |
| `aliasesByEntry` | An index on `aliases (entry)`, so a source's change counter is cheap |
| `modified` | A column of `notes`, `creatureArt`, `customCreatures` and `customArt`: the user's last change, in seconds since the reference date, 0 before version 6 |
| `picturePixels` | A column of `art`: the long side of its picture in pixels, 0 for a picture saved before version 6 until `measurePictures` has read its file |

## Records and payloads

A `SyncRecord` is a kind, a name, the canonical JSON of a payload, a title for people reading the CloudKit Console,
and custom art's image file. The kinds, in the order fetched records are applied: `source`, `customArt`,
`customCreature`, `creatureArt`, `note`.

| Kind | Record name | Payload |
|---|---|---|
| `source` | `source-<sha256>` | `SourceReading`: id, title, game, byte count, reader version, art found, and its groups |
| `note` | `note-<entry UUID>` | `NotePayload` |
| `creatureArt` | `creatureArt-<SHA-256 hex of the subject>` (a subject can hold any character) | `CreatureArtPayload` |
| `customCreature` | `creature-<UUID>` | `CustomCreaturePayload`; its name, game and size are optionals added for custom pawns (shared libraries design, "Custom pawns are custom creatures"); a record without a name, from a build before them, leaves the row's three alone |
| `customArt` | `customArt-<UUID>` | `CustomArtPayload` |

A reading's `ReadingGroup` is one piece of art as far as this PDF prints it: its ID on the sender (`entry`), its
attributes, its picture's name and size, `keys` (every print key of the art, from any PDF), this PDF's `prints`, and the art's
`aliases`. Payloads are `Codable` structs encoded by one `JSONEncoder` with sorted keys; dates are seconds since the
reference date. `digest` is the SHA-256 of those bytes.

**Rule for every later version:** fields are only added, as optionals, and a missing field keeps the local value. A
digest is always taken of the payload **as this version encodes it** (decode the incoming bytes, encode again),
never of the incoming bytes, or two app versions would upload over each other forever. A new value of an existing
field (another game, kind of print or app) makes the record unreadable to the versions before it: see "Records kept
aside".

## What to upload

A record's **change counter**: for a note, creature art, custom creature or custom art, the row's `changed`. For a
source, the greatest `changed` of its `sources` row, its prints, the art those prints belong to, and the aliases of
that art, in one statement. No writer has to change.

- **Saves**: records whose counter is above their `cloudRecords.sentChanged`, or with no `cloudRecords` row; but
  those whose copy in the cloud this version can't read.
- **Deletions**: `cloudRecords` rows of the zone `Library` with system fields whose row is gone. The `deletions`
  table isn't used.
- Paused: neither.
- `outgoingRecord` builds the payload. When its digest equals the stored one and the server has the record, it
  catches `sentChanged` up and returns nothing: another app on the device sent this content, or a write changed
  nothing that syncs.
- `markSent` stores the record's fields and digest and the counter *when the record was built*, so a change made
  while it was in flight is still a candidate.
- `forgetServer` empties `cloudRecords` and `parkedRecords` and the engine states, so everything uploads again.

## Merging in a record from another device

`applyRemote` applies fetched and conflicting server records alike, in one `write` transaction.

1. **Skip what is known.** A saved record whose re-encoded digest equals the stored one only updates the stored
   system fields, outside `write`. That holds with its row gone too: the row was deleted here since, and merging
   the record in again would undo a deletion still to send. When nothing else is left: no transaction, no counter,
   no notification. A second app on the device fetching the same records is a no-op (R2.3). A record whose content
   the library holds already is noted the same way, and so is a deletion of a record that is neither here nor
   known to the cloud. What was kept aside under the name of any of these goes: it is older. A saved record this
   version can't read is kept aside here too ("Records kept aside").
2. **In `SyncKind` order**, deletions of a kind before its saves; then the notes kept aside are tried again; then
   `cloudRecords` is settled for every source applied. Applying a record first drops what
   was kept aside under its name.
3. **A source saved.** A local reading by a newer reader stays, and is uploaded over the incoming one. An older
   local reading is taken out (`takeOutPrints`) and the incoming one merged: each group becomes a `SharedArtEntry`
   merged with `merge(_:with:)`, which also finds art by the group's other keys, so art the sender had as one
   piece becomes one piece here (R3.4). Of the group's picture and those of the art it joins here, the one that
   stays is chosen as "Pictures" says, not the incoming one. The old prints are then retired, their keys becoming aliases (R3.3), and
   their pictures deleted after the transaction. Last, the incoming aliases are added unless they already find
   art. For an alias this device holds too, both devices settle on one row whichever applies the other's first:
   the app whose name sorts first and, when they name different art, the ID that sorts first; otherwise each
   would send its reading over the other's forever. A reading leaves out an alias that is also art's ID or a
   print's key.
   `sourceAccess` is never written, and `kept` stays as it was.
4. **A source deleted.** The PDF is removed as `SharedLibrary.remove(sourceID:)` does, its kept copy and the
   pictures nothing names any more deleted after the transaction: a PDF downloaded afresh has other bytes and so
   another ID, and its record in the same batch names the same pictures. A removal always wins.
5. **A note saved.** Found by any ID of its art; without art it is parked (R3.7). With unsent local changes, the
   local note stays if it is corrected and the incoming one isn't, or when neither or both are and its `modified` is
   later. When the art's ID here differs from the record's, the record is renamed on the server by uploading the
   note under the new name and deleting the old (R3.5).
6. **Creature art, custom creature and custom art saved.** With unsent local changes the later `modified` wins, a
   tie going to the incoming one. A custom art's image is copied in under a staged name (`<file>.incoming`) and put
   in place once the transaction has committed.
7. **Those deleted.** With unsent local changes the row stays and is uploaded again; otherwise it goes, and a
   custom art's image once the transaction has committed.
8. **Settling `cloudRecords`** after a save: the system fields and the incoming digest are stored. When the local
   payload built again has the same digest, nothing is left to upload; otherwise the merged result is. A PDF's
   reading also has nothing to upload when it differs only in what this device knows from its other PDFs and knows
   no key the incoming one doesn't (`SourceReading.isCovered`): a device lacking another PDF that prints the same
   art (its record not here yet, or unreadable to this version) gives the art fewer keys and another ID, and
   sending that over the fuller reading would have the two devices upload over each other forever.
   A known limit: the rule is applied only as a PDF's own record is merged in, so a device lacking one of three
   PDFs that print the same art can still answer for the other two.

On a failure the transaction rolls back and `applyRemote` throws, with every file as it was: files are only
deleted or replaced after the commit.

## Records kept aside

`parkedRecords` holds what can't be applied yet, by record name, with the server's fields.

- **A note without its art** (R3.7) is tried again at the end of every batch that is applied.
- **A record this version can't read** (R3.10): a newer app wrote a value this one doesn't know. It is marked
  `unreadable`, counted as parked, and the rest of the batch is applied. While it is there, the local row of that
  name is no candidate and `outgoingRecord` returns nothing for it, so an older app never writes over what it
  couldn't read. Every `applyRemote`, even with no changes, first tries the unreadable records this version can now
  read, as changes of that batch; with none of those, an empty batch still opens no transaction. The engine calls
  `applyRemote([])` when it starts, so an updated app catches up without waiting for another device.
- A later copy of the record, or its deletion, replaces or drops what was kept aside under its name.

## Pictures

Rows of the zone `Pictures` in `cloudRecords` have the kind `picture`; the name and `rowKey` are the file's name and
the digest is empty. A picture is referenced by `art.picture`, `prints.picture` or `prints.backPicture`.

- **Upload and delete.** `picturesToUpload` lists referenced files this device has that have no `cloudRecords`
  row; `picturesToDelete` the rows nothing names any more.
- **Download.** `missingPictures(of:)` names what an art lacks here; `storeFetchedPicture` moves a downloaded file
  into `Pictures` and records it in `fetchedPictures` and `cloudRecords`, so it isn't uploaded back.
- **The cache limit** (R4.7). With `.onDemand(limit:)` and a limit, storing and setting the policy end by evicting
  the least recently shown, never one shown in the last hour. An evicted picture keeps its `cloudRecords` row, so it
  is missing again and is not uploaded back. `shown` is set when a picture is stored, when `picture(of:)` returns
  it, and by `markPicturesShown`. A picture noted in the last half hour is left as it is: that spares the disk,
  keeps a picture in use inside the hour, and means showing art takes no write lock (the app remembers what it
  noted, and only a downloaded picture with a stale time is written). Pictures the device drew
  from its own PDFs are never in `fetchedPictures`, so they are never evicted. No limit is not `.everything`: with no
  limit nothing is removed, but a picture still downloads only when first shown.
- **Old files** (R4.4). `removeUnreferencedPictures` deletes files nothing names, leaving alone files modified in the
  last hour: an import writes a picture's file before the row that names it. It also forgets cached pictures
  whose files are gone.
- **Names** (R4.6). Only `SharedPictures.writePicture` and `StoreMerger.makePrint` name a new picture, the first
  as `pictureName(drawnFrom:)` says. Art reads its picture's name from its row; that function only tells whether
  a picture whose file is missing is one this device can draw again.
- **Which picture stays** (R4.10). Art printed in two PDFs can have a picture from either, so two devices can name
  different ones. When a reading is merged, the art keeps the sharper of its picture here and the incoming one
  (`ArtPicture.stays`): more pixels on the long side, then the name that sorts first; any picture over none. Taking
  the incoming one each time would have two devices that sync at the same moment swap pictures forever, deleting
  and uploading each time. The loser is deleted once nothing names it. Reading a PDF follows the same rule
  (`LibraryWriter.setPicture`): a Battle Card's picture replaces the art's only when it stays over it. Giving art
  its Battle Card's picture whatever its size would have the sharper one deleted from iCloud before the next sync
  named it again.
- **Sizes.** A picture's size is noted when it is drawn or, for a token, saved. `measurePictures` notes those saved
  before version 6 from their files' headers; the engine calls it before it first sends.
- **A missing file.** `picture(of:)` and `drawMissingPictures` save a drawing under the name the art has only when
  that is the name of the print they draw from: the same picture, back again, and the row is left alone. For a
  picture another print gave the art, `picture(of:)` returns a drawing without saving it and
  `drawMissingPictures` draws nothing: the picture comes from iCloud. A stand-in saved under that name would pass
  for the sharper original, never be replaced by it, and be sent to iCloud.
- **Drawing** (R4.8). `drawMissingPictures(limit:)` draws up to `limit` pictures for art without one that has a
  print in a PDF this app can reach. Art moved in from an app's old library has none, and Pawn Shop draws pawns
  straight from the PDF.

## A PDF another device read (R3.9)

`addNewFiles` links a file whose source the library has but which this app can't reach, whichever reader read it:
it records this app's access with the `.inFolder` location, without reading the PDF's art (`ArtLibrary.prepare`
reads it all before `commit` finds out it is known).

**A file iCloud Drive hasn't downloaded.** Reading it makes the system download it, which would pull every PDF onto a
device meant to stay thin. So a file whose `ubiquitousItemDownloadingStatus` is present and isn't `.current` is left
for a later scan. A file outside iCloud has no such value and is read as before. The decision is a function of the
status alone, `isDownloaded(_:)`. The older kind of placeholder, a hidden `.<name>.icloud` file, isn't listed by
`ProductScanner.artPDFs`.

## The `TablesideSync` target

`TablesideSync` imports CloudKit and puts a `CKSyncEngine` on the store. It is a target of its own so that an app
that doesn't sync, and `SharedLibraries` itself, need no CloudKit.

### Records in CloudKit

`LibraryRecordCoder` turns a `SyncRecord` into a `CKRecord` and back. A record's name is the `SyncRecord`'s, and its
kind is told from the name (`SyncRecordID(recordName:)`).

| Type | Zone | Fields |
|---|---|---|
| `Source` | `Library` | `format` Int64 (1), `title` String, `payload` Asset (a reading can pass a record's 1 MB) |
| `Note`, `CreatureArt`, `CustomCreature` | `Library` | `format`, `title`, `payload` Bytes |
| `CustomArt` | `Library` | `format`, `title`, `payload` Bytes, `image` Asset |
| `Picture` | `Pictures` | `image` Asset; the record's name is the file's name |

These are the record types to deploy to Production in the CloudKit Console before a release.

- A reading's JSON is written to `<library folder>/Sync/Outgoing/<app>/<record name>` for the upload and deleted
  once the record is sent. The folder is each app's own, so one app clearing what an earlier run left behind
  takes nothing from another app's upload.
- An incoming asset's bytes are read while its event is handled: the file doesn't outlive it.
- A record is built over the server's last known system fields when the store has them, so the save is a change
  to that record and not a conflict.
- A record of one of these types whose payload can't be read (a field that moved) is handed to the store with an
  empty payload, which it keeps aside as it does any record this version can't read. So is a record whose `format`
  is later than this version's, whatever its payload holds. A record of any other type, or of another zone, is
  ignored.
- **Raising `format`.** Nothing of a record in a later format is kept, and the engine's change token is past it,
  so a device that is then updated neither reads the record nor sends its own copy until another device changes
  it. The version that raises `format` must therefore make each device fetch again what its earlier versions
  kept aside: dropping the engine's state once does it, as applying is idempotent.
- The server's record that comes with a refused save has no asset files: CloudKit doesn't download them. A reading
  refused that way is therefore kept aside too, and merged when the fetch that follows brings it whole; until then
  this device doesn't send its own. The other kinds carry their payload in the record and are merged at once.

### The engine

`SyncEngine` is one `CKSyncEngine` for an app's private database, shared by the owners of its zones. An owner is a
`SyncZoneHandler`: the library's is `LibrarySync`, and Turnkeeper's campaigns and Pawn Shop's custom pawns add
theirs to the same engine later. The engine's own code takes plain values, so tests reach all of it but the
CloudKit glue (`SyncEngineCloudKit`).

- **Zones.** At its first start (no saved state) the engine saves every handler's zones. A handler names the
  zones it fetches itself (`unfetchedZones`: the library's `Pictures`), and every fetch leaves those out.
- **What to send.** A handler says what it has to send (`pendingChanges`), and the engine queues it: at each
  start, after it hands the handler fetched changes or refused saves (merging can leave something to send), and
  when told the handlers changed. When the handler then has no record for a queued save (the row is gone, or the
  cloud holds this content already), the engine forgets the save; `CKSyncEngine` would otherwise keep it pending
  forever.
- **Routing.** Fetched and sent records go to the handler whose zone they are in. A delete the server refused
  because it never had the record counts as deleted.
- **Refused saves** go to the handler's `settle`, which says whether its zones must be saved again.
- **The account.** On a sign-in or a change of account every handler is told the user, then the zones and what is
  pending are queued again; on a sign-out it is told there is none. `CKSyncEngine` reports a sign-in at an app's
  first start too, and the apps on a device share `cloudRecords`, so a handler forgets the server only when the
  user isn't the one it knew (`syncState.account`): an app that starts syncing where another already does keeps
  what that one learned, instead of sending every record again.
- **A deleted zone** is told to every handler with its reason, since a handler may no longer list a zone that is
  gone. A handler that answers true has its zones saved again and everything queued.
- **State.** The engine's state goes to a `SyncStateStore`, which `LibrarySync` keeps in `syncState`.
- **Subscriptions.** The subscription ID is `tableside-sync-` and the app's bundle identifier, so each app keeps its
  own.

### The library's handler

`LibrarySync` owns the zones `Library` and `Pictures`. It opens a `SharedLibrary` of its own (the store isn't safe to
share), and the store makes every decision: this only hands records between the store and the engine.

- **Starting.** `LibrarySync.start(app:fallback:containerIdentifier:handlers:)` gives nothing when the build names
  no container (`TablesideSyncContainer` in `Info.plist`, R6.1) or iCloud isn't available, and the app then works
  on the device alone (R2.4); `SyncStatus.withoutSync` says which of the two it is. No `CKContainer` is made before
  the name is checked: one the build has no entitlement for stops the app. Before the engine starts, the handler
  applies the records kept aside that this version can now read (`applyRemote([])`), measures the pictures saved
  before sizes were kept (`measurePictures`), and is told the account that is signed in, whether or not
  `CKSyncEngine` reports a sign-in at that start.
- **Sending.** `pendingChanges` is `syncCandidates`. `record(for:)` is `outgoingRecord`, remembered by record name
  until the server takes it and `markSent` stores the fields it answered with.
- **Local changes.** The library's Darwin notification, from this app or another, queues what there is to send
  two seconds after the last one, so a run of changes goes up together. The run of pictures it starts isn't
  waited for, so the next change doesn't cancel a transfer under way.
- **Fetched records** are decoded and applied with `applyRemote`. When that fails it is tried once more. When it
  fails again, syncing stops for this run with the status `failed`: nothing more is sent, and the engine's state is
  dropped and stays dropped, so the next launch fetches everything again (applying is idempotent).
- **Refused saves.** `serverRecordChanged`: the server's record is applied as a fetched one is, and the store then
  says whether the result still has to be sent. `unknownItem`: the stored system fields are forgotten and the
  record is sent as new. `zoneNotFound`: the server is forgotten, as a zone that is gone holds none of the
  records, and the zones are saved again with everything. `userDeletedZone`: syncing pauses, as below.
  `quotaExceeded`: the status is `storageFull`, and nothing is queued again until the library changes, a fetch
  brings something or the server is forgotten (R5.4). Anything else the engine retries.
- **A deleted zone.** Deleted by the user in Settings (`purged`): syncing pauses and the server is forgotten, until
  the app calls `resume()`, which uploads everything again (R5.3). While paused, fetched records are still merged
  in, and nothing is sent. Deleted any other way: the server is forgotten and everything is uploaded again (R5.2).
- **The account** (R5.1): see "The engine". A sign-out shows as `unavailable`.
- **In the background.** `close()` closes the database and makes every later use close it again when done, until
  `open()` (shared libraries R5.4).
- **Status** (R2.5). `status` and `statusUpdates()` give `syncing` while a fetch, a send or a run of pictures is
  under way and `upToDate` otherwise, unless something is wrong: `paused`, `storageFull`, `unavailable` or
  `failed`. An app that isn't syncing shows `unsupported` or `unavailable`.

### Pictures in iCloud

`PictureCloud` keeps the pictures in step through a `PictureStore`: `CloudPictureStore` over the zone `Pictures` of
the private database, or a stand-in in tests. It has a library of its own, so that drawing and transfers keep
nothing else waiting. The store's bookkeeping is in "Pictures" above.

- **Drawing comes first** (R4.8). At the start the pictures the art lacks are drawn, 100 at a time, until none is
  left that this app can draw; a library moved in from an app's old one has about 10,000 to draw, once. Nothing
  is sent until that is done: each picture drawn changes its PDF's reading, and the readings would be sent over
  and over meanwhile. Fetched records are merged in all the same. Drawing stops for now when a picture can't be
  drawn or saved and nothing else could be, as with a full disk.
- **A run** uploads, downloads ahead and deletes, in that order. It starts when the drawing is done, after local
  changes, after each finished fetch and each send (the first send makes the zones), on `resume()` and when the
  policy is set. A run asked for while one is under way makes that one go round again. Nothing runs while
  syncing is paused.
- **Upload** (R4.1): 25 at a time until `picturesToUpload` is empty. Those iCloud holds already are only noted;
  the rest are saved, and a save that finds the picture there already counts, as a picture never changes.
- **Download when shown** (R4.2): an app calls `LibrarySync.fetchPictures(named:)` with `missingPictures(of:)` when
  `picture(of:)` gives none. It downloads those the device lacks, stores them with `storeFetchedPicture`, notes
  all of them as shown, and doesn't wait for whatever else syncing is doing.
- **Download ahead** (R4.9): with `.everything`, the missing pictures are downloaded 25 at a time until none is
  missing or a batch brings nothing. Those iCloud didn't have (no device has uploaded them yet) aren't asked for
  again until the app next starts. A picture that failed to download any other way ends the run instead, and is
  asked for again in the next. These downloads don't count as shown.
- **Delete** (R4.4): only once a fetch has finished in this run of the app, when it is known what art still
  uses, `picturesToDelete` is deleted from iCloud, then `removeUnreferencedPictures` deletes the files here. A
  fetch that couldn't bring a zone's changes (`SyncPhase.fetchFailed`), or whose records couldn't be merged in,
  doesn't count, and takes back what an earlier one allowed.
- **A full iCloud** (R5.4) ends the run with the status `storageFull`, until a later run gets through. Any other
  failure, as without a network, ends the run until the next one.
- **The cache** (R4.3, R4.7): `LibrarySync` passes on `fetchedPicturesByteCount`, `clearFetchedPictures`,
  `picturePolicy`, `setPicturePolicy` and `markPicturesShown`.

### Builds (R6)

An app syncs only when its `Info.plist` names the container under `TablesideSyncContainer`, and a build names it only
when it is signed with the entitlements for it. App Store and Xcode builds carry both in the app's own files.
A Developer ID build gets them from `scripts/add-icloud-entitlements.sh <app> <entitlements> <team ID> <provisioning
profile>`, which apps reach at `.build/checkouts/tabletop-kit/scripts/`, as they do `package-appstore.sh`:

- It embeds the provisioning profile and sets the application and team identifiers, the CloudKit service, the
  containers, and the CloudKit and push environments in the entitlements to sign with. Keys that are there already
  are replaced, so it can run again on the same files.
- `ICLOUD_CONTAINERS` lists the containers, separated by spaces; the default is the suite's. Field Guide, whose lore
  stays in a container of its own, names both.
- `ICLOUD_ENVIRONMENT` is `Production` or `Development`. Without it, an App Store build (`CHANNEL=appstore`) gets
  Production and every other build Development (R6.4), the same split the iOS projects make between Release and
  Debug. `package-appstore.sh` refuses an app whose entitlements or `TablesideSyncEnvironment` name Development.
- `TablesideSyncContainer` and `TablesideSyncEnvironment` are written when the suite's container is among them, and
  removed otherwise.

The shared library keeps one set of sync state, and CloudKit's two environments hold separate data. An Xcode build
names Development in `TablesideSyncEnvironment` too. Sync records its account as `Development:<user>` there and as the
plain user in Production, so a move either way is an ordinary account change (R5.1, R6.3). Released apps that predate
the key read it the same way.

`scripts/test-add-icloud-entitlements.sh` checks this on a generated app, from `make test-scripts`.

## Known limits

- A PDF removed on one device while another is changing its art, or before another device's first sync, can come
  back; the user removes it again.
- A PDF is the same PDF only when its bytes are (its ID is its SHA-256). Whether two downloads of one Paizo PDF are
  byte-identical is **not checked yet**. If they differ, each device's copy is a source of its own: the art still
  merges (its keys come from the embedded pictures), each piece with a print per copy, the product is listed twice,
  and R3.9 doesn't apply. Art keyed by its place on the page (flattened pages) would be doubled.
- A watched folder in iCloud Drive is untested on real devices: whether the download status is reported for a
  folder reached through a bookmark, and what an app does when it draws from a PDF that is linked here but has since
  been removed from the device (the read then downloads it, and blocks until it has).
- An app version from before `modified` existed writes 0, so its edits lose a conflict. One from before
  `picturePixels` leaves the old size when it gives art another picture, so that picture can win or lose wrongly.
- A custom art's image isn't kept with a record this version can't read: applied later, the record brings no image.
  The same goes for a custom art's record that comes with a refused save, so an image changed on two devices at
  the same moment can stay different on the two until it is changed again.
- Art's name, size, traits and fingerprint, where two devices differ, are still the incoming record's: two devices
  that sync at the same moment can swap them until one goes first.
- Each app's engine fetches the same changes; the second finds them applied and writes nothing.
- The CloudKit glue (`SyncEngineCloudKit`, `LibrarySyncStart`, `CloudPictureStore`) has no unit tests: a container
  without the entitlement stops the process. The end-to-end check below covers it.
- After iCloud data was deleted by the user, an app that starts for the first time still makes the two empty zones;
  nothing is uploaded to them until `resume()`.
- A picture iCloud didn't have when a device that keeps everything asked for it is asked for again only when the app
  next starts.

## End-to-end check

First, without any build: download one pawn PDF from Paizo twice and compare the files' SHA-256 (see the known
limit above). The rest needs a signed build with the container. Mac and iPad on one account, both in the Development
environment: a first sync from a full Mac library to an empty iPad; the same PDF read on both first; a note, a
creature's art and a custom creature edited on each side; two apps open on the Mac while the iPad changes something;
a PDF removed; a picture shown on the iPad without its PDF, then the cache cleared; signed out of iCloud; iCloud data
deleted in Settings, then `resume()`; a watched folder in iCloud Drive whose PDFs aren't downloaded on the iPad
(nothing downloads by itself; a PDF downloaded by hand is linked, not read). Before a release, deploy the schema to
Production in the CloudKit Console.
