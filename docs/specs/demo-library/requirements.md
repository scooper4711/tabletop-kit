# Demo Library: requirements

Scrollkeeper's demo library lets App Review, and anyone without Paizo's books, try every Tableside Toolkit app and
how they work together. This library writes the PDFs and covers the demo serves. Scrollkeeper's
`docs/specs/library-manager` (13) says how the demo uses them.

## R1 What it writes
- R1.1 Text is lorem ipsum under real game terms: creature names, traits, levels, so the apps can match art and
  lore to the bestiary. No Paizo text is used.
- R1.2 Art is either drawn by the tool (creature silhouettes, maps) or from Paizo's Community Use Package
  (the Iconics, religious and faction symbols), which the Community Use Policy allows in a free app. No other
  Paizo art: none from books, pawn sets, Battle Cards or maps.
- R1.3 Each PDF ends with a page saying it is a demo with placeholder text, and Paizo's Community Use notice.
  Pawns carry "© 2026 Tableside Toolkit demo" where Paizo's carry their copyright: nothing claims to be Paizo's.
- R1.4 The same input writes the same files, so regenerating them changes nothing unless the tool changed.
- R1.5 Without the Community Use Package folder (on CI, in tests) the tool draws stand-ins for its art.

## R2 The products
- R2.1 **A pawn collection** of monsters: outlined pawns, each with its name printed inside, front and mirrored
  back, as Paizo's pawn boxes print them.
- R2.2 **A hero pawn collection**: the Iconics as pawns printed without outlines, named along their feet.
- R2.3 **A token set**: round creature tokens with their names.
- R2.4 **A Battle Cards deck**: monsters' art sides and stat sides.
- R2.5 **Two battle maps**, a forest and a starship deck, drawn on a regular one-inch grid.
- R2.6 **An adventure and a society scenario**: headings, paragraphs, pictures (Iconics), a creature's stat block
  and a handout.
- R2.7 **A rulebook** with chapters, a picture and a page of deities' religious symbols.

## R3 Working with the apps
- R3.1 Pawn Shop's, Turnkeeper's and Field Guide's art import (`ProductScanner`, the pawn, token and card
  extraction) finds every pawn, token and card, with its name.
- R3.2 Mapsmith finds each map and its grid.
- R3.3 Pluck extracts the adventures' pictures and finds the stat block.
