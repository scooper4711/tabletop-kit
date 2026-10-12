# Tabletop Kit

[![CI](https://github.com/scooper4711/tabletop-kit/actions/workflows/ci.yml/badge.svg)](https://github.com/scooper4711/tabletop-kit/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](./LICENSE)

Swift libraries shared by [Pawn Shop](https://github.com/scooper4711/pawn-shop) and the author's other tabletop
apps, for macOS and iPadOS.

- **ArtExtraction** finds the creature art in Pathfinder and Starfinder pawn, token and Battle Cards PDFs that you
  bought, and the item art in item decks (Potions & Talismans, Magic Armaments, Alchemy, Guns, Gears, Relics,
  Deck of Endless Treasure, and Weapons & Armor, sold as pictures): each pawn, token, card creature and item
  with its name (and a creature's size and
  traits), and its picture alone on a transparent background.
- **ArtExtractionTestSupport** draws small test PDFs laid out like Paizo's, for the apps' tests.

It contains no Paizo art or text, and works only with PDFs you supply. Pathfinder and Starfinder are trademarks
of Paizo Inc.; this project is not published, endorsed, or specifically approved by Paizo.

## Use
Add the package in Xcode or `Package.swift`:

```swift
.package(url: "https://github.com/scooper4711/tabletop-kit.git", from: "0.1.0")
```

## Develop
`make test`, `make lint`, `make coverage` (80% of lines and regions) and `make build-ios`. Tests that read real
Paizo PDFs run when a git-ignored `TestData` folder (or link) holds them, and are skipped otherwise. See
`docs/specs/tabletop-kit/` for the requirements and design.
