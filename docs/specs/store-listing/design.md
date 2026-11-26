# Store listing and TestFlight: design

Three scripts wrap [fastlane](https://docs.fastlane.tools): *deliver* for the listing and *pilot* for TestFlight.
fastlane already signs the API's tokens and does the reserve, upload and commit steps a screenshot needs; the scripts
call it with explicit options, so no app has a `Fastfile` or `Deliverfile`. fastlane is not a dependency of the
package: it is installed on the Mac that releases (`brew install fastlane`), and `FASTLANE` names another copy.

## `store-common.sh`

Sourced by the other two.

- `require_fastlane` sets `FASTLANE` to the one on `PATH`, or stops.
- `write_api_key` checks the three `ASC_*` variables and the key file, then writes fastlane's key file
  (`{"key_id", "issuer_id", "key"}`, the key being the `.p8`'s text with its line ends escaped) into `WORK_DIR`, a
  `mktemp -d` scratch folder, and sets `API_KEY_JSON`. An `EXIT` trap removes the folder.

## `store-listing.sh`

`PLATFORMS` (default `ios macos`) names the records to work on; an app with only a macOS record passes `macos`.
fastlane calls macOS `osx`, which `fastlane_platform` translates.

- `pull`: `deliver download_metadata --metadata_path <store>/metadata --force`, for the first platform. Every other
  platform's text is downloaded into the scratch folder and compared file by file: the files that differ are copied
  to `metadata-<platform>/`, which is emptied first, so it never holds a difference that is gone.
- `pull-screenshots`: `deliver download_screenshots --screenshots_path <store>/screenshots/<platform>` for each
  platform, and removes the folders left empty when a record has none. It is for the first import: fastlane names the
  files after their device and position, so a later pull doesn't match the names the folder was pushed with.
- `push`: for each platform, `deliver --app_version $VERSION --metadata_path … --skip_binary_upload --force`. The
  path is `metadata/`, or for a platform with a `metadata-<platform>/` a copy of `metadata/` in the scratch folder
  with that folder's files over it. With
  `--screenshots_path … --overwrite_screenshots` when the platform has a folder and `--skip_screenshots` when not.
  `--app_version` renames the version being prepared, which is how the record's number follows the release.
  deliver then runs *precheck* over the text, which looks for what App Review rejects. It can't read in-app purchases
  with an API key and stops there, so `--precheck_include_in_app_purchases false` leaves them out.

deliver runs in a folder of its own inside the scratch folder, with an empty `metadata` folder in it: without one
where it runs, deliver stops to ask whether to set itself up, and it leaves its default folders behind. The store
folder is given to it as a full path.

R2.3: the script never passes `submit_for_review`, whose default is off, and unsets `DELIVER_SUBMIT_FOR_REVIEW`, the
environment variable that would turn it on. Boolean options are passed bare (`--force`, not `--force true`), the form
fastlane documents.

## `archive-ios.sh`

`xcodebuild archive` for `generic/platform=iOS` with `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` on the
command line, where they win over an app's `Version.xcconfig`; then `xcodebuild -exportArchive` with an options file
written on the spot (`method` `app-store-connect`, `destination` `export`). The `.ipa` lands in
`<out-dir>/export/`, and its path is the script's last line of output.

Signing depends on the `ASC_*` variables:

- **Set (R3.5):** manual signing, so nothing new is made. Automatic signing archives with an Apple Development
  identity, and on a hosted runner, which has none, Xcode made a certificate through the API on every run. Its private
  key died with the runner, and about ten runs filled the account's certificate limit.
  - The bundle identifiers are the scheme's app, from `xcodebuild -showBuildSettings -scheme`, and the project's
    app extensions whose identifiers start with the app's, from `-alltargets -sdk iphoneos`. A scheme's settings
    leave out the extensions it embeds, and Apple requires an embedded extension's identifier to start with its
    app's. Settings that can't be read stop the script with a message that says so.
  - `ios-store-profiles.rb` finds the keychain's valid Apple Distribution certificates by serial number in App
    Store Connect, then reuses or makes an `IOS_APP_STORE` profile per bundle identifier and installs it in
    `~/Library/Developer/Xcode/UserData/Provisioning Profiles`. It deletes only profiles of its own name, in App Store
    Connect and in that folder, so a machine that keeps its files can't pick a replaced profile by name. An
    identifier registered for macOS only stops it with a message that says so.
  - CI exports `PROVISIONING_PROFILE`, the Mac App Store profile, and xcodebuild reads the environment as build
    settings. The script unsets it and the xcconfig empties it, so no target gets the Mac profile.
  - The archive gets `-xcconfig <out-dir>/Signing.xcconfig`: `CODE_SIGN_STYLE = Manual`, `CODE_SIGN_IDENTITY = Apple
    Distribution`, and `PROVISIONING_PROFILE_SPECIFIER = $(STORE_PROFILE_$(WRAPPER_EXTENSION))`, which names the
    profile for `app` and `appex` targets and is empty for Swift package targets, which take none.
  - The xcconfig also sets `DEVELOPMENT_TEAM` to the app's, read from the scheme's settings. A Swift package's
    resource bundle inherits no team from the project, and manual signing refuses a target without one ("Signing
    for … requires a development team"). An app without a team stops the script with a message that says so.
  - The export options say `signingStyle` `manual`, the `signingCertificate` and the profile of each bundle identifier.
- **Not set:** automatic signing with `-allowProvisioningUpdates` and the account Xcode is signed in to, as before.

What an app must do before archiving (generate its data, fetch its artwork) stays in that app's Makefile.

## `testflight.sh`

`pilot upload --ipa` or `--pkg … --app_platform osx`, by the file's extension, with `--changelog` from the notes
file, `--groups` and `--distribute_external`. pilot waits for App Store Connect to process the build, sets the notes,
adds the groups and submits it for beta review.

`archive-ios.sh` and `package-appstore.sh` call `record-build-source.sh`, which writes `<artifact>.source` with the
version, build number and commit. Reading the commit from there, rather than from `HEAD` at upload time, keeps the tag
right if something was committed between the build and the upload. Tags are signed, as release tags are, and iPad and
Mac builds of one commit share a tag.

`package-appstore.sh` keeps `UPLOAD=1` for uploading a Mac package without TestFlight notes.

## Tests

`scripts/test-store-scripts.sh` puts stand-ins for `fastlane` and `xcodebuild` first on `PATH`. Each records its
arguments, and the fastlane one also copies the key file it was given. The checks: one `deliver` run per platform with
the version and paths; never `submit_for_review`; screenshots replaced or skipped by folder; a platform's differing
text kept by a pull and sent back by a push; the key file valid while
fastlane runs and gone afterward; `pilot` options by file type; the archive and export commands, with manual signing
and one profile per app or extension when there is a key and automatic signing without one; and that a missing
key, version, notes file or over-long notes stops before a tool is run. Nothing is sent anywhere.

`scripts/test-ios-store-profiles.rb` runs the profile logic against a stand-in for App Store Connect: a missing profile
made for the right certificate and iOS bundle identifier, a working one reused, an invalid, expiring or
other-certificate one replaced, others' profiles left alone, a replaced profile's file removed, and no write without
a matching certificate or an iOS registration.
