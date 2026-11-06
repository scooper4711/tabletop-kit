# Contributing to Tabletop Kit

Thank you for helping with Tabletop Kit. It is the Swift package the Tableside Toolkit apps share: the bestiary,
battle cards, creature art and art extraction from Paizo's PDFs. It is part of the
[Tableside Toolkit](https://github.com/scooper4711/scrollkeeper#tableside-toolkit), free tools for Pathfinder and
Starfinder players and GMs, kept by one maintainer in spare time.

## Before you start

- Small fixes can go straight to a pull request.
- For anything bigger (a feature, a change in behavior, a new dependency), open or comment on an issue first, so we
  can agree on the design before you write the code.
- One change per pull request.

## Setting up

You need macOS 26 and Xcode 26 (Swift 6), as CI uses, and [SwiftLint](https://github.com/realm/SwiftLint)
(`brew install swiftlint`).

```sh
git clone https://github.com/scooper4711/tabletop-kit.git
cd tabletop-kit
make build
make test
```

`make build-ios` also builds the package for the iPad. Field Guide, Turnkeeper and Pawn Shop depend on it, so a
change here reaches all three: keep the public API stable, say in the pull request what a change does to it, and
expect a release to follow the merge (the apps pick up new versions by SemVer).

The tests that read Paizo's pawn PDFs read sample pages of them from the private toolkit-artwork repository, in
`test-pdfs/` next to your checkout or wherever `TOOLKIT_TEST_PDFS` points. Without them those tests are skipped; CI
runs them. If your change affects art extraction, say so, and the maintainer will run them too.

## Making a change

### Code

Match the code around your change, and:

- **Functions** do one thing: under 20 lines ideally, 50 at most, with two arguments or fewer (four or more become a
  parameter object). No Boolean flag arguments: write two functions.
- **Files** under 300 lines (500 at most); lines under 120 characters.
- **Complexity** under 5 where you can, never 15 or more. Say why next to any SwiftLint rule you silence.
- **Empty values over `nil`**: return an empty array or string, or an `Optional` the caller must handle.
- **Errors** say what was being done and what went wrong.
- **Names** are whole words, one word per concept. Public before private, callers before the functions they call,
  positive conditions (`isValid`, not `!isInvalid`).
- **Repetition**: factor code out the third time it appears, when the copies mean the same thing.
- **No unrelated reformatting**; leave the code you touch cleaner than you found it.
- **Doc comments** say what something is for and why it works as it does.
- **American English** everywhere, interface text and commit messages included.

`make lint` (SwiftLint, strict) must be clean.

### Tests

- New behavior gets tests; a bug fix gets a test that would have caught it.
- Test code meets the same standard, apart from length. Use the shared helpers and fixtures.
- `make coverage` fails below 80% of the lines or regions of every library target (the `TestSupport` targets aside).
  Code you add or change should be at 80% or more too. SwiftUI views count too, so keep logic in types that can be
  tested without them.
- **Never commit with a failing test.** A failing test is a signal that something another feature relies on has
  changed: find out why, rather than skipping or loosening it.

### Specs

Features are described in `docs/specs/<feature>/`: `requirements.md` (numbered, such as R4.3) and `design.md`.
Update both in the same pull request as the behavior.

### Game rules

For a change to the rules, cite the rule (book and page, or an [Archives of Nethys](https://2e.aonprd.com) link).
Remastered rules come first.

### Paizo's and others' material

The repository holds no Paizo text, art or PDFs. Don't commit any, nor screenshots of them, nor other publishers'
art (such as Rexard's packs) or fonts whose licenses don't allow it.

Creatures and the glossary come from the [Foundry VTT pf2e system](https://github.com/foundryvtt/pf2e) under the ORC
License and OGL; art is read from the user's own PDFs and Rexard packs. Tests draw small PDFs laid out like Paizo's
(`ArtExtractionTestSupport`), or read the private sample pages described above.

## Commits

- Each commit is one coherent step that builds and passes its tests.
- Start the message with a type (`feat`, `fix`, `refactor`, `docs`, `test`, `style`, `chore`, or `chore(ci)` for
  CI), then a capitalized summary of what changes for the user, with no period:
  `feat: Roll a group's initiative from one die`. The body says why.
- Leave `CHANGELOG.md` alone: it is written at release.

## Pull requests

1. Branch from `main` and keep up to date with it.
2. Run `make lint` and `make coverage` before you push; CI runs the same. CI on a first pull request from a fork
   waits for the maintainer's approval.
3. Say what changes, why, and how you checked it (tests, what you tried, on which devices). Link the issue, and add
   screenshots for interface changes.

Code written with AI tools is welcome: say so in the pull request, and submit only what you have read, understood
and tested.

## Issues

[Open an issue](https://github.com/scooper4711/tabletop-kit/issues) for a bug or an idea. For a bug, give the
package version and the app you saw it in, the device and system version, and what you did, expected and got. Leave
Paizo content out of screenshots.

## License

Tabletop Kit is under the [MIT License](LICENSE); your contributions are too.
