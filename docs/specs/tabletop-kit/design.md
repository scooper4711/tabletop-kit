# Tabletop Kit: design

A Swift package (`Package.swift`, macOS 15 and iOS 18) of libraries the apps depend on by URL and version tag.
Each library is unit tested on test PDFs drawn by `ArtExtractionTestSupport`; CI also builds for the iOS
simulator.

## Modules
| Module | Contents |
|---|---|
| `ArtExtraction` | PDF scanning, pawns, tokens, Battle Cards, figures, fingerprints, and the art library |
| `ArtExtractionTestSupport` | Test PDF drawing (`DrawnPawn`, `DrawnToken`, `DrawnCard`, `makePDF`, …), published for the apps' tests |
| `CreatureArt` | `CreatureArtStore`, an actor over `ArtLibrary` that Combat Pad and Field Guide share |
| `Bestiary` | Creatures, stat-block presentation, conditions and rules text, from Combat Pad |
| `CreatureImport` | The pf2e repository's creatures, conditions and glossary, written for `Bestiary` to load |
| `BattleCards` | SwiftUI card fronts and backs, card text, glossary popovers, fonts, and `CardArtImport` |

## Paizo pawn PDFs
Measured across 61 Pathfinder and Starfinder pawn PDFs:
- Most pawns have a cut outline: a stroked path of straight edges and two curves (`v`/`c`) that round the
  head corners. Outlines are drawn on the page or inside a form XObject; the stroke is red, but detection
  relies on shape and size, not color.
- Upright outline sizes (points): small 60×81, medium 81×138, large 138×180, huge 215×281. Mediums stand
  upright on the page; small, large and huge are printed sideways, with the curves on the left or right edge.
- Pages come in pairs: a front page followed by its back. The back page mirrors positions around the page's
  vertical axis (offset by any bleed) and flips the art horizontally. Cover and credit pages have no outlines.
- Art is clipped to a frame cell around each outline, so a clip to the outline never picks up a neighbor.
- The label sits inside the outline's foot: the name in the largest type (one or two lines), the copyright
  in fine print, and in some products a reference code (such as "B 62") in fine print in a corner. Some
  labels are drawn twice (fill and outline), so their text reads each chunk twice.
- A page holds several copies of a pawn that differ only in a colored badge. Newer PDFs reuse one image
  object for the copies; older ones embed each copy again with different compression. One name can also
  have different art.
- Token PDFs print round tokens instead. Each token's art is images clipped to a circle (a `W n` path of
  curves, sometimes cut flat on one side), reaching a 1/8" bleed past the cut. Measured on two:
  - Alien Core Token Box: art pages alternate with label pages, which mirror the art pages' positions and
    print each token's number, name and copyright on a dark disc. The red cut circles are one raster overlay
    across the page; colored bands at the foot tell copies apart. Clips are 90, 162 and 232 pt (1", 2", 3"
    cuts); art reaching past the circle is embedded as separately cropped images per copy.
  - Murder in Metal City Tokens: 62 pt clips on a full-page dark background image, the art transparent
    around the figure (a soft mask), the cut line a filled vector ring, and the name set along the rim one
    letter per text object, twice (outline and fill), with copy numbers ("Smog Scamp 2"). The second page is
    the duplex back. The font maps a hyphen through its ToUnicode CMap only.
- Some products print pawns without cut outlines: the second half of Monster Core Pawn Box (large pawns, sideways,
  three by five to a page) and all of Dawn of Flame (mediums upright, smaller and larger ones sideways). Each pawn
  is a picture with a soft mask, about 10 pt of bleed larger than its outline (a medium's is about 100 × 146 pt),
  with the name and copyright printed along its foot, inside the picture's edge or just outside it. Labels are
  drawn twice (a fill and an outline), the copies sometimes split into different pieces, and words are broken
  where the type is kerned ("PITB", "ORN ADEPT"). Back pages draw the same image objects mirrored.
- Not yet handled: pages that are only a raster image (the second half of NPC Core), and terrain sets with
  rectangular outlines.

## Paizo Battle Cards
Measured across eleven decks (Bestiary 1–3, Monster Core, NPC, NPC Core, Abomination Vaults, Book of the Dead,
Fists of the Ruby Phoenix, Alien Archive 1 & 2 and 3 & 4), 289 × 425 pt cards (Starfinder 289 × 431):
- Layouts: one PDF with each card's art page just before its stat page (Bestiary); one PDF with runs of stat
  pages each followed by a run of the same cards' art (Monster Core, NPC Core: runs of about 110); or two PDFs,
  "… FRONT(S)" and "… BACKS", paired page by page. Art pages print no text, except Starfinder's, which print the
  name above the art. The NPC deck's combined PDF prints no art of its own, and the Deck of Endless NPCs is not
  a Battle Cards deck.
- An art page draws the background, frame and badges every card shares, then the card's own pictures. The
  creature is the last of those, an image with a soft mask that is transparent around the figure; first-edition
  decks draw a zoomed copy of it behind the frame, and the creature's canvas is often the whole card, with
  transparent margins.
- The creature's picture is the pawn box's painting, at about 2.9 times the pixels across (1.2 to 6.3) in the
  Bestiary deck, and some cards use different paintings from the pawn box (Giant Centipede, Flash Beetle, Orc
  Warrior).
- PDFKit reads stat pages in a mostly natural order: "AEON, ARBITER CREATURE 1" (a backspace sometimes follows
  the name), then the traits in capitals, wrapping onto the Perception line in Bestiary 2. On a few cards the
  alignment and size come before or after the name. Starfinder prints "NAME CR n", "XP n" and "LE Medium
  humanoid (human)", but sometimes the name shares its line with the type, or CR comes several lines down.
  Long stat blocks continue on a card headed "(Name; continued from card n)".
- Reading all eleven decks takes about 35 seconds (release build); they give about 2,700 creatures.

## Extraction (`ArtExtraction/Extraction`)
- `PageScanner` walks a page's content stream with `CGPDFScanner`, tracking `q`/`Q`/`cm`, recursing into
  form XObjects (with their `Matrix`), and building paths from `m l c v y re h`.
  - On `S`/`s`/`B`/`b` it records each subpath with two curves and otherwise straight edges as an `Outline`:
    its bounding rect in page space and the edge holding the curves (`headEdge`).
  - On `Do` of an image it records an `ImagePlacement`: the rect, transform and stream, the circle it is
    clipped to (a `W` path of one subpath with at least three curves whose points all lie on a fitted circle,
    kept through `q`/`Q`), and the image's `ImageIdentity` (SHA-256 of its data and a 16×24 grayscale
    thumbnail of its decoded pixels), computed once per image object.
  - It records each piece of text shown (`Tj`, `TJ`, `'`, `"`) where its text matrix (`BT`, `Tm`, `Td`,
    `TD`) puts it, decoded through the font's ToUnicode CMap (`FontDecoder`: `bfchar` and `bfrange`).
- `TokenFinder` turns a page's clip circles 36–306 pt across, outside pawn outlines and with art images, into
  `FoundToken`s with their images, fingerprint and the text inside. `TokenPairing` pairs token pages like
  outline pages (most common mirror axis over same-row, same-size circles): a mirrored token is the back when
  it shows the same art, or when it carries words and the front has none (a label side). Names come from the
  token's text in lines (letters shown one by one join into a line), dropping lines without letters (token
  numbers), the copyright and repeated lines. The size is the clip less the bleed: under 1.5" medium, 2.5"
  large, 3.5" huge, else gargantuan. `TokenPicture` draws the token's own images alone, with their soft masks,
  clipped to the circle, into a PNG at the sharpest image's resolution (at most 600 dpi): the background, cut
  line, bands and printed names are left out. Same-name copies whose crops differ too much to match stay
  separate pawns (four in the Alien Core box).
- `PawnSize.classify(_:)` matches an outline's upright size to the table within ±4 pt.
- `PawnExtractor`:
  - pairs page *n* with *n+1* when at least half of *n*'s outlines have a same-size outline at the mirrored
    position on *n+1*; the mirror axis is the most common sum of centers of same-row, same-size outlines;
    paired back pages are not read as fronts;
  - gives each front outline its mirrored back (or none, in which case the back is the front mirrored);
  - names each pawn from the text inside the outline (`PDFKitLabelReader` reads runs with their font size):
    only text at least 80% of the largest size, copyright removed, doubled chunks read once, title case;
  - sets the rotation (0/90/180/270) that turns the head edge to the top;
  - fingerprints the art (`ArtFingerprint`): the digests of the images inside the outline (at least 20 pt
    across) plus the largest one's thumbnail. Pawns merge only when name and size are equal and the art
    matches: equal digests, or thumbnails with a correlation distance (100 × (1 − r)) of at most 20. Copies
    embedded separately measure up to about 10; different figures start above 40.

## Pawns without outlines (`ArtExtraction/Extraction/FigurePawns.swift`)
- `PawnExtractor.foundArt` reads pages with no sized outlines and no tokens for `FigurePawns`: each image with a
  soft mask at least 36 pt across. Each piece of text belongs to the picture it is printed inside (nearest that
  picture's edge) or else the nearest picture within 18 pt, judged at about the middle of the piece (its start moved
  half its estimated length along it). A picture is a pawn only when its text includes "©" or "Paizo", which leaves
  out covers; its foot is the edge nearest the middle of its text, and its head the edge across from it.
- `PageScanner` records each piece of text's size (`Tf` times the text matrix's vertical scale) and direction.
  `LabelLines` rebuilds the label: pieces are grouped into lines across the text's direction and ordered along it,
  joined without spaces (the text carries its own), skipping a piece that starts within the previous piece's
  estimated length (0.45 em a character) or where it started: the second copy. The lines then go through
  `PawnLabel.name` as outlined pawns' labels do. Names over 60 characters are blurbs, not pawns.
- The size is the one whose upright outline is closest to the picture's upright size (summed differences of width
  and height, small to huge), an estimate, since the bleed varies. The next page is the back when it draws at least
  half of the page's pictures again (same image digests); it is not read as fronts.
- Each pawn is an `ExtractedPawn` with the `.card(imageIndex:)` shape, drawn alone like a Battle Card's creature:
  the face is the picture's opaque bounds on its page, with the rotation that turns the head to the top, and the
  back is the front mirrored. `Figure.draw(in:mirrored:rotation:context:)` turns a figure upright with the same
  transform as `PawnFace`.
- A page after the first that is one image covering 90% of it, with no text or outlines, is listed in
  `ExtractionResult.unreadablePages`.
- `PawnExtractor.version` is 2, so PDFs in which version 1 found nothing are read again.
- Measured: Monster Core Pawn Box gives 411 pawns (202 before, 209 of them from pictures), Dawn of Flame 134
  (none before); NPC Core reports its 16 flattened pages.

## Battle Cards and item decks (`ArtExtraction/Cards`)
- `CardDeck.containing(_:)` takes a PDF whose name, or one of its two enclosing folders, says "Battle Cards"
  (`kind` `.creatures`), or names a deck (the word "deck") that isn't one without art: spell, condition, NPC,
  hero point, harrow, chase, critical, rules, reference, character, many worlds, starship (`.items`).
  A file naming a side (FRONT, FRONTS, BACK, BACKS) is paired with the file beside it whose name differs only
  in naming the other side, or else the only file beside it naming the other side (Relics: "Relic Deck
  Fronts", "Relics Deck Backs"); the BACKS file is the deck's `artFile`, which the library keeps. The title comes
  from the nearest enclosing folder naming the deck and starting with Pathfinder or Starfinder (as Scrollkeeper
  files them), without "(Download)" and "- PDF(s)", or else from the file name.
- `CardPairing` pairs pages: page *n* of both PDFs; or in one PDF, each art page with the page after it when
  such pairs cover over a third of the pages; else, when under a tenth of the pages are art pages (Deck of
  Endless Treasure, whose art and name share a page), each page with itself; else the *k*th page of each run
  of other pages with the *k*th of the run of art pages after it. An art page prints under 80 characters and
  no stat block or item name: the NPC deck's combined PDF credits the illustrator on each art page.
- `CardExtractor` scans art pages with `PageScanner.images(on:)` (placements without identities, which are
  slow to compute) and digests each image once. Images on at least half the art pages, and on three or more,
  are shared; the creature is the last image drawn that is not shared, has a soft mask and is at least 20 pt
  across. It becomes an `ExtractedPawn` with the `.card(imageIndex:)` shape, a face on the art page whose rect
  is the creature's opaque bounds, the back the front mirrored, and the creature's digest and thumbnail as its
  fingerprint.
- `CardStats.read(_:)` reads the stat page's PDFKit text (control characters become spaces). The name is the
  run of words in capitals starting the header's line, or one of the three lines above it; rarity, alignment
  and size words read beside it move to the traits, except after a comma ("Herd Animal, Huge"). Pathfinder's
  traits are the words in capitals between the header and "Perception"; Starfinder's are the size, type and
  subtypes of the first "[alignment] Size type (subtypes)" line, without a book reference after a semicolon.
- `ItemCardText.name(in:)` reads an item card: the words in capitals before "ITEM n" or "MINOR/MAJOR/GRAND
  GIFT" (as `CardStats` reads a creature's), else up to three first lines all in capitals (Deck of Endless
  Treasure) or all in title case: at most five words, each capitalized with a lowercase letter or a joining
  word, no sentence punctuation (the Guns and Gears decks). Names with "instructions", "deck" or "product
  identity" are skipped. An item becomes an `ExtractedPawn` of medium size with no traits and the
  `.item(imageIndex:)` shape, printed as `ArtKind.item`; `ArtEntry.isItem` and `LibraryArt.isItem` mark it, and
  `ArtMerger` merges items only with items. `PawnExtractor.version` 3 rereads PDFs read before item decks.
- `Figure` (in Extraction) is one image as its page draws it: the image with its soft mask, and its opaque
  bounds in page space, found in a bitmap at most 512 px across (alpha above 24). `pixelArea` is those bounds in
  the image's own pixels. `palette()` counts the opaque pixels of the figure drawn 64 × 64 into 64 colors (four
  levels of red, green and blue); `paletteDistance` is 1 minus the Bhattacharyya coefficient. In the Bestiary,
  the same painting however cropped measured at most 0.013 and different paintings of the same creature 0.027
  or more, so 0.02 is the same painting. Thumbnails (16 × 24) cannot tell these apart, since a crop moves the
  figure in its frame, and Vision's feature prints rate young and adult dragons closer than one painting's crops.

## Changes from Pawn Shop
The extraction and Battle Cards code moved from Pawn Shop (`PawnShopCore/Extraction` and `Cards`) unchanged in
behavior, with these changes for sharing:
- `PDFKitLabelReader` reads label font sizes through Core Text (`CTFontGetSize`) instead of AppKit's `NSFont`, so
  the module builds for iPadOS, where PDFKit's font attributes are `UIFont`s; both are `CTFont`s.
- `Figure`, `ImagePlacement`, `PageScanner.images(on:)` and `EmbeddedImage.maskedImage(of:)` are public, so that
  Pawn Shop's library can find a pawn's figure in a kept PDF and compare paintings (`palette`, `paletteDistance`,
  `isSamePainting`); they move behind the art library (R2) when it comes.
- `ProductTitle.fromFileName(_:)` turns a download's file name into a product title; Pawn Shop's `PawnSource` and
  `CardDeck.title` use it.

## Art library (`ArtExtraction/Library`)
A smaller store than Pawn Shop's `PawnLibrary`, which keeps its own for printing, custom pawns and tagging; both
build on the same extraction.
- Stored in the app's folder: `art-library.json` (`StoredArtLibrary`: sources, entries and watched folders, with a
  version number), kept PDFs in `Sources/<sha256>.pdf`, tokens' art in `Tokens/<uuid>.png`. 74 PDFs (every pawn,
  token and Battle Cards PDF Scrollkeeper holds) give 9,434 entries in an 11 MB file.
- `ArtSource`: SHA-256 id, title, `GameSystem` (from the title), `SourceLocation` (`.kept`; `.referenced` by a
  `FileReference`; or `.inFolder`, a watched folder's reference and the path inside it, since on the iPad access to
  a file found in a chosen folder comes from the folder), byte count, reader version and the count of art found.
- `FileReference` holds a bookmark: security-scoped on the iPad and in sandboxed Mac apps, plain otherwise (the
  scoped one can't be made outside the sandbox). `withAccess` resolves it, starts access, and checks the file
  can be read. `status(of:)` is `.missing` when the file can't be reached, checked once per source until
  `refreshStatuses()`; a file that returns is available again.
- `ArtEntry`: id, name, game, size, traits, fingerprint, `prints` and a `palette` measured when needed. Each
  `ArtPrint` is where one product prints it: source, `ArtKind` (`.figure` for a card's creature or an outline-less
  pawn, `.pawn`, `.token`), face, image index (figures) or token picture file, and copies. Figures come first, the
  sharpest pictures, then the order products were added.
- `prepare(_:)` hashes and extracts off the main thread; `commit(_:location:)` adds the source and merges with
  `ArtMerger`: unnamed art is counted and left out; art with the same name (ignoring case and accents) and game is
  the same painting when the fingerprints match, or, when either is a figure, when the figures' palettes are within
  `Figure.samePaintingDistance`. A pawn's print sets the size. A source read by an older reader is removed and read
  afresh (the library holds no edits of the user's to keep).
- `watch(_:)` remembers a folder; `addNewFiles(progress:)` adds, by `.inFolder` reference, the PDFs
  `ProductScanner.artPDFs(in:)` finds there (names mentioning pawns or tokens, and each Battle Cards deck once as its
  art PDF) that `contains(_:)` doesn't recognize by place and size or contents. 74 PDFs take about two minutes on a
  Mac (release build).
- `picture(of:maxPixels:)` draws the first print that can be drawn: a token's kept picture, or the figure read from
  the PDF (a figure's picture by its index, or the largest picture inside a pawn's outline) turned upright with
  `Figure.draw(in:rotation:)` on a transparent bitmap.

## Creature art store (`CreatureArt`)
Moved from Combat Pad. `CreatureArtStore` owns an `ArtLibrary` in the folder the app gives it.
`importFolder(_:progress:)` watches a folder and adds its new PDFs by reference; `addNewFiles` does so for the
watched folders (at launch); `addFiles(_:progress:)` keeps copies of chosen PDFs; each returns an
`ArtImportSummary` with a message. `catalog()` refreshes the PDFs' statuses and returns `LibraryArt` for each entry
(remastered when a printing product's title names one of `remasteredProducts`: Monster Core, NPC Core, Alien Core,
Howl of the Wild, Rage of Elements) and an `ArtSourceSummary` for each PDF. `picture(id:maxPixels:)` draws and
caches.

## Creatures (`Bestiary`)
Moved from Combat Pad's `CombatPadKit`: `Creature` and its parts, `BestiaryStore` (the index, packs loaded a pack
at a time, conditions, the glossary and `art-overrides.json`), `StatBlockPresenter` (templates and conditions
applied), the rules the cards need (`CreatureTemplate`, `AppliedCondition`, `ConditionEffects`, `Modifiers`), rules
text, `PlayerDetails` (a linked PC's sheet shown as a creature), Pluck stat blocks and `LibraryArtMatcher` (art
from the art library matched to creatures by name, and with `art(forItemNamed:game:)` to items: by name, then
without grade words, potency runes and numbers; see Combat Pad's spec). Encounter budgets, challenge points and
everything about campaigns and fights stay in Combat Pad.

## Importing creatures (`CreatureImport`)
1. **Pack discovery.** Read `system.pf2e.json` and `system.sf2e.json` for the Actor packs. Scan
   `packs/<system>/<pack>/**/*.json`, keeping `type == "npc"` and complex `hazard` documents.
2. **Normalization.** Each document becomes a `Creature` with the key `<game>.<pack>.<_id>`. Strikes
   come from `melee` items, abilities from `action` items, spells are grouped by `spellcastingEntry`,
   and lore comes from `lore` items.
3. **Rules text.** HTML and Foundry enrichers become `RulesText` runs. `@Check` and `@Damage` stay
   structured so templates and conditions can adjust them. `@UUID` becomes its label, `@Localize` is
   resolved from the lang JSON, and `@Template` becomes prose.
   A `@UUID` to an Item in a compendium pack becomes a `{{link:<id>|<label>}}` run instead, where the glossary
   ID is `<system>.<pack>.<_id>` (links by name are resolved to the `_id`). Links into effect packs stay labels.
4. **Conditions.** The condition packs go to `conditions.json`. sf2e gets the pf2e conditions plus its
   own.
5. **Art overrides.** `art-overrides.json` (creature name → the name its art has in a PDF), when present, is
   copied to `Generated/Bestiary/art-overrides.json` for matching art on the device (below). The import
   handles no art itself.
6. **Glossary.** `CompendiumIndex` reads the Item packs of both systems (an Item pack is indexed on first
   use) and records every glossary ID the import links to. Each creature gets a `LinkTable` from
   `<kind>:<shown text>` to a glossary ID: spells and items by their compendium source (or, without one, their
   embedded copy, `<creature key>.<item _id>`), Strike effects by the creature's own action or the ability
   glossary, and traits as `trait.<game>.<slug>`. `GlossaryBuilder` then turns the linked documents into
   `GlossaryEntry` values (name, category such as "Spell 3", traits and their links, rules text, with spell
   cast, range, area, targets, defense and duration lines first), follows their links one more level, and
   stops: everything a card links to, and everything those entries link to, is in the glossary. Trait text
   comes from `traitDescriptions` in the system's `src/scripts/config/traits.ts`, else
   `PF2E.TraitDescription<Slug>`, dropping a trailing `-value` (reach-10, deadly-d10); Starfinder prefers
   `sf2e-overrides-en.json`.
   **Player compendium.** For PC cards, `PlayerCompendium` also links every document in the player-facing
   Item packs of both systems (spells, feats, class features, actions, ancestry features, heritages and
   equipment), so they and the traits they link to are in the glossary. It writes `glossary-index.json`:
   `GlossaryIndex` keys `<game>:<kind>:<normalized name>` (kinds spell, ability, item and trait) to glossary
   IDs. Names are normalized by `GlossaryIndex.normalize` (lowercase, apostrophes dropped, other punctuation
   as spaces), so "Healing Potion, Moderate" and "Healing Potion (Moderate)" meet; on a clash the remastered
   document wins.
7. **Output.** `Generated/Bestiary/index.json` holds a summary of every creature. There is one
   `packs/<game>.<pack>.json` per pack, plus `conditions.json` and `Generated/import-report.md`. Keys and arrays are sorted, so the output is deterministic.

## Battle cards (`BattleCards`)
- Moved from Combat Pad's `CombatPadUI`: `CardContent` (a presenter's stat block as lines), `CardLine` and
  `CardLineView` (segments with links and changed numbers), `TraitChips`, `GlossaryContext` and `GlossaryPopover`
  (links two deep, URLs of the `tabletop-glossary` scheme), `RulesTextLines`, the player-character lines, and
  `Fonts`/`FontName` (Roboto and the action glyphs, registered from TrueType, OpenType or the pf2e repository's
  WOFF2 files, which Core Text reads directly). The Paizo-styled fronts and backs
  were not moved.
- `BattleCard(creature:template:conditions:textSize:scrolls:)` presents the creature and draws
  `PathfinderCardFront` or `StarfinderCardFront`.
  `CardBack(name:game:traits:art:)` draws `PathfinderCardBack` or `StarfinderCardBack` at a 0.7 aspect ratio
  around the art view the app passes.
- `CardArtPieces` reads `<name>.png` from the app's folder (the `cardArt` environment value) and returns nil for a
  missing piece; each view draws a gradient, a stroke or a shape instead. `manifest` lists the 20 pieces and
  their paths in the packs: Fantasy GUI (parchment `bg_01`, frames `slot_03`/`slot_04`, ribbon `text_bg_03`), Heroic
  UI (rule `el_28_01`, elite frame `el_29`, drawn at a third of its size so its corners stay small), Shields Badges
  (`ShieldsBadges_04_a`), Legendary Battlegrounds (`bg_01`–`bg_05`) and Space Depot UI (`bg`, `bg_big`, corners
  `frame_01_03`–`06`, `button_01_04`, `ava_04_04`). Frames are stretched by cap insets of 60 points.
- `CardBackdrop(traits:)` picks the landscape: the first of undead/spirit/ghost/incorporeal (ruins), fiend/fire/
  demon/devil/daemon (lava), cold/ice (snow), earth/dragon/giant (canyon), else meadow. Fantasy Locations' scenes
  are separate sprites placed by their PSDs, so they aren't used.
- `NameRibbon` centers the name at 27% of the ribbon's height, the middle of its banner (rows 0–123 of 225).
  `TerminalPlate` fills an `ElongatedHexagon` (points at half its height) with near-black glass, `Scanlines` every
  3 points, a cyan edge with a glow, and the name in semibold monospaced cyan with two glow shadows and a `_`.
- `CardArtCopier.copy(from:to:)` finds each piece, matching each path part without regard to case, scales any
  over 1,600 pixels down, writes PNGs and returns the missing pieces; the `CardArtImport` executable runs it. The
  pieces take 9.3 MB.

## Test support (`ArtExtractionTestSupport`)
The drawing helpers that Pawn Shop's tests had, made public so that both packages' tests use one copy:
`makePDF`, `rawPDF`, `strokeOutline`, `drawText`, `artImage`, `DrawnPawn` and `writePawnPDF`, `DrawnToken` and
`tokenPDF`, `DrawnCard`, `writeCardDeck` and `writeSplitDeck`. `RealPDFs`, which finds `TestData` next to the
package that runs the tests, stays in each package's tests.
