# Demo Library: design

- **Targets.** `DemoLibrary`, a library, writes everything; `DemoLibraryTool`, an executable,
  `swift run DemoLibraryTool <output folder> [--art <community-use-artwork folder>]`. Scrollkeeper's
  `make demo-pdfs` runs it from a checkout beside Scrollkeeper and commits the output.
- **Formats.** Tokens and cards are drawn with `ArtExtractionTestSupport`'s `DrawnToken` and `DrawnCard`, the
  writers the extraction's tests use; pawns with `DemoPawn` (at `PawnSize`'s outline for the monster's size
  trait, so they are read by their outlines) and `DemoFigurePawn`, neither with a copyright line, which no pawn
  needs. What the art import needs, found by `DemoLibraryTests`: outlines at Paizo's sizes (larger ones were read
  only as figures), card names in capitals as Battle Cards print them, and the art and stat sides in pairs. Card pages are built from plain closures: mixing
  `DrawnCard`'s `@Sendable` methods into the page list fails at run time.
- **Art.** `DemoArt` loads the Iconics (`Community Use Package- Iconics/*.png`, transparent) and the religious and
  faction symbols from `--art`; without it, `creatureArt(variant:)` and drawn shapes stand in. Pictures are
  scaled down so the files stay small.
- **Text.** `Lorem` makes paragraphs from a fixed seed. Prose pages are drawn with Core Text: headings, body,
  pictures, and a stat block laid out as Paizo's are (name and level line, traits, then labeled lines).
- **Maps.** A drawn image of 8 × 10 one-inch squares at 150 pixels an inch, with dark grid lines, embedded as one
  picture per page, as map packs print them.
- **File names.** As Scrollkeeper's demo editions name them (`DemoLibrary.files`), so its catalog and this tool
  agree.
- **Covers** are not written here: Scrollkeeper's demo draws a cover for each title when asked, so this tool
  needn't know its catalog.
- **Tests.** Write into a temporary folder without `--art`; check `ProductScanner` lists the art products under
  the names Scrollkeeper gives them, `ArtLibrary` imports every monster from the pawns, tokens and cards and every
  hero, and every PDF ends with the notice. Checked once by hand with the Community Use art (2026-11-09): the
  heroes import with the Iconics; Mapsmith finds each map and a grid of 150 pixels a square at 150 dpi; Pluck
  finds the Goblin Warrior and Skeleton Guard stat blocks and every picture.
