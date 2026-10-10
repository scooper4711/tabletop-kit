# Tabletop Kit: design

A Swift package (`Package.swift`, macOS 15 and iOS 18) of libraries the apps depend on by URL and version tag.
Each library is unit tested on test PDFs drawn by `ArtExtractionTestSupport`; CI also builds for the iOS
simulator. Pawn Shop's spec describes the measurements of Paizo's PDFs these readers rely on.

## Modules
| Module | Contents |
|---|---|
| `ArtExtraction` | PDF scanning, pawns, tokens, Battle Cards, figures, fingerprints; later the art library |
| `ArtExtractionTestSupport` | Test PDF drawing (`DrawnPawn`, `DrawnToken`, `DrawnCard`, `makePDF`, …), published for the apps' tests |
| `Bestiary`, `BestiaryImport`, `BattleCards` | Planned (R4), moved from Combat Pad |

## Extraction (`ArtExtraction/Extraction`)
Moved from Pawn Shop (`PawnShopCore/Extraction`) unchanged in behavior; its design is described in Pawn Shop's
spec. Changes for sharing:
- `PDFKitLabelReader` reads label font sizes through Core Text (`CTFontGetSize`) instead of AppKit's `NSFont`, so
  the module builds for iPadOS, where PDFKit's font attributes are `UIFont`s; both are `CTFont`s.
- `Figure`, `ImagePlacement`, `PageScanner.images(on:)` and `EmbeddedImage.maskedImage(of:)` are public, so that
  Pawn Shop's library can find a pawn's figure in a kept PDF and compare paintings (`palette`, `paletteDistance`,
  `isSamePainting`); they move behind the art library (R2) when it comes.
- `ProductTitle.fromFileName(_:)` turns a download's file name into a product title; Pawn Shop's `PawnSource` and
  `CardDeck.title` use it.

## Battle Cards (`ArtExtraction/Cards`)
Moved from Pawn Shop (`PawnShopCore/Cards`) unchanged: `CardDeck`, `CardPairing`, `CardExtractor`, `CardStats`.

## Test support (`ArtExtractionTestSupport`)
The drawing helpers that Pawn Shop's tests had, made public so that both packages' tests use one copy:
`makePDF`, `rawPDF`, `strokeOutline`, `drawText`, `artImage`, `DrawnPawn` and `writePawnPDF`, `DrawnToken` and
`tokenPDF`, `DrawnCard`, `writeCardDeck` and `writeSplitDeck`. `RealPDFs`, which finds `TestData` next to the
package that runs the tests, stays in each package's tests.
