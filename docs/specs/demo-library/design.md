# Demo Library: design

- **Targets.** `DemoLibrary`, a library, writes everything; `DemoLibraryTool`, an executable,
  `swift run DemoLibraryTool <output folder> [--art <community-use-artwork folder>]`. Scrollkeeper's
  `make demo-pdfs` runs it from a checkout beside Scrollkeeper and commits the output.
- **Formats.** The pawn, token and card pages are drawn with `ArtExtractionTestSupport`'s writers (`pawnPDF`,
  `figurePawnPDF`, `tokenPDF`, `cardDeckPDF`), the same ones the extraction's tests are written against, so a
  change to either is caught by `DemoLibraryTests`.
- **Art.** `DemoArt` loads the Iconics (`Community Use Package- Iconics/*.png`, transparent) and the religious and
  faction symbols from `--art`; without it, `creatureArt(variant:)` and drawn shapes stand in. Pictures are
  scaled down so the files stay small.
- **Text.** `Lorem` makes paragraphs from a fixed seed. Prose pages are drawn with Core Text: headings, body,
  pictures, and a stat block laid out as Paizo's are (name and level line, traits, then labeled lines).
- **Maps.** A drawn image of 8 × 10 one-inch squares at 150 pixels an inch, with dark grid lines, embedded as one
  picture per page, as map packs print them.
- **Covers.** A JPEG per demo title: its name over a color band, with an Iconic or symbol where one fits.
- **File names.** As Scrollkeeper's demo editions name them (`DemoLibrary.files`), so its catalog and this tool
  agree.
- **Tests.** Write into a temporary folder without `--art`; check `ProductScanner` lists the art products, the
  pawn, token and card extraction find every one by name, the maps' pages hold a single large picture, and every
  PDF ends with the notice.
