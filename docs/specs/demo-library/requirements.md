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
- R1.3 Each PDF ends with a page saying it is from the demo library and what it holds, then Paizo's Community Use
  notice. Only the prose files (rulebook, adventure, scenario) say their text is lorem ipsum; the monster pawns,
  tokens and Battle Cards say their art was drawn for the demo under real creatures' names, the maps that they
  were drawn for the demo, and the hero pawns that the Iconics come from Paizo's Community Use Package.
- R1.4 The same input writes the same files, so regenerating them changes nothing unless the tool changed.
- R1.5 Without the Community Use Package folder (on CI, in tests) the tool draws stand-ins for its art.

## R2 The products
- R2.1 **A pawn collection** of monsters: outlined pawns at Paizo's outline sizes for their size traits, each with
  its name printed inside, front and mirrored back, as Paizo's pawn boxes print them.
- R2.2 **A hero pawn collection**: the Iconics as pawns printed without outlines, named along their feet.
- R2.3 **A token set**: round creature tokens with their names.
- R2.4 **A Battle Cards deck**: monsters' art sides and stat sides.
- R2.5 **Two battle maps**, a forest and a starship deck, drawn on a regular one-inch grid.
- R2.6 **An adventure and a society scenario**: headings, paragraphs, pictures (Iconics), a creature's stat block
  and a handout. The adventure's handout is a torn-off piece of the forest map with a trail to an X, not an Iconic.
- R2.8 The monsters (pawns, tokens, Battle Cards) are twelve, and include Aapoph Serpentfolk, which is near the top
  of Field Guide's Bestiary list, so a reviewer sees demo art on its first screen.
- R2.7 **A rulebook** with chapters, a picture and a page of deities' religious symbols.

## R3 Working with the apps
- R3.1 Pawn Shop's, Turnkeeper's and Field Guide's art import (`ProductScanner`, the pawn, token and card
  extraction) finds every pawn, token and card, with its name.
- R3.2 Mapsmith finds each map and its grid.
- R3.3 Pluck extracts the adventures' pictures and finds the stat block.
