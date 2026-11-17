# Shared libraries: requirements

Pawn Shop, Turnkeeper and Field Guide each read the user's pawn, token and Battle Cards PDFs into an art library of
their own today, and Turnkeeper alone keeps custom creatures. This spec puts one art library and one creature library
in the toolkit's App Group (Tableside Shared R1), read and written by all three apps, and gives extracted art an ID
that is the same on every device, so libraries can later sync through the user's private iCloud.

Issues: tabletop-kit#15 (this spec), #16 and #33 (implementation), #44 (sync); Pawn Shop #46 (stable pawn IDs) and
#27 (the move); Turnkeeper #18; Field Guide #17 and #40. What each app shows stays in its own spec.

## R1 Where the libraries live
- R1.1 Both libraries live in the group's `Tableside` folder, next to Scrollkeeper's (Tableside Shared R1.3). Only
  Pawn Shop, Turnkeeper and Field Guide write there.
- R1.2 An app outside the group (an ad hoc build, the tests) keeps both libraries in a folder of its own, in the
  same format, and carries on as today.
- R1.3 Each PDF is read once, by whichever app sees it first, and its art shows in all three apps.

## R2 Art IDs
- R2.1 Every piece of art found in a PDF gets an ID that any app on any device derives the same way: the same PDF
  read by the same reader gives the same IDs everywhere, in any order of import.
- R2.2 The ID comes from the picture Paizo embedded, not from where or how an app found it on the page: a better
  detector or a different crop doesn't change it, and art reprinted in another product gets the same ID.
- R2.3 Where one product prints one picture under several names or sizes (numbered tokens "Drone 1" to "Drone 6",
  "Mantis, Deadly" and "Mantis, Giant" on Battle Cards, an elemental printed Large and Huge), each gets an ID of
  its own.
- R2.4 Art without a picture of its own (a page printed as one flattened image) gets an ID from its PDF, its page
  and its place on the page.
- R2.5 Art printed by several products is one piece of art that answers to the ID of each print. It shows one of
  them as its ID, chosen the same way on every device, and a reference saved with any of them finds it.
- R2.6 What the user makes (custom creatures, custom pawns, pasted or dropped art) keeps a random ID.
- R2.7 Art imported before this keeps its old ID as an alias, so saved Pawn Shop sheets, Turnkeeper's `library:`
  art paths and Field Guide's art choices keep finding it.
- R2.8 A reference to art the library doesn't have (a PDF not imported on this device) says what is missing, with
  the art's name and product ("Goblin Warrior, from *Monster Core Pawn Box*"), never a blank.
- R2.9 Art is never stored in a document or file the user can share, which would hand Paizo's art to people who
  didn't buy it. It reaches the user's other devices only through their private iCloud database (#44).

## R3 The art library
- R3.1 One art library holds the PDFs (kept, or referenced where they are), each piece of art with every product
  that prints it, and its pictures.
- R3.2 Each piece of art is saved as a picture when its PDF is read, named by its ID, and the apps show and print
  from that picture, so art stays available when its PDF goes missing or is out of an app's reach.
- R3.3 What one app learns about a piece of art helps the others: Pawn Shop's names, tags and corrections help
  match creatures in Turnkeeper and Field Guide, and a creature matched there helps Pawn Shop name a pawn.
- R3.4 The art chosen for a creature is the same in Turnkeeper and Field Guide.
- R3.5 Each app keeps what is only its own: Pawn Shop its sheets, layouts and custom pawns; Turnkeeper its
  campaigns and encounters.
- R3.6 A PDF one app was given access to (a file or folder the user chose there) may be out of the others' reach.
  They still show its art from the saved pictures, and tell the user which app reads it again for a newer reader.

## R4 The creature library
- R4.1 Custom creatures are one list in both Turnkeeper and Field Guide and don't belong to a campaign. Turnkeeper
  lists the creatures made for the current campaign or scenario first.
- R4.2 The art the user pastes or drops is kept in the creature library with its image files.
- R4.3 Field Guide shows custom creatures in its Bestiary, searchable and with their battle cards. Making and
  editing them stays in Turnkeeper.
- R4.4 Pawn Shop lists each custom creature with art as a pawn it can print; one without art is left out.
- R4.4a Its pawn's size is the creature's size from its traits; Tiny prints as Small, and a size that is missing or
  isn't one of Paizo's prints as Medium.
- R4.5 Turnkeeper's encounters keep referring to custom creatures by their `custom.<id>` keys, and sharing a
  library (`sharedVersion` on custom creatures and art) keeps working.

## R5 Two apps at once
- R5.1 Two or three apps can read and write the libraries at the same time without losing a change.
- R5.2 An app sees another app's changes within a second, without polling and without reading again what didn't
  change.
- R5.3 A PDF one app is reading isn't read again by another meanwhile.
- R5.4 On the iPad an app isn't stopped by the system for holding a shared file locked when it is suspended.

## R6 Moving into the group
- R6.1 The first app on a device with this version moves its library into the group; each later app merges its own
  into it. Each library moves at most once: Pawn Shop changes its pawn IDs (#46) and moves (#27) in the same step.
- R6.2 Merging keeps each piece of art once, by its ID (R2), with every product, the user's names, tags and
  corrections, and the art chosen for creatures. Where two apps disagree, the user's corrections win over what was
  read, and the later correction wins over the earlier.
- R6.3 PDFs the library keeps are moved, not copied, and a PDF kept by two apps is kept once. PDFs that were missing
  stay listed as missing.
- R6.4 Old IDs become aliases (R2.7). The move is tested on a copy of a real library (about 10,000 pieces of art
  from 85 PDFs) and on Pawn Shop sheets saved before it.
- R6.5 An app that can't finish the move keeps its own library and says so; the next launch tries again.
