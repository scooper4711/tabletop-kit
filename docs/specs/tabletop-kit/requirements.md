# Tabletop Kit: requirements

Swift libraries shared by Pawn Shop, Combat Pad and Field Guide, on macOS and iPadOS. The apps may not ship
Paizo's art, so each reads it from PDFs the user bought: pawn and token boxes and Battle Cards decks. Tabletop
Kit holds that reading in one place, and (in later releases) the creature data and battle cards that Combat Pad
and Field Guide share. It contains no Paizo art or text.

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
- R1.7 Pawns printed without cut outlines (the second half of Monster Core Pawn Box, Dawn of Flame) are found
  from their pictures: each picture with its own transparency is a pawn, named from the label under it, its back
  the same picture mirrored on the following page. Pages that are a single flattened image with no text (the
  second half of NPC Core Pawn Box) give no pawns and are reported as unreadable.
- R1.8 A product's readable title comes from its file name: "PZO1234 Pathfinder Pawns- Bestiary Box PDF.pdf"
  becomes "Pathfinder Pawns: Bestiary Box".

## R2 The art library (`ArtExtraction`)
- R2.1 A library of PDFs and the art found in them is kept in a folder the app chooses, between launches.
- R2.2 A PDF is added either kept (the library copies it, so the art survives the original being moved; Pawn
  Shop) or referenced (the library remembers where the file is, without copying it; Combat Pad and Field Guide
  referencing Scrollkeeper's downloads, so the iPad holds each PDF once).
- R2.3 A referenced PDF that has been deleted, moved or can no longer be opened is reported as missing, with the
  art that came from it, so the app can tell the user which PDFs it needs back. When the file returns, its art
  is available again without importing it anew.
- R2.4 Adding a PDF that is already in the library changes nothing, except a PDF in which nothing was found: it is
  read again once by each newer version of the reader.
- R2.5 Art printed in several products is stored once, with every product that prints it. Where a Battle Card and
  a pawn show the same painting, the sharper picture is used.
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
  Combat Pad and Field Guide, imported from the pf2e system repository (every NPC and complex hazard, the
  conditions, and a glossary of what the creatures link to), and art from the art library matched to creatures by
  name. Running the import twice on the same input produces identical output.

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
