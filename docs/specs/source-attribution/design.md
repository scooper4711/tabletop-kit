# Source attribution: design

## Module `SourceAttribution` (Foundation only)
- `CatalogEntry`: one book. `notice` quotes the book's notice; otherwise `noticeLine` builds
  `Title © Year, Publisher; Role: A, B, and C.` from `year`, `publisher` and `credits`. `missingFacts` names what a
  gap lacks. `includes` holds earlier works' notices for the OGL (R1.4). `verified` is false for unchecked facts.
- `SourceCatalog`: the bundled `Resources/source-catalog.json`, looked up by `SourceTitle.key` over titles and
  aliases; refuses a title listed twice.
- `SourceTally`: titles and counts, read and written as `title<TAB>count` lines.
- `NoticeWriter`: fills `Resources/orc-notice.md` and `Resources/open-game-license.md` (taken from pf2e's files,
  without their notices) and writes them to a folder; throws `AttributionError.unattributedSources` with every
  problem (R3.1).
- `GapReport`: the markdown of R3.2.

## Tool `SourceAttributionTool`
- `write SOURCES OUTPUT_FOLDER` for the importers that are shell scripts.
- `gaps USAGE_FOLDER REPORT` (`make attribution-gaps`).

## Filling the catalog
`scripts/seed-source-catalog.py` adds to the catalog without changing complete entries:
- `--licenses`: every notice in pf2e's ORC and OGL files, quoted, with the other publishers' lines of an OGL group as
  that group's `includes`.
- `--items`: an app's records; each new source becomes a gap.
- Adventure Path volumes the data titles "Pathfinder #N: …" become aliases of "Pathfinder Adventure Path #N: …".
- `--alias "DATA=>NOTICE"`: other titles, linked by hand.
- `--books`: Scrollkeeper's download folder. An ORC book prints the notice it wants to be credited with ("please
  credit us in your product as follows: …"); a gap whose book is there gets that notice, quoted and verified. A
  notice cut short by a column or page break is left for hand filling.
- `--scrollkeeper`: Scrollkeeper's scraped `metadata.json` (account data, kept in `tmp/`) fills the year and authors
  of the gaps left, unverified, and the ORC license for sf2e and for books from 2024 on (Paizo's books are ORC from
  the Remaster).
