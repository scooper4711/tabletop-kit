# Library sync: requirements

Pawn Shop, Turnkeeper and Field Guide share one art library and one creature library on each device (shared
libraries). This spec makes them the same on the user's devices, through the suite's own container in the user's
private iCloud (CloudKit) database, whichever of the three apps is open.

Issue: tabletop-kit#44. The apps turn it on in turnkeeper#67, field-guide#40 and pawn-shop#30. What each app shows,
and its settings, stay in its own spec.

## R1 What syncs
- R1.1 The art read from PDFs (sources, art, prints, aliases), notes, the art chosen for creatures, custom creatures,
  and custom art with its images.
- R1.2 Never the PDFs, nor how a device reaches them, nor watched folders, claims or moves.
- R1.3 Art reaches other devices only through the user's private database (shared libraries R2.9).

## R2 Where
- R2.1 One container for the suite, the private database, a zone `Library`.
- R2.2 Whichever suite app is open syncs every kind of record, whichever app made it.
- R2.3 Two or three apps on one device syncing at once lose nothing and upload nothing twice in a loop.
- R2.4 Without iCloud (signed out, off for the app, a build without the entitlement) each app works locally and
  doesn't crash.
- R2.5 An app can say whether the library syncs (`SyncStatus`).

## R3 Merging
- R3.1 A first sync merges the library on the device with the one in iCloud; neither replaces the other.
- R3.2 A PDF read on two devices by the same reader is one piece of art per picture, not two.
- R3.3 A newer reader's reading of a PDF replaces an older one on every device, the old keys kept as aliases; an
  older app doesn't read the PDF again.
- R3.4 Art two devices grouped differently (a Battle Card joined to a pawn on one) ends up grouped on both.
- R3.5 Notes, creature art and custom creatures follow the art when its ID changes.
- R3.6 The later edit wins; a corrected note wins over an uncorrected one.
- R3.7 A note for art that hasn't arrived yet waits for it.
- R3.8 Removing a PDF removes its art on every device.
- R3.9 A PDF another device read is linked, not read again, when this device first sees the file.

## R4 Pictures
- R4.1 Each art picture is an asset in the zone `Pictures`, uploaded once by a device that has it.
- R4.2 A device without the PDF downloads a picture when it is first shown.
- R4.3 Downloaded pictures are a cache the user can clear, with its size shown.
- R4.4 Pictures no art uses any more are deleted from iCloud, and their files from each device.
- R4.5 Custom art's images sync with their record, not on demand.
- R4.6 A picture never changes once saved: a different rendering is a new picture under a new name.
- R4.7 A device can limit the size of its downloaded pictures; past the limit the least recently shown are removed,
  and come back from iCloud when next shown.
- R4.8 A device that can reach the PDFs draws the pictures its art lacks, so they can be uploaded.
- R4.9 A device can instead keep every picture: it downloads them all ahead of time, for use without internet, and
  removes none.

## R5 Accounts and resets
- R5.1 Another account signing in uploads the library to it.
- R5.2 A deleted zone is uploaded again.
- R5.3 iCloud data the user deleted pauses syncing until they turn it on again.
- R5.4 A full iCloud is reported, and syncing carries on when there is room.

## R6 Builds
- R6.1 A build names the container in its `Info.plist` (`TablesideSyncContainer`) only when it has the entitlements.
- R6.2 Developer ID builds get the entitlements from `scripts/add-icloud-entitlements.sh`.
