#!/usr/bin/env bash
# Fetches an app's App Store listing into its store folder, or sends the folder to App Store Connect.
# Specified in docs/specs/store-listing. It never uploads a build and never submits a version for review.
#
# Usage: store-listing.sh pull|pull-screenshots|push <bundle-id> <store-dir>
#   pull              writes the listing text App Store Connect holds into <store-dir>/metadata, and the files in
#                     which another platform's text differs into <store-dir>/metadata-<platform>
#   pull-screenshots  writes each platform's screenshots into <store-dir>/screenshots/<platform>
#   push              sends metadata/ (with metadata-<platform>/ over it) and screenshots/<platform>/ to the version
#                     being prepared, on each platform
#
# PLATFORMS   the records to work on (default "ios macos"); an app with only a Mac record passes "macos"
# VERSION     the version number the prepared version gets (required for push)
# ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_FILE and FASTLANE: see store-common.sh
set -euo pipefail

SCRIPT="store-listing"
# shellcheck source=scripts/store-common.sh
source "$(dirname "$0")/store-common.sh"

COMMAND="${1:-}"
BUNDLE_ID="${2:-}"
STORE_DIR="${3:-}"
PLATFORMS="${PLATFORMS:-ios macos}"
[[ -n "$BUNDLE_ID" && -n "$STORE_DIR" ]] \
    || fail "usage: store-listing.sh pull|pull-screenshots|push <bundle-id> <store-dir>"

# fastlane's name for a platform: it calls macOS osx.
fastlane_platform() { if [[ "$1" == "macos" ]]; then echo osx; else echo "$1"; fi; }

# Usage: deliver <platform> <deliver arguments…>
deliver() {
    local platform="$1"
    shift
    # deliver asks whether to set itself up unless the folder it runs in has a metadata folder, and leaves its
    # default folders there: it runs in a scratch folder that has one. Paths given to it are absolute.
    mkdir -p "$WORK_DIR/run/metadata"
    # Submitting stays a person's decision: the option is never passed, and its variable can't turn it on.
    (cd "$WORK_DIR/run" && env -u DELIVER_SUBMIT_FOR_REVIEW "$FASTLANE" deliver "$@" \
        --api_key_path "$API_KEY_JSON" --app_identifier "$BUNDLE_ID" --platform "$(fastlane_platform "$platform")")
}

# Usage: download_text <platform> <folder>
download_text() {
    mkdir -p "$2"
    deliver "$1" download_metadata --metadata_path "$2" --force
}

pull() {
    local platform base="${PLATFORMS%% *}"
    download_text "$base" "$STORE_DIR/metadata"
    for platform in $PLATFORMS; do
        [[ "$platform" == "$base" ]] || pull_differences "$platform"
    done
}

# Usage: pull_differences <platform>; App Store Connect holds the text per platform. The files in which this
# platform's differs from metadata/ go to metadata-<platform>/, which is removed when none does.
pull_differences() {
    local theirs="$WORK_DIR/$1" own="$STORE_DIR/metadata-$1" file
    download_text "$1" "$theirs"
    rm -rf "$own"
    while IFS= read -r file; do
        cmp -s "$theirs/$file" "$STORE_DIR/metadata/$file" && continue
        mkdir -p "$own/$(dirname "$file")"
        cp "$theirs/$file" "$own/$file"
    done < <(cd "$theirs" && find . -type f)
}

pull_screenshots() {
    local platform
    for platform in $PLATFORMS; do
        mkdir -p "$STORE_DIR/screenshots/$platform"
        deliver "$platform" download_screenshots --screenshots_path "$STORE_DIR/screenshots/$platform" --force
    done
    # A record without screenshots leaves an empty folder, which is not one to send back.
    find "$STORE_DIR/screenshots" -depth -type d -empty -delete
}

push() {
    local platform
    [[ -n "${VERSION:-}" ]] || fail "VERSION must be the version number being prepared"
    [[ -d "$STORE_DIR/metadata" ]] || fail "there is no metadata folder in $STORE_DIR"
    for platform in $PLATFORMS; do
        push_platform "$platform"
    done
}

# Usage: push_platform <platform>; a platform with no screenshots in its folder keeps the ones on its record:
# replacing them with nothing would only delete them. Its review/attachment-<platform>.* goes with it.
push_platform() {
    local screenshots="$STORE_DIR/screenshots/$1" metadata="$STORE_DIR/metadata"
    [[ ! -d "$STORE_DIR/metadata-$1" ]] || metadata="$(merged_text "$1")"
    # deliver checks the text for what App Review rejects; with an API key that check can't read in-app purchases.
    set -- "$1" --app_version "$VERSION" --metadata_path "$metadata" --skip_binary_upload --force \
        --precheck_include_in_app_purchases false
    local attachment review="$STORE_DIR/review"
    attachment="$(find "$review" -maxdepth 1 -type f -name "attachment-$1.*" 2> /dev/null | head -n 1 || true)"
    [[ -z "$attachment" ]] || set -- "$@" --app_review_attachment_file "$attachment"
    if [[ -n "$(find "$screenshots" -type f 2> /dev/null | head -n 1)" ]]; then
        deliver "$@" --screenshots_path "$screenshots" --overwrite_screenshots
    else
        deliver "$@" --skip_screenshots
    fi
}

# Usage: merged_text <platform>; prints a folder holding metadata/ with the platform's own files over it.
merged_text() {
    local merged="$WORK_DIR/merged-$1"
    mkdir -p "$merged"
    cp -R "$STORE_DIR/metadata/." "$STORE_DIR/metadata-$1/." "$merged"
    echo "$merged"
}

case "$COMMAND" in
    pull | pull-screenshots | push) ;;
    *) fail "usage: store-listing.sh pull|pull-screenshots|push <bundle-id> <store-dir>" ;;
esac
require_fastlane
write_api_key
mkdir -p "$STORE_DIR"
STORE_DIR="$(cd "$STORE_DIR" && pwd)"
case "$COMMAND" in
    pull) pull ;;
    pull-screenshots) pull_screenshots ;;
    push) push ;;
esac
