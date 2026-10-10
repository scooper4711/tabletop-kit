# Tabletop Kit: design

A Swift package (`Package.swift`, macOS 15 and iOS 18) of libraries the apps depend on by URL and version tag.
Each library is unit tested on test PDFs drawn by `ArtExtractionTestSupport`; CI also builds for the iOS
simulator.

## Modules
| Module | Contents |
|---|---|
| `ArtExtraction` | PDF scanning, pawns, tokens, Battle Cards, figures, fingerprints; later the art library |
| `ArtExtractionTestSupport` | Test PDF drawing (`DrawnPawn`, `DrawnToken`, `DrawnCard`, `makePDF`, …), published for the apps' tests |
| `Bestiary`, `BestiaryImport`, `BattleCards` | Planned (R4), moved from Combat Pad |

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

## Battle Cards (`ArtExtraction/Cards`)
- `CardDeck.containing(_:)` takes a PDF whose name, or one of its two enclosing folders, says "Battle Cards".
  A file naming a side (FRONT, FRONTS, BACK, BACKS) is paired with the file beside it whose name differs only
  in naming the other side; the BACKS file is the deck's `artFile`, which the library keeps. The title comes
  from the nearest enclosing folder naming the deck and starting with Pathfinder or Starfinder (as Scrollkeeper
  files them), without "(Download)" and "- PDF(s)", or else from the file name.
- `CardPairing` pairs pages: page *n* of both PDFs; or in one PDF, each art page with the page after it when
  such pairs cover over a third of the pages, else the *k*th page of each run of other pages with the *k*th of
  the run of art pages after it. An art page prints under 80 characters and no stat block: the NPC deck's
  combined PDF credits the illustrator on each art page.
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

## Test support (`ArtExtractionTestSupport`)
The drawing helpers that Pawn Shop's tests had, made public so that both packages' tests use one copy:
`makePDF`, `rawPDF`, `strokeOutline`, `drawText`, `artImage`, `DrawnPawn` and `writePawnPDF`, `DrawnToken` and
`tokenPDF`, `DrawnCard`, `writeCardDeck` and `writeSplitDeck`. `RealPDFs`, which finds `TestData` next to the
package that runs the tests, stays in each package's tests.
