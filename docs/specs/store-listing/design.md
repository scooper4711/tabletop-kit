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
written on the spot (`method` `app-store-connect`, `destination` `export`, automatic signing). Both get
`-allowProvisioningUpdates` and, when the `ASC_*` variables are set, the key as `-authenticationKey…`, so signing
needs no Xcode account. The `.ipa` lands in `<out-dir>/export/`, and its path is the script's last line of output.

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
fastlane runs and gone afterward; `pilot` options by file type; the archive and export commands; and that a missing
key, version, notes file or over-long notes stops before a tool is run. Nothing is sent anywhere.
