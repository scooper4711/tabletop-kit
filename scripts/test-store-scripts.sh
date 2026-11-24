#!/usr/bin/env bash
# Runs store-listing.sh, testflight.sh and archive-ios.sh against stand-ins for fastlane and xcodebuild that record
# their arguments, and checks what docs/specs/store-listing promises. Nothing is sent anywhere.
set -euo pipefail
cd "$(dirname "$0")/.."
SCRIPTS="$PWD/scripts"
DIR="$(mktemp -d)"; trap 'rm -rf "$DIR"' EXIT
LOG="$DIR/calls.log"
export LOG KEY_COPY="$DIR/key-seen.json" KEY_PATH_FILE="$DIR/key-path" ENV_LOG="$DIR/env.log"
export ASC_TEXT="$DIR/asc" SENT="$DIR/sent" UNREADY="$DIR/unready.log"
mkdir -p "$ASC_TEXT" "$SENT"

# Each stand-in writes one line per run, its arguments joined by "|".
mkdir -p "$DIR/bin"
cat > "$DIR/bin/fastlane" <<'TOOL'
#!/usr/bin/env bash
{ printf 'fastlane|'; printf '%s|' "$@"; echo; } >> "$LOG"
echo "${DELIVER_SUBMIT_FOR_REVIEW:-unset}" >> "$ENV_LOG"
[[ "${1:-}" != "deliver" || -d metadata ]] || echo "$PWD" >> "$UNREADY"
# A download writes the text App Store Connect would hold for the platform ($ASC_TEXT/<platform>), and an upload
# keeps the description it was given ($SENT/<platform>.txt).
for ((i = 1; i <= $#; i++)); do
    next=$((i + 1))
    case "${!i}" in
        --api_key_path) cp "${!next}" "$KEY_COPY"; echo "${!next}" > "$KEY_PATH_FILE" ;;
        --platform) platform="${!next}" ;;
        --metadata_path) text="${!next}" ;;
        download_metadata) download=1 ;;
    esac
done
[[ "${1:-}" == "deliver" && -n "${text:-}" ]] || exit 0
if [[ -n "${download:-}" ]]; then
    [[ ! -d "$ASC_TEXT/$platform" ]] || cp -R "$ASC_TEXT/$platform/." "$text"
elif [[ -f "$text/en-US/description.txt" ]]; then
    cp "$text/en-US/description.txt" "$SENT/$platform.txt"
fi
TOOL
cat > "$DIR/bin/xcodebuild" <<'TOOL'
#!/usr/bin/env bash
{ printf 'xcodebuild|'; printf '%s|' "$@"; echo; } >> "$LOG"
if [[ "${1:-}" == "-showBuildSettings" ]]; then
    for target in application:io.example.Demo app-extension:io.example.Demo.Widget \
        bundle.ui-testing:io.example.DemoUITests application:io.example.Demo; do
        printf '{"buildSettings":{"PRODUCT_TYPE":"com.apple.product-type.%s","PRODUCT_BUNDLE_IDENTIFIER":"%s"}}\n' \
            "${target%%:*}" "${target#*:}"
    done | paste -sd, - | sed 's/.*/[&]/'
    exit 0
fi
while (($#)); do
    if [[ "$1" == "-exportPath" ]]; then mkdir -p "$2"; touch "$2/Demo.ipa"; fi
    shift
done
[[ -z "${TEST_RUNNER_SCREENSHOT_DIR:-}" ]] || touch "$TEST_RUNNER_SCREENSHOT_DIR/1-home.png"
[[ -z "${TEST_RUNNER_SCREENSHOT_DIR:-}" || -z "${FAIL_TESTS:-}" ]] || exit 65
TOOL
cat > "$DIR/bin/xcrun" <<'TOOL'
#!/usr/bin/env bash
{ printf 'xcrun|'; printf '%s|' "$@"; echo; } >> "$LOG"
case "$2" in
    list) printf '    iPad Pro 13-inch (M5) (16GB) (AAAAAAAA-0000-0000-0000-000000000000) (Shutdown)\n'
          printf '    iPad Pro 13-inch (M5) (BBBBBBBB-0000-0000-0000-000000000000) (Shutdown)\n'
          printf '    iPhone 18 Pro (CCCCCCCC-0000-0000-0000-000000000000) (Shutdown)\n' ;;
    clone) echo "CLONE-$3" ;;
esac
TOOL
cat > "$DIR/bin/sips" <<'TOOL'
#!/usr/bin/env bash
case "$3" in */iphone/*) size=(1206 2622) ;; *) size=(2064 2752) ;; esac
[[ -z "${WRONG_SIZE:-}" ]] || size=(100 100)
if [[ "$2" == "pixelWidth" ]]; then echo "  pixelWidth: ${size[0]}"; else echo "  pixelHeight: ${size[1]}"; fi
TOOL
cat > "$DIR/bin/store-profiles" <<'TOOL'
#!/usr/bin/env bash
{ printf 'profiles|'; printf '%s|' "$@"; echo; } >> "$LOG"
TOOL
chmod +x "$DIR/bin/store-profiles" "$DIR/bin/fastlane" "$DIR/bin/xcodebuild" "$DIR/bin/xcrun" "$DIR/bin/sips"
export PATH="$DIR/bin:$PATH"

printf -- '-----BEGIN PRIVATE KEY-----\nQUJD\n-----END PRIVATE KEY-----\n' > "$DIR/AuthKey.p8"
export ASC_KEY_ID=KEYID12345 ASC_ISSUER_ID=issuer-1 ASC_KEY_FILE="$DIR/AuthKey.p8"
STORE="$DIR/store"
mkdir -p "$STORE/metadata/en-US" "$STORE/screenshots/ios/en-US"
echo "A demo." > "$STORE/metadata/en-US/description.txt"
touch "$STORE/screenshots/ios/en-US/1-home.png"
echo "Check the sync." > "$DIR/notes.txt"
touch "$DIR/Demo.ipa" "$DIR/Demo.pkg"

check() { if ! eval "$2"; then echo "FAIL: $1" >&2; exit 1; fi; }
calls() { if [[ -f "$LOG" ]]; then wc -l < "$LOG" | tr -d ' '; else echo 0; fi; }
# Usage: call <n> <text>; whether the nth recorded run has the text.
call() { sed -n "${1}p" "$LOG" | grep -qF -- "$2"; }
# Usage: refused <command…>; whether the command fails without running a tool.
refused() { local before; before="$(calls)"; ! "$@" 2>/dev/null && [[ "$(calls)" == "$before" ]]; }
listing() { "$SCRIPTS/store-listing.sh" "$@" io.example.demo "$STORE"; }
testflight() { "$SCRIPTS/testflight.sh" io.example.demo "$@"; }

# R2.2, R2.3: push
DELIVER_SUBMIT_FOR_REVIEW=true VERSION=1.2.3 listing push
check "one deliver run per platform"       '[[ "$(calls)" == 2 ]]'
check "iOS gets the version"               'call 1 "--platform|ios|" && call 1 "--app_version|1.2.3|"'
check "iOS gets the metadata folder"       'call 1 "--metadata_path|$STORE/metadata|"'
check "iOS screenshots are replaced"       'call 1 "|$STORE/screenshots/ios|--overwrite_screenshots|"'
check "the Mac record is osx to fastlane"  'call 2 "--platform|osx|"'
check "no Mac folder, screenshots kept"    'call 2 "--skip_screenshots|" && ! call 2 "--overwrite_screenshots"'
mkdir -p "$STORE/screenshots/macos/en-US"
VERSION=1.2.3 PLATFORMS=macos listing push
check "an empty folder deletes nothing"    'call 3 "--skip_screenshots|" && ! call 3 "--overwrite_screenshots"'
mkdir -p "$STORE/review"
echo zip > "$STORE/review/attachment-macos.zip"
VERSION=1.2.3 listing push
check "the Mac gets its attachment"        'call 5 "--app_review_attachment_file|$STORE/review/attachment-macos.zip|"'
check "iOS has none to send"               '! call 4 "--app_review_attachment_file|"'
rm -r "$STORE/review"
check "no build is uploaded"               'call 1 "--skip_binary_upload|" && call 2 "--skip_binary_upload|"'
check "the text check skips purchases"     'call 1 "--precheck_include_in_app_purchases|false|--"'
check "deliver finds itself set up"        '[[ ! -e "$UNREADY" ]]'
check "nothing is left where it was run"   '[[ ! -e metadata && ! -e screenshots ]]'
check "review is never asked for"          '! grep -q submit_for_review "$LOG"'
check "the variable can't ask for it"      '! grep -qv unset "$ENV_LOG"'

# R4: the key
key_seen() { plutil -extract "$1" raw -o - "$KEY_COPY"; }
check "fastlane got the key's ID"          '[[ "$(key_seen key_id)" == KEYID12345 ]]'
check "fastlane got the key's text"        '[[ "$(key_seen key)" == "$(cat "$DIR/AuthKey.p8")" ]]'
check "the key's copy is removed"          '[[ ! -e "$(cat "$KEY_PATH_FILE")" ]]'
check "push without a version refused"     'refused listing push'
check "push without metadata refused"      'VERSION=1 refused "$SCRIPTS/store-listing.sh" push io.example.demo "$DIR"'
check "missing key refused"                'ASC_KEY_ID= VERSION=1 refused listing push'
check "missing key file refused"           'ASC_KEY_FILE="$DIR/none.p8" VERSION=1 refused listing push'
check "missing fastlane refused"           'PATH=/usr/bin:/bin VERSION=1 refused listing push'
check "unknown command refused"            'refused listing publish'

# R2.1: pull
rm "$LOG"
PLATFORMS=macos listing pull
check "pull fetches the text once"         '[[ "$(calls)" == 1 ]] && call 1 "|deliver|download_metadata|"'
check "pull reads the first platform"      'call 1 "--platform|osx|" && call 1 "--metadata_path|$STORE/metadata|"'
listing pull-screenshots
check "screenshots come per platform"      'call 2 "download_screenshots|" && call 3 "--platform|osx|"'
check "each into its own folder"           'call 3 "--screenshots_path|$STORE/screenshots/macos|"'
check "no screenshots, no folder left"     '[[ ! -e "$STORE/screenshots/macos" && -d "$STORE/screenshots/ios/en-US" ]]'

# R1.2: a platform's own text
OURS="$DIR/ours"
for platform in ios osx; do
    mkdir -p "$ASC_TEXT/$platform/en-US"
    echo "pawns,maps" > "$ASC_TEXT/$platform/en-US/keywords.txt"
    echo "For the iPad." > "$ASC_TEXT/$platform/en-US/description.txt"
done
echo "For the Mac, with Finder tags." > "$ASC_TEXT/osx/en-US/description.txt"
"$SCRIPTS/store-listing.sh" pull io.example.demo "$OURS"
check "the first platform's text is kept"  'grep -q "For the iPad." "$OURS/metadata/en-US/description.txt"'
check "the Mac's different text is kept"   'grep -q "Finder tags" "$OURS/metadata-macos/en-US/description.txt"'
check "only the files that differ"         '[[ ! -e "$OURS/metadata-macos/en-US/keywords.txt" ]]'
VERSION=1.2.3 "$SCRIPTS/store-listing.sh" push io.example.demo "$OURS"
check "the iPad gets its text back"        '[[ "$(cat "$SENT/ios.txt")" == "For the iPad." ]]'
check "the Mac gets its own text back"     'grep -q "Finder tags" "$SENT/osx.txt"'
check "the Mac's text is a merged copy"    'tail -n 1 "$LOG" | grep -q "merged-macos"'
cp "$ASC_TEXT/ios/en-US/description.txt" "$ASC_TEXT/osx/en-US/description.txt"
"$SCRIPTS/store-listing.sh" pull io.example.demo "$OURS"
check "no difference, no Mac folder"       '[[ ! -e "$OURS/metadata-macos" ]]'

# R3.2, R3.3: TestFlight
rm "$LOG"
testflight "$DIR/Demo.ipa" "$DIR/notes.txt"
check "an .ipa is uploaded as one"         'call 1 "|pilot|upload|--ipa|$DIR/Demo.ipa|"'
check "the notes are What to Test"         'call 1 "--changelog|Check the sync.|"'
check "the build goes to Public beta"      'call 1 "--groups|Public beta|--distribute_external|"'
TESTFLIGHT_GROUPS="Friends" testflight "$DIR/Demo.pkg" "$DIR/notes.txt"
check "a .pkg is a Mac build"              'call 2 "--pkg|$DIR/Demo.pkg|--app_platform|osx|"'
check "the groups can be named"            'call 2 "--groups|Friends|"'
check "missing notes refused"              'refused testflight "$DIR/Demo.ipa" "$DIR/none.txt"'
: > "$DIR/empty.txt"
check "empty notes refused"                'refused testflight "$DIR/Demo.ipa" "$DIR/empty.txt"'
head -c 4001 /dev/zero | tr '\0' x > "$DIR/long.txt"
check "over-long notes refused"            'refused testflight "$DIR/Demo.ipa" "$DIR/long.txt"'
check "missing build refused"              'refused testflight "$DIR/None.ipa" "$DIR/notes.txt"'
check "another file type refused"          'refused testflight "$DIR/notes.txt" "$DIR/notes.txt"'

# R3.4: the tag, with a stand-in git. EXISTING_COMMIT is what the tag already marks; FAIL_TAG makes tagging fail.
mkdir -p "$DIR/gitbin"
cat > "$DIR/gitbin/git" <<'TOOL'
#!/usr/bin/env bash
{ printf 'git|'; printf '%s|' "$@"; echo; } >> "$LOG"
case "$1" in
    fetch) exit 1 ;;
    rev-parse) [[ -n "${EXISTING_COMMIT:-}" ]] || exit 1; echo "$EXISTING_COMMIT" ;;
    tag) [[ -z "${FAIL_TAG:-}" ]] ;;
esac
TOOL
chmod +x "$DIR/gitbin/git"
tagged() { rm -f "$LOG"; PATH="$DIR/gitbin:$PATH" testflight "$DIR/Demo.ipa" "$DIR/notes.txt" 2>/dev/null; }
echo "2.0.1 251 abc123" > "$DIR/Demo.ipa.source"
tagged
check "the built commit is tagged"         'grep -qF "git|tag|-s|testflight/2.0.1-251|abc123|" "$LOG"'
check "the tag is pushed"                  'grep -qF "git|push|--quiet|origin|refs/tags/testflight/2.0.1-251|" "$LOG"'
EXISTING_COMMIT=abc123 tagged
check "a shared tag isn't made again"      '! grep -qF "git|tag|" "$LOG" && grep -qF "git|push|" "$LOG"'
EXISTING_COMMIT=other tagged
check "another commit's tag is left alone" '! grep -qF "git|tag|" "$LOG" && ! grep -qF "git|push|" "$LOG"'
check "a failed tag doesn't fail upload"   'FAIL_TAG=1 tagged && ! grep -qF "git|push|" "$LOG"'
rm "$DIR/Demo.ipa.source"
tagged
check "no recorded commit, no tag"         '! grep -qF "git|" "$LOG" && grep -qF "pilot" "$LOG"'

REPO="$DIR/repo"
git init --quiet "$REPO"
echo one > "$REPO/file"
git -C "$REPO" add file
git -C "$REPO" -c user.name=Test -c user.email=test@example.invalid -c commit.gpgsign=false commit --quiet -m one
record() { (cd "$REPO" && "$SCRIPTS/record-build-source.sh" Demo.ipa 2.0.1 7); }
record
check "a clean build records its commit" \
    '[[ "$(cat "$REPO/Demo.ipa.source")" == "2.0.1 7 $(git -C "$REPO" rev-parse HEAD)" ]]'
echo two > "$REPO/file"
record
check "uncommitted changes record nothing" '[[ ! -e "$REPO/Demo.ipa.source" ]]'

# R3.1, R3.5: the archive, from a made-up app's folder
rm "$LOG"
APP="$DIR/app"
mkdir -p "$APP/scripts"
printf '#!/bin/sh\ncase "$1" in marketing) echo 2.0.0 ;; build) echo 77 ;; esac\n' > "$APP/scripts/version.sh"
chmod +x "$APP/scripts/version.sh"
IPA="$(cd "$APP" && STORE_PROFILES="$DIR/bin/store-profiles" \
    "$SCRIPTS/archive-ios.sh" ios/Demo.xcodeproj Demo-iPad build/ios 2>/dev/null | tail -n 1)"
# Usage: run_of <text>; the recorded run that has the text.
run_of() { grep -F -- "$1" "$LOG" | tail -n 1; }
OPTIONS="$APP/build/ios/ExportOptions.plist"
check "the .ipa's path is printed"         '[[ "$IPA" == "build/ios/export/Demo.ipa" ]]'
check "the archive has git's version" \
    'run_of "|archive|" | grep -qF "|MARKETING_VERSION=2.0.0|CURRENT_PROJECT_VERSION=77|"'
check "profiles for apps and extensions" \
    'call 2 "profiles|Tableside App Store |io.example.Demo|io.example.Demo.Widget|"'
check "each bundle gets one profile"       '[[ "$(run_of "profiles|" | grep -o "io.example.Demo|" | wc -l)" -eq 1 ]]'
check "no profile for the UI tests"        '! grep -qF DemoUITests "$LOG"'
check "the archive is signed by hand"      'run_of "|archive|" | grep -qF "|-xcconfig|build/ios/Signing.xcconfig|"'
check "with the distribution identity" \
    'grep -qx "CODE_SIGN_IDENTITY = Apple Distribution" "$APP/build/ios/Signing.xcconfig"'
check "and no automatic signing"           'grep -qx "CODE_SIGN_STYLE = Manual" "$APP/build/ios/Signing.xcconfig"'
check "packages take no profile" \
    'grep -qF "= \$(STORE_PROFILE_\$(WRAPPER_EXTENSION))" "$APP/build/ios/Signing.xcconfig"'
check "Xcode may make nothing"             '! grep -qF -- "-allowProvisioningUpdates" "$LOG"'
check "the export follows the archive"     'call 4 "|-exportArchive|-archivePath|build/ios/Demo-iPad.xcarchive|"'
check "the export is for the store"        'grep -q app-store-connect "$OPTIONS"'
check "the export is signed by hand"       '[[ "$(plutil -extract signingStyle raw -o - "$OPTIONS")" == manual ]]'
check "the export names each profile"      \
    'grep -qF "<key>io.example.Demo.Widget</key><string>Tableside App Store io.example.Demo.Widget</string>" "$OPTIONS"'
rm "$LOG"
(cd "$APP" && ASC_KEY_ID= VERSION=3.1.0 BUILD_NUMBER=9 "$SCRIPTS/archive-ios.sh" ios/Demo.xcodeproj Demo-iPad out) \
    > /dev/null 2>&1
check "the version can be given"           'call 1 "|MARKETING_VERSION=3.1.0|CURRENT_PROJECT_VERSION=9|"'
check "without a key, Xcode's account"     'call 1 "|-allowProvisioningUpdates|" && ! grep -qF "profiles|" "$LOG"'
check "which signs automatically" \
    '[[ "$(plutil -extract signingStyle raw -o - "$APP/out/ExportOptions.plist")" == automatic ]]'

# Store screenshots R1.1 to R1.5
rm "$LOG"
SHOTS="$DIR/shots"
shots() { "$SCRIPTS/store-screenshots.sh" ios/Demo.xcodeproj Demo-iPad "$SHOTS" > /dev/null 2>&1; }
shots
check "both devices' pictures are kept"    '[[ -f "$SHOTS/iphone-1-home.png" && -f "$SHOTS/ipad-1-home.png" ]]'
check "the exact iPad model is cloned"     'grep -qF "clone|BBBBBBBB-0000-0000-0000-000000000000|" "$LOG"'
check "the app's UI tests are run"         'grep -qF -- "-only-testing:DemoUITests/StoreScreenshots|" "$LOG"'
check "each clone is erased"               '[[ "$(grep -c "|erase|" "$LOG")" == 2 ]]'
check "each clone is deleted"              '[[ "$(grep -c "|delete|" "$LOG")" == 2 ]]'
check "the status bar is fixed"            'grep -qF "|status_bar|" "$LOG"'
echo kept > "$SHOTS/iphone-1-home.png"
check "a failed test is refused"           '! FAIL_TESTS=1 shots'
check "a wrong size is refused"            '! WRONG_SIZE=1 shots'
check "a failure keeps the pictures"       '[[ "$(cat "$SHOTS/iphone-1-home.png")" == kept ]]'
check "the Mac script wants an app"        '[[ "$("$SCRIPTS/store-screenshots-mac.sh" 2>&1 || true)" == *"usage: "* ]]'
MAC_ERROR="$("$SCRIPTS/store-screenshots-mac.sh" "$DIR/none" x.png 2>&1 || true)"
check "the Mac script wants a bundle"      '[[ "$MAC_ERROR" == *"is not an app bundle"* ]]'
echo "store scripts: all checks passed"
