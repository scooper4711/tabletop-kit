#!/usr/bin/env bash
# Fetches an app's App Store listing into its store folder, or sends the folder to App Store Connect.
# Specified in docs/specs/store-listing. It never uploads a build and never submits a version for review.
#
# Usage: store-listing.sh pull|pull-screenshots|push <bundle-id> <store-dir>
#   pull              writes the listing text App Store Connect holds into <store-dir>/metadata
#   pull-screenshots  writes each platform's screenshots into <store-dir>/screenshots/<platform>
#   push              sends metadata/ and screenshots/<platform>/ to the version being prepared, on each platform
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
    # Submitting stays a person's decision: the option is never passed, and its variable can't turn it on.
    env -u DELIVER_SUBMIT_FOR_REVIEW "$FASTLANE" deliver "$@" --api_key_path "$API_KEY_JSON" \
        --app_identifier "$BUNDLE_ID" --platform "$(fastlane_platform "$platform")"
}

pull() {
    mkdir -p "$STORE_DIR/metadata"
    # One copy of the text serves every platform, so the first platform's is the one fetched.
    deliver "${PLATFORMS%% *}" download_metadata --metadata_path "$STORE_DIR/metadata" --force
}

pull_screenshots() {
    local platform
    for platform in $PLATFORMS; do
        mkdir -p "$STORE_DIR/screenshots/$platform"
        deliver "$platform" download_screenshots --screenshots_path "$STORE_DIR/screenshots/$platform" --force
    done
}

push() {
    local platform
    [[ -n "${VERSION:-}" ]] || fail "VERSION must be the version number being prepared"
    [[ -d "$STORE_DIR/metadata" ]] || fail "there is no metadata folder in $STORE_DIR"
    for platform in $PLATFORMS; do
        push_platform "$platform"
    done
}

# Usage: push_platform <platform>; a platform without a screenshots folder keeps the screenshots it has.
push_platform() {
    local screenshots="$STORE_DIR/screenshots/$1"
    set -- "$1" --app_version "$VERSION" --metadata_path "$STORE_DIR/metadata" --skip_binary_upload --force
    if [[ -d "$screenshots" ]]; then
        deliver "$@" --screenshots_path "$screenshots" --overwrite_screenshots
    else
        deliver "$@" --skip_screenshots
    fi
}

case "$COMMAND" in
    pull | pull-screenshots | push) ;;
    *) fail "usage: store-listing.sh pull|pull-screenshots|push <bundle-id> <store-dir>" ;;
esac
require_fastlane
write_api_key
case "$COMMAND" in
    pull) pull ;;
    pull-screenshots) pull_screenshots ;;
    push) push ;;
esac
