# Store listing and TestFlight: requirements

Every Tableside Toolkit app has an App Store Connect record for iOS, for macOS or for both. Its listing text,
screenshots, review notes and TestFlight notes are kept as files, and scripts here send them to App Store Connect, so
nothing is typed into the website for a release. The steps live here once, as scripts the apps and the store folder
call from a checkout of tabletop-kit.

## R1 The files
- R1.1 An app's store folder holds `metadata/` (the listing text and review information, in the layout fastlane's
  *deliver* reads), `screenshots/ios/` and `screenshots/macos/` (a folder per language in each) and
  `testflight/what-to-test.txt`, and optionally `review/attachment-<platform>.<ext>` (R2.4).
- R1.2 App Store Connect holds the text per platform. `metadata/` is the text of the first platform in `PLATFORMS`
  and serves the others too; a file in which another platform's text differs is in `metadata-<platform>/`, at the
  same path, and nothing else is.
- R1.3 The scripts don't care where the store folder is. It holds review contact details, so it belongs in a private
  repository, never in an app's public one.

## R2 The listing
- R2.1 `scripts/store-listing.sh pull <bundle-id> <store-dir>` writes the listing text App Store Connect holds, for
  every platform, into `metadata/` and `metadata-<platform>/` (R1.2), so a push after a pull changes nothing on any
  platform. `pull-screenshots` does the same for the screenshots of each platform.
- R2.2 `scripts/store-listing.sh push <bundle-id> <store-dir>` sends each platform its text (R1.2) and screenshots, to
  the version being prepared, for every platform in `PLATFORMS`, and sets that version's number to `VERSION`.
  Screenshots on the record are replaced by the folder's; a platform with no screenshots in its folder keeps its own.
- R2.4 A file named `review/attachment-<platform>.<ext>` in the store folder (a PDF or zip) is sent to that platform's
  version as its App Review attachment, which App Store Connect holds one of per version. A platform without one
  keeps the attachment on its record.
- R2.3 A push never uploads a build and never submits the version for review. Submitting stays a person's decision,
  made on the website.

## R3 TestFlight
- R3.1 `scripts/archive-ios.sh <project> <scheme> <out-dir>` archives an app's iOS target and exports the `.ipa` for
  App Store Connect, with the version and build number of the app's `scripts/version.sh`, or `VERSION` and
  `BUILD_NUMBER` when given.
- R3.2 `scripts/testflight.sh <bundle-id> <ipa-or-pkg> <notes-file>` uploads the build, gives it the notes as "What
  to Test", adds it to the groups in `TESTFLIGHT_GROUPS` (default `Public beta`) and sends it to beta review.
- R3.3 Without notes, or with notes over TestFlight's 4000 characters, nothing is uploaded.
- R3.4 After an upload, the commit the build came from is tagged `testflight/<version>-<build>` and the tag is pushed.
  The tag starts no release and doesn't change the marketing version. A build with uncommitted changes isn't tagged,
  an existing tag on another commit is left alone, and a tagging problem warns without failing the finished upload.

## R4 The key
- R4.1 Every script takes the App Store Connect API key from `ASC_KEY_ID`, `ASC_ISSUER_ID` and `ASC_KEY_FILE`, as
  `package-appstore.sh` does. Changing a listing needs a key with the App Manager role.
- R4.2 The copy of the key a script makes for a tool is removed however the script ends.
- R4.3 A missing key, key file, version or tool stops the script with a message naming what is missing, before
  anything is sent.
