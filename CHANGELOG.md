# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.26.0] - 2026-11-27

### Added
- Write a pawn sheet request as a sheet file

### Changed
- Specify the pawn sheet request as a sheet file

[1.26.0]: https://github.com/scooper4711/tabletop-kit/releases/tag/v1.26.0

## [1.25.0] - 2026-11-26

### Added
- Add PageSetupArchive and PageSetupStore
- Give the pawn sheet request a format version

### Changed
- Specify the shared Mac page setup
- Specify the pawn sheet request's format version

[1.25.0]: https://github.com/scooper4711/tabletop-kit/releases/tag/v1.25.0

## [1.24.0] - 2026-11-26

### Added
- Save a creature's name with its pasted art

### Changed
- Specify the name saved with pasted art

[1.24.0]: https://github.com/scooper4711/tabletop-kit/releases/tag/v1.24.0

## [1.23.0] - 2026-11-26

### Added
- Add the pawn sheet request
- Show what the notices print for each entry to check

### Fixed
- Give package resource bundles the app's team
- Mark Dark Archive (Remastered) verified
- Name the product in Starfinder Player Core's reference
- Quote the two player's guides' own notices

### Changed
- Specify the pawn sheet request

[1.23.0]: https://github.com/scooper4711/tabletop-kit/releases/tag/v1.23.0

## [1.22.0] - 2026-11-26

### Added
- Attribute Chronicle Keeper's last 5 sources
- Attribute 9 more sources from product pages
- Attribute 16 more of Chronicle Keeper's sources
- Find more books' notices when seeding the catalog
- Credit collections such as the Pathfinder Blog by their parts
- Attribute 43 more of Chronicle Keeper's sources
- Fill catalog gaps from the books' own notices

### Fixed
- Wait for GitHub to show a new run before following it

### Changed
- Keep the attribution code within 120 columns

[1.22.0]: https://github.com/scooper4711/tabletop-kit/releases/tag/v1.22.0

## [1.21.0] - 2026-11-26

### Added
- List the attribution gaps and add the command-line tool
- Write the ORC and OGL notices for the sources used
- Add the source catalog for attribution notices

### Changed
- Specify source attribution

[1.21.0]: https://github.com/scooper4711/tabletop-kit/releases/tag/v1.21.0

## [1.20.0] - 2026-11-26

### Added
- Add the release-train command
- Add the Public beta promotion script
- Add the train's git, GitHub and store layers
- Guard store builds by the train's branch and tag

### Changed
- Specify the release train

[1.20.0]: https://github.com/scooper4711/tabletop-kit/releases/tag/v1.20.0

## [1.19.2] - 2026-11-25

### Fixed
- Pair old prints by name in image decks only
- Key image-deck items by their back files alone

[1.19.2]: https://github.com/scooper4711/tabletop-kit/releases/tag/v1.19.2

## [1.19.1] - 2026-11-24

### Fixed
- Harden the manual iPad signing from review
- Sign the iPad archive without making a certificate

### Changed
- Specify manual signing for the iPad archive

[1.19.1]: https://github.com/scooper4711/tabletop-kit/releases/tag/v1.19.1

## [1.19.0] - 2026-11-24

### Added
- Save art pictures at up to 2,048 pixels

[1.19.0]: https://github.com/scooper4711/tabletop-kit/releases/tag/v1.19.0

## [1.18.0] - 2026-11-24

### Added
- Share the sync settings section between the apps

### Changed
- Specify the shared sync settings section

[1.18.0]: https://github.com/scooper4711/tabletop-kit/releases/tag/v1.18.0

## [1.17.0] - 2026-11-24

### Added
- Send library backups elsewhere and leave out PDFs

### Fixed
- Prune only dated backup folders
- Back up Chronicle Keeper's library too

[1.17.0]: https://github.com/scooper4711/tabletop-kit/releases/tag/v1.17.0

## [1.16.0] - 2026-11-24

### Added
- Sync local builds with Development CloudKit
- Add the shared App Store pipeline scripts

### Fixed
- Stop when the profile doesn't allow the iCloud environment

### Changed
- Specify the shared App Store pipeline

[1.16.0]: https://github.com/scooper4711/tabletop-kit/releases/tag/v1.16.0

## [1.15.1] - 2026-11-23

### Fixed
- Count art in iCloud as available

[1.15.1]: https://github.com/scooper4711/tabletop-kit/releases/tag/v1.15.1

## [1.15.0] - 2026-11-23

### Added
- Tag the commit each TestFlight build came from
- Send a platform's review attachment with its push
- Add a script for Mac store screenshots

### Fixed
- Keep sync state apart per CloudKit environment

### Changed
- Specify tagging TestFlight builds
- Specify the review attachment
- Specify the Mac store screenshots

[1.15.0]: https://github.com/scooper4711/tabletop-kit/releases/tag/v1.15.0

## [1.14.0] - 2026-11-22

### Added
- Add store screenshots from the demo libraries

### Fixed
- Report why a store screenshot test failed
- Run deliver in a folder of its own
- Leave a record's screenshots alone when the folder is empty

### Changed
- Specify store screenshots from the demo libraries

[1.14.0]: https://github.com/scooper4711/tabletop-kit/releases/tag/v1.14.0

## [1.13.0] - 2026-11-21

### Added
- Send store listings and TestFlight builds from scripts

### Fixed
- Keep each platform's own listing text
- Stop a backup when macOS keeps a library folder from the terminal

### Changed
- Specify the store listing and TestFlight scripts

[1.13.0]: https://github.com/scooper4711/tabletop-kit/releases/tag/v1.13.0

## [1.12.0] - 2026-11-20

### Added
- Put a custom creature's name and size over its stat block
- Give custom creatures a name, game and size

### Changed
- Warn before Pawn Shop deletes a custom creature
- Specify custom pawns as custom creatures

[1.12.0]: https://github.com/scooper4711/tabletop-kit/releases/tag/v1.12.0

## [1.11.4] - 2026-11-19

### Fixed
- Stop remembering a file from hanging in an unsandboxed process with no desktop session, such as a CI runner

[1.11.4]: https://github.com/scooper4711/tabletop-kit/releases/tag/v1.11.4

## [1.11.3] - 2026-11-18

### Fixed
- Find item cards' names where PDFKit now puts them
- Leave out pawns shown under a cover's title
- Read a simple font's codes as single bytes

[1.11.3]: https://github.com/scooper4711/tabletop-kit/releases/tag/v1.11.3

## [1.11.2] - 2026-11-18

### Fixed
- Leave covers' and ads' pictures out of the pawns

[1.11.2]: https://github.com/scooper4711/tabletop-kit/releases/tag/v1.11.2

## [1.11.1] - 2026-11-18

### Fixed
- Keep pictures a failed fetch can't call unused
- Ask again for a picture that failed to download
- Send everything after a missing zone or a full iCloud
- Keep aside a record in a later format

### Changed
- Say what raising the record format asks of a version
- Start the sync engine without a flag argument

[1.11.1]: https://github.com/scooper4711/tabletop-kit/releases/tag/v1.11.1

## [1.11.0] - 2026-11-18

### Added
- Add iCloud entitlements to Developer ID builds
- Keep the library's pictures in iCloud
- Sync the library's zone through the engine
- Host zone handlers on one sync engine
- Add the TablesideSync target with its record coder

### Fixed
- Tell the library its iCloud account when syncing starts

### Changed
- Cover a reading refused without its asset

[1.11.0]: https://github.com/scooper4711/tabletop-kit/releases/tag/v1.11.0

## [1.10.0] - 2026-11-18

### Added
- Keep the sharper picture when two devices drew different ones
- Keep aside a synced record this version can't read
- Link PDFs other devices read and skip undownloaded files
- Track which pictures to upload, download and keep
- Merge library records from other devices
- Choose which library records to upload
- Add schema version 6 with the time of each edit

### Fixed
- Count no PDF another app is reading
- Tell when no picture could be drawn at all
- Apply a record deleted and saved again in one batch
- Note a picture's size only while the art still names it
- Count no PDF a watched folder only links
- Draw the other pictures when one can't be drawn
- Keep custom art's image when its staged copy is gone
- Keep the sharper picture when a Battle Card is read
- Send nothing back for a PDF this device knows less about
- Keep a row deleted here when its record is fetched again
- Draw a missing picture only under its own print's name
- Draw no more missing pictures than asked for
- Link a synced PDF whichever reader read it
- Keep a picture in use out of the cache's removals
- Settle an alias two devices hold the same way
- Change files only once a synced batch has committed
- Read one cloud record per change, not the whole table

### Changed
- Spell forever as one word and note a limit of settling
- Drop a picture check that never applied
- Correct two statements in the sync design
- Stop checking picture files once the limit is reached
- Share one SHA-256 hex helper
- Add scripts to back up and restore the apps' libraries
- Describe the picture rule and records kept aside
- Share how cloud records are read and stored
- Specify syncing the libraries through iCloud

[1.10.0]: https://github.com/scooper4711/tabletop-kit/releases/tag/v1.10.0

## [1.9.0] - 2026-11-17

### Added
- Merge a Battle Card with a pawn naming more of its family
- Keep tokens' back pictures in the shared library
- Keep art printed without a name in the shared library

### Fixed
- Merge a Battle Card only with the same images or colors
- Keep every product printing one picture under one name
- Keep the note of art a reread leaves without prints

### Changed
- Keep art printed without a name in the shared library

[1.9.0]: https://github.com/scooper4711/tabletop-kit/releases/tag/v1.9.0

## [1.8.1] - 2026-11-17

### Fixed
- Let older apps share a library a newer app changed

[1.8.1]: https://github.com/scooper4711/tabletop-kit/releases/tag/v1.8.1

## [1.8.0] - 2026-11-17

### Added
- Keep notes about art and move in keyed art
- Keep creature art in the shared library

[1.8.0]: https://github.com/scooper4711/tabletop-kit/releases/tag/v1.8.0

## [1.7.0] - 2026-11-17

### Added
- Read PDFs into the shared library with their pictures

[1.7.0]: https://github.com/scooper4711/tabletop-kit/releases/tag/v1.7.0

## [1.6.0] - 2026-11-17

### Added
- Add the shared library store for art and custom creatures

### Changed
- Rekey Pawn Shop's pawns in place before the move

[1.6.0]: https://github.com/scooper4711/tabletop-kit/releases/tag/v1.6.0

## [1.5.0] - 2026-11-17

### Added
- Derive stable art IDs from embedded pictures and names

### Changed
- Key art by picture and name
- Size custom creatures' pawns from their traits
- Spec shared art and creature libraries with stable art IDs

[1.5.0]: https://github.com/scooper4711/tabletop-kit/releases/tag/v1.5.0

## [1.4.1] - 2026-11-17

### Fixed
- Name Scrollkeeper's folder on the iPhone

### Changed
- Drop the AI disclosure rule from CONTRIBUTING

[1.4.1]: https://github.com/scooper4711/tabletop-kit/releases/tag/v1.4.1

## [1.4.0] - 2026-11-16

### Fixed
- Ask Scrollkeeper on the iPad to download the chosen title

### Changed
- Specify the iPad's download link to Scrollkeeper

[1.4.0]: https://github.com/scooper4711/tabletop-kit/releases/tag/v1.4.0

## [1.3.0] - 2026-11-16

### Added
- Show the About screen from the iPad's menu bar

### Changed
- Specify the About item in the iPad's menu bar

[1.3.0]: https://github.com/scooper4711/tabletop-kit/releases/tag/v1.3.0

## [1.2.0] - 2026-11-15

### Added
- Let an app read only Scrollkeeper's library list

### Changed
- Specify a bridge that reads only the library list

[1.2.0]: https://github.com/scooper4711/tabletop-kit/releases/tag/v1.2.0

## [1.1.0] - 2026-11-15

### Added
- Share the Scrollkeeper bridge in TablesideShared

### Changed
- Specify the shared Scrollkeeper bridge

[1.1.0]: https://github.com/scooper4711/tabletop-kit/releases/tag/v1.1.0

## [1.0.0] - 2026-11-12

### Added
- Draw the demo maps at Flip-Mat size
- Share one empty-window view between Pluck and Mapsmith
- Validate an App Store package without uploading it
- Package an app for the Mac App Store from shared scripts
- Write the demo library's PDFs

### Fixed
- Describe each demo PDF truly, and show demo art up front
- Clear the quarantine attribute before signing the App Store package
- Keep the empty-window buttons from truncating their titles
- Name the App Store icon and follow the app's system and entitlements
- Package from absolute paths, which actool needs
- Draw the demo pawns at Paizo's outline sizes
- Read pawns printed without a copyright line
- Write the same demo PDFs every time

### Changed
- use the exact Community Use notice wording
- Check what the empty window draws
- Specify the shared Mac App Store build
- Specify the demo library's PDFs

[1.0.0]: https://github.com/scooper4711/tabletop-kit/releases/tag/v1.0.0

## [0.17.0] - 2026-11-07

### Added
- Name Scrollkeeper's folders the same way in every app

### Changed
- Specify how the apps show where files are

[0.17.0]: https://github.com/scooper4711/tabletop-kit/releases/tag/v0.17.0

## [0.16.0] - 2026-11-07

### Added
- Add TablesideShared for the toolkit's App Group

### Changed
- Specify the Tableside Shared library
- Welcome signed commits without requiring them
- Add a contributing guide

[0.16.0]: https://github.com/scooper4711/tabletop-kit/releases/tag/v0.16.0

## [0.15.2] - 2026-11-06

### Fixed
- Leave pictures out of pawn labels
- Stop retrying every split of a label that isn't doubled
- Show Markdown license files as plain text in About
- Scale a full-screen card up as a whole, under no toolbar

### Changed
- Run the real-PDF tests on sample pages in CI

[0.15.2]: https://github.com/scooper4711/tabletop-kit/releases/tag/v0.15.2

## [0.15.1] - 2026-10-17

### Fixed
- Relink PDFs to a folder when it is watched again

### Changed
- Restore access when a folder is watched again

[0.15.1]: https://github.com/scooper4711/tabletop-kit/releases/tag/v0.15.1

## [0.15.0] - 2026-10-15

### Added
- Offer a spell's detail fields to other importers

[0.15.0]: https://github.com/scooper4711/tabletop-kit/releases/tag/v0.15.0

## [0.14.2] - 2026-10-15

### Fixed
- Describe level formulas from the entry's own level

[0.14.2]: https://github.com/scooper4711/tabletop-kit/releases/tag/v0.14.2

## [0.14.1] - 2026-10-15

### Fixed
- Word dice with growing bonuses, skill ranks and chosen damage types

[0.14.1]: https://github.com/scooper4711/tabletop-kit/releases/tag/v0.14.1

## [0.14.0] - 2026-10-15

### Added
- Offer formula wording to other importers
- Work out damage formulas and describe ones known only in play

### Changed
- Specify working out damage formulas
- Say the toolkit is Mac apps, two also on the iPad

[0.14.0]: https://github.com/scooper4711/tabletop-kit/releases/tag/v0.14.0

## [0.13.0] - 2026-10-15

### Added
- List the bundled licenses on the About screen

### Changed
- Specify the license texts on the About screen
- Rename the suite the Tableside Toolkit
- Name the apps and describe every library
- Call the combat tracker Turnkeeper in the changelog

[0.13.0]: https://github.com/scooper4711/tabletop-kit/releases/tag/v0.13.0

## [0.12.0] - 2026-10-14

### Changed
- Read the Generated folder from BESTIARY_GENERATED
- Call the combat tracker Turnkeeper

[0.12.0]: https://github.com/scooper4711/tabletop-kit/releases/tag/v0.12.0

## [0.11.0] - 2026-10-14

### Added
- Add an About screen with Paizo's required notices

### Changed
- Specify the shared About screen

[0.11.0]: https://github.com/scooper4711/tabletop-kit/releases/tag/v0.11.0

## [0.10.0] - 2026-10-14

### Added
- Draw action icons with Paizo's Pathfinder-Icons font

### Changed
- Describe the Pathfinder-Icons action font

[0.10.0]: https://github.com/scooper4711/tabletop-kit/releases/tag/v0.10.0

## [0.9.3] - 2026-10-13

### Fixed
- Remove the rivets behind the level on Pathfinder cards

[0.9.3]: https://github.com/scooper4711/tabletop-kit/releases/tag/v0.9.3

## [0.9.2] - 2026-10-13

### Fixed
- Key creatures by their pack's name in links

[0.9.2]: https://github.com/scooper4711/tabletop-kit/releases/tag/v0.9.2

## [0.9.1] - 2026-10-13

### Fixed
- Let taps through the card frame to links and tags

[0.9.1]: https://github.com/scooper4711/tabletop-kit/releases/tag/v0.9.1

## [0.9.0] - 2026-10-12

### Added
- Add an interactive battle card and shared art picture
- Show conditions and trait immunities on cards
- Derive trait immunities and estimate health

### Changed
- Specify condition tags, interactive cards and derived immunities

[0.9.0]: https://github.com/scooper4711/tabletop-kit/releases/tag/v0.9.0

## [0.8.0] - 2026-10-12

### Added
- Read item art from item decks sold as pictures

### Changed
- Name the cut-out picture apart from the image helper
- Describe reading item decks sold as pictures

[0.8.0]: https://github.com/scooper4711/tabletop-kit/releases/tag/v0.8.0

## [0.7.0] - 2026-10-12

### Added
- Read item art from Paizo's item decks

### Changed
- Describe reading item decks
- Read every test bundle for coverage, as Xcode 27 builds one per target

[0.7.0]: https://github.com/scooper4711/tabletop-kit/releases/tag/v0.7.0

## [0.6.0] - 2026-10-11

### Added
- Share the creature art store
- Register the pf2e repository's web fonts for the cards

### Changed
- Describe the shared creature art store
- Register web fonts for the cards

[0.6.0]: https://github.com/scooper4711/tabletop-kit/releases/tag/v0.6.0

## [0.5.0] - 2026-10-11

[0.5.0]: https://github.com/scooper4711/tabletop-kit/releases/tag/v0.5.0

## [0.4.0] - 2026-10-10

### Added
- Share the flow layout, template badge and signed numbers
- Copy the cards' UI art from the user's packs
- Draw battle cards in a look of their own
- Move the card text and glossary from Turnkeeper
- Move the creature import from Turnkeeper
- Move the creature model from Turnkeeper

### Changed
- Describe the battle cards
- Describe the shared creatures and their import

[0.4.0]: https://github.com/scooper4711/tabletop-kit/releases/tag/v0.4.0

## [0.3.0] - 2026-10-10

### Added
- Keep the art of the user's PDFs in a library
- Model the art library and its file references
- Find the PDFs of art in a folder

### Changed
- Describe the art library

[0.3.0]: https://github.com/scooper4711/tabletop-kit/releases/tag/v0.3.0

## [0.2.0] - 2026-10-10

### Added
- Find pawns printed without cut outlines
- Turn figures upright when drawing them
- Rebuild pawn labels from the pieces of text

### Changed
- Describe reading pawns without cut outlines

[0.2.0]: https://github.com/scooper4711/tabletop-kit/releases/tag/v0.2.0

## [0.1.0] - 2026-10-10

### Added
- Initial release

[0.1.0]: https://github.com/scooper4711/tabletop-kit/releases/tag/v0.1.0
