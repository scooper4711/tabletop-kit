# Tabletop Kit: requirements

Swift libraries shared by Pawn Shop, Turnkeeper and Field Guide, on macOS and iPadOS. The apps may not ship
Paizo's art, so each reads it from PDFs the user bought: pawn and token boxes and Battle Cards decks. Tabletop
Kit holds that reading in one place, along with the creature data and battle cards that Turnkeeper and Field Guide
share. It contains no Paizo art or text.

## R1 Finding art in PDFs (`ArtExtraction`)
- R1.1 Runs on macOS 15 and iPadOS 18, using only PDFKit, Core Graphics and Core Text.
- R1.2 Every pawn printed with a cut outline is found from the outline, named from the label printed inside it,
  and sized (small, medium, large, huge) from the outline. Pawns printed sideways are turned upright.
- R1.3 Each pawn's back is taken from the mirrored position on the following page; when there is none, the back
  is the front mirrored.
- R1.4 Art is fingerprinted so that copies of one painting (on one page, or reprinted in another product) can be
  recognized, while pawns with the same name and different art are kept apart.
- R1.5 Round tokens are found from the circle their art is clipped to, sized from the cut circle (up to 1"
  medium, 2" large, 3" huge, larger gargantuan), and named from the label on the mirrored back page or the name
  along the rim. The token's art can be drawn alone, without the page background, cut line or printed name.
- R1.6 Battle Cards decks (a PDF, or the folders it is in, named "… Battle Cards"; one PDF or a FRONT/BACKS pair)
  give each card's creature: the last picture of its own that the art side draws, transparent around the figure,
  with its name, size and traits read from the stat block. Hazards, continued stat blocks and rules pages are
  skipped.
- R1.6a Item decks (a PDF, or the folders it is in, named "… Deck" or "Deck of …", other than spell, condition,
  NPC, rules and other decks without art; one PDF, or a Fronts/Backs pair even when the two names differ in more
  than the side) give each card's item art the same way, named from the card: the capitals before "ITEM n" or
  "MINOR/MAJOR/GRAND GIFT", else the first lines when all in capitals or all in title case. Pages naming the
  deck or its instructions are skipped. Deck of Endless Treasure prints the art beside the name on one page.
- R1.6b Item decks sold as pictures (a folder of `…Fronts<n>.jpg` and `…Backs<n>.jpg` in an item deck's folder,
  such as Weapons & Armor) give each back's item cut out of the background all backs share, named from the
  title across the top of its front. The pictures are kept in the library, as token art is.
- R1.7 Pawns printed without cut outlines (the second half of Monster Core Pawn Box, Dawn of Flame) are found
  from their pictures: each picture with its own transparency is a pawn, named from the label under it, its back
  the same picture mirrored on the following page. Pages that are a single flattened image with no text (the
  second half of NPC Core Pawn Box) give no pawns and are reported as unreadable.
- R1.8 A product's readable title comes from its file name: "PZO1234 Pathfinder Pawns- Bestiary Box PDF.pdf"
  becomes "Pathfinder Pawns: Bestiary Box".

## R2 The art library (`ArtExtraction`)
- R2.1 A library of PDFs and the art found in them is kept in a folder the app chooses, between launches.
- R2.2 A PDF is added either kept (the library copies it, so the art survives the original being moved; Pawn
  Shop) or referenced (the library remembers where the file is, without copying it; Turnkeeper and Field Guide
  referencing Scrollkeeper's downloads, so the iPad holds each PDF once).
- R2.3 A referenced PDF that has been deleted, moved or can no longer be opened is reported as missing, with the
  art that came from it, so the app can tell the user which PDFs it needs back. When the file returns, its art
  is available again without importing it anew.
- R2.4 Adding a PDF that is already in the library changes nothing, except a PDF in which nothing was found: it is
  read again once by each newer version of the reader.
- R2.5 Art printed in several products is stored once, with every product that prints it. Where a Battle Card and
  a pawn show the same painting, the sharper picture is used.
- R2.5a Item art is never merged with creature art of the same name, and matching creatures never picks it;
  items are matched by name, then without their grade or potency ("Healing Potion (Minor)", "+1 Striking
  Longsword").
- R2.6 Each piece of art can be drawn alone, upright, on a transparent background, at a requested size.
- R2.7 Folders can be watched, such as Scrollkeeper's downloads: the PDFs of art in them that the library
  doesn't have are added by reference on request, with progress.
- R2.8 A token's art is kept as a picture when its PDF is added, so it stays available when the PDF goes
  missing. Other art is drawn from its PDF when asked for.
- R2.9 Art with no name printed is left out of the library.
- R2.10 The apps share a store over the art library (`CreatureArt`): importing a watched folder or chosen PDFs with
  progress and a summary, a catalog of the art (name, game, whether a remastered product prints it, whether it is
  a token, whether it can be drawn, the PDFs printing it) and of the PDFs (missing or not), and pictures drawn off
  the main thread.

## R3 Test support (`ArtExtractionTestSupport`)
- R3.1 Draws small PDFs laid out like Paizo's (pawns with cut outlines and labels, tokens, Battle Cards decks), so
  the libraries and the apps can be tested without Paizo's PDFs.
- R3.2 Tests that read real Paizo PDFs run when a git-ignored `TestData` folder holds them, and are skipped
  otherwise.

## R4 Creatures (`Bestiary`, `CreatureImport`)
- R4.1 Creatures (`Bestiary`, `CreatureImport`): the creature model, stat-block presentation and rules shared by
  Turnkeeper and Field Guide, imported from the pf2e system repository (every NPC and complex hazard, the
  conditions, and a glossary of what the creatures link to), and art from the art library matched to creatures by
  name. Running the import twice on the same input produces identical output.
- R4.2 A creature's immunities include those its traits grant by their rules text, even when the source data
  leaves them out: constructs (bleed, death effects, disease, healing, nonlethal attacks, poison, spirit, vitality,
  void, and the doomed, drained, fatigued, paralyzed, sickened and unconscious conditions), mindless creatures
  (mental) and swarms (the grabbed, prone and restrained conditions). Each immunity shows once. Undead get none,
  since their trait's text grants none.
- R4.3 A creature's health can be described to players without numbers: Unharmed (full), Healthy (76–99%),
  Injured (51–75%), Bloodied (26–50%), Near Death (1–25%) and Down (0 HP or less).

## R5 Battle cards (`BattleCards`)
- R5.1 A creature's card front shows its stat block with the template and conditions applied, in a look of its
  own, not Paizo's Battle Cards': Pathfinder on parchment in a stone frame, the level on a heraldic shield and gold
  rules between sections; Starfinder on a dark panel in steel corner brackets, the name on a cyan bar and the level
  in a hexagon. An elite card adds a thin gold frame. Linked words open glossary popovers, two deep.
- R5.2 A card back shows the creature's art (from the user's PDFs, supplied by the app) with its name: Pathfinder in
  a painted landscape picked by its traits (undead and spirits in haunted ruins, fiends and fire on lava, cold in
  snow, earth, dragons and giants in a canyon, the rest in a meadow), its name centered on the banner of a parchment
  ribbon; Starfinder glowing on a dark texture, its name on a terminal plate, an elongated hexagon of dark glass with
  scanlines and glowing monospaced type.
- R5.3 The cards are drawn with UI art from the user's own Rexard packs, which can't be published: `CardArtImport`
  copies the pieces from the packs into an app's folder at build time, and the app passes that folder to the
  cards. Without a piece, the card draws plain color in its place.
- R5.4 A card front shows the creature's conditions as colored tags under its traits ("Frightened 2", "Bleed 1d6").
  Tapping a tag shows the condition's rules text in a glossary popover.
- R5.5 An interactive card shows the front and back of a creature and lets the user flip it and show it full
  screen. Tapping empty card area shows or hides two corner icons: flip (top right) and full screen (bottom
  right); with a pointer, each icon shows while the pointer is over its corner. Taps on links and trait or
  condition tags go to them, not to the card. Full screen opens with the icon or a pinch out, on the face that's
  showing, and closes with its icon, a pinch in or Escape; flipping works in it too.
- R5.6 The apps share one view that loads a creature's art at full size from a loader they supply, so a card
  back's art is drawn the same way in each.

## R6 About screen (`AppNotices`)
- R6.1 Each app shows an About screen with the notice Paizo's Community Use Policy prescribes, word for word with
  only the app's name filled in, and the Paizo Compatibility License's line "Pathfinder and Starfinder are
  registered trademarks and copyrights of Paizo Inc."
- R6.2 The screen also gives a one-line description of the app, credits for the third-party content it ships,
  links to the policy and paizo.com, and where to reach the author, as the policy requires.
- R6.3 On the Mac it is the About panel, from the app menu; on the iPad, a sheet the app opens from a button.
- R6.4 The screen lists the full text of every license the app's bundled content requires it to ship (such as the
  Open Game License, the ORC License and fonts' licenses), read from a folder the app bundles. On the iPad each
  opens on its own page; on the Mac the texts follow the credits in the About panel.

