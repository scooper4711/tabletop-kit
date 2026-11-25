# Source attribution: requirements

Chronicle Keeper, Pawn Shop, Field Guide and Turnkeeper ship game text imported from pf2e and sf2e. The ORC License
asks for an attribution notice naming the Licensed Material used, and OGL 1.0a Section 15 for the copyright notice of
every source. The apps used to bundle pf2e's own notice files, which name only some of the books and no Starfinder
book. This spec builds the notices from the sources each import actually used.

Issue: tabletop-kit#94. The apps adopt it in chronicle-keeper#31, pawn-shop#93, field-guide#97 and turnkeeper#118.

## R1 Notices
- R1.1 An import reports every source title it used, with a count of records per title.
- R1.2 It writes `ORC License.md` (the ORC notice, an attribution notice listing every ORC source used, the reserved
  material and expressly designated material sections) and `Open Game License.md` (the OGL 1.0a text and a
  Section 15 with the OGL's own notice and every OGL source used).
- R1.3 Each source used appears in exactly one notice; a notice no source needs isn't written, and a stale one is
  removed.
- R1.4 An OGL source's own Section 15 entries for earlier works (such as Tome of Horrors creatures) are repeated,
  once each.
- R1.5 Neither file starts with pf2e's stray `/static/licenses/…` line.
- R1.6 The Community Use notice stays with AppNotices.

## R2 Catalog
- R2.1 The source books live in a catalog in tabletop-kit, kept in git and edited by hand: title, other titles the
  data uses, game, license (ORC, OGL or neither), and either the book's notice quoted whole or its year, publisher
  and credits.
- R2.2 Titles match whatever their case, spacing, punctuation, accents or "&".
- R2.3 Every complete entry says where its facts came from. Facts not taken from the book's own notice are marked
  unverified until checked.
- R2.4 Attribution facts are never generated: they come from the book's notice, pf2e's notices, or the Paizo
  product page (as Scrollkeeper reads it).

## R3 Gaps
- R3.1 An import fails, listing every problem source at once, when a source isn't in the catalog, lacks facts, or is
  covered by neither license. Unknown sources never ship silently.
- R3.2 `docs/source-attribution-gaps.md` lists what's missing and which apps use it, generated from the catalog and
  each app's source list (`docs/source-usage/<app>.txt`), and a test keeps it current.
