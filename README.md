# Tabletop Kit

[![CI](https://github.com/scooper4711/tabletop-kit/actions/workflows/ci.yml/badge.svg)](https://github.com/scooper4711/tabletop-kit/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](./LICENSE)

Swift libraries shared by three of the [Tableside Toolkit](#the-apps) apps,
[Pawn Shop](https://github.com/scooper4711/pawn-shop), [Turnkeeper](https://github.com/scooper4711/turnkeeper) and
[Field Guide](https://github.com/scooper4711/field-guide), for macOS, iPadOS and iOS.

- **ArtExtraction** finds the creature art in Pathfinder and Starfinder pawn, token and Battle Cards PDFs that you
  bought, and the item art in item decks (Potions & Talismans, Magic Armaments, Alchemy, Guns, Gears, Relics,
  Deck of Endless Treasure, and Weapons & Armor, sold as pictures): each pawn, token, card creature and item
  with its name (and a creature's size and traits), and its picture alone on a transparent background.
- **ArtExtractionTestSupport** draws small test PDFs laid out like Paizo's, for the apps' tests.
- **Bestiary** and **CreatureImport**: the creature model, stat-block presentation and rules that Turnkeeper and
  Field Guide share, imported from the pf2e system for Foundry VTT (every NPC and complex hazard, the conditions,
  and a glossary of what the creatures link to).
- **BattleCards** draws a creature's battle card, front and back, with its template and conditions applied, in a
  look of its own; the card art comes from your own Rexard packs.
- **CreatureArt** keeps the art library that Turnkeeper and Field Guide read from your PDFs.
- **SharedLibraries** keeps the art library and creature library the three apps share in the toolkit's App Group:
  an SQLite database that two apps can write at once, telling the others of each change.
- **TablesideSync** keeps those libraries the same on your devices, through your private iCloud database.
- **AppNotices** is the About screen each app shows, with the notices Paizo's Community Use Policy and
  Compatibility License require.
- **SourceAttribution** writes the ORC and OGL notices for the game text an app imports, naming every source book
  it comes from, and stops the import when a book can't be attributed. Its catalog of books is
  `Sources/SourceAttribution/Resources/source-catalog.json`; what's still missing from it is in
  [docs/source-attribution-gaps.md](docs/source-attribution-gaps.md) (`make attribution-gaps` regenerates it).

It contains no Paizo art or text, and works only with PDFs you supply. Pathfinder and Starfinder are trademarks
of Paizo Inc.

Tabletop Kit uses trademarks and/or copyrights owned by Paizo Inc., used under Paizo's Community Use Policy
([paizo.com/licenses/communityuse](https://paizo.com/licenses/communityuse)). We are expressly prohibited from
charging you to use or access this content. Tabletop Kit is not published, endorsed, or specifically approved by
Paizo. For more information about Paizo Inc. and Paizo products, visit [paizo.com](https://paizo.com).

## Use
Add the package in Xcode or `Package.swift`:

```swift
.package(url: "https://github.com/scooper4711/tabletop-kit.git", from: "0.13.0")
```

## The apps

The Tableside Toolkit is a set of free apps for the Mac, iPad and iPhone for running Pathfinder and Starfinder games
in person. Like any good toolkit, each one grants a +1 item bonus to game prep.

- [Scrollkeeper](https://github.com/scooper4711/scrollkeeper) keeps your Paizo library in order and downloads your
  purchases.
- [Pluck](https://github.com/scooper4711/pluck) gets the art, text and stat blocks out of a PDF.
- [Pawn Shop](https://github.com/scooper4711/pawn-shop) prints just the pawns you need, single-sided, from your
  pawn PDFs.
- [Mapsmith](https://github.com/scooper4711/mapsmith) prints battle maps at true scale on ordinary paper.
- [Turnkeeper](https://github.com/scooper4711/turnkeeper) builds encounters and runs initiative at the table, with
  the battle card of whoever's turn it is.
- [Field Guide](https://github.com/scooper4711/field-guide) carries the Pathfinder and Starfinder compendium,
  offline.
- [Chronicle Keeper](https://github.com/scooper4711/chronicle-keeper) keeps a record of your Organized Play
  characters: their sessions, XP, level, reputation and Fame.

## Develop
`make test`, `make lint`, `make coverage` (80% of lines and regions) and `make build-ios`. Tests that read real
Paizo PDFs run when a git-ignored `TestData` folder (or link) holds them, and are skipped otherwise. See
`docs/specs/tabletop-kit/` for the requirements and design.
