#!/usr/bin/env bash
# Uploads a build to TestFlight with its "What to Test" notes, adds it to the tester groups and sends it to beta
# review. Specified in docs/specs/store-listing.
#
# Usage: testflight.sh <bundle-id> <ipa-or-pkg> <notes-file>
#   <ipa-or-pkg>   the iOS .ipa (archive-ios.sh) or the Mac .pkg (package-appstore.sh)
#   <notes-file>   what testers should look at in this build, at most 4000 characters
#
# TESTFLIGHT_GROUPS   the groups that get the build, comma-separated (default "Public beta")
# ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_FILE and FASTLANE: see store-common.sh
set -euo pipefail

SCRIPT="testflight"
# shellcheck source=scripts/store-common.sh
source "$(dirname "$0")/store-common.sh"

BUNDLE_ID="${1:-}"
BUILD="${2:-}"
NOTES="${3:-}"
NOTES_LIMIT=4000
[[ -n "$BUNDLE_ID" && -n "$BUILD" && -n "$NOTES" ]] \
    || fail "usage: testflight.sh <bundle-id> <ipa-or-pkg> <notes-file>"
[[ -f "$BUILD" ]] || fail "there is no build at $BUILD"
[[ -s "$NOTES" ]] || fail "there are no notes for the testers at $NOTES"
[[ "$(wc -m < "$NOTES")" -le "$NOTES_LIMIT" ]] || fail "the notes at $NOTES are over $NOTES_LIMIT characters"

case "$BUILD" in
    *.ipa) set -- --ipa "$BUILD" ;;
    *.pkg) set -- --pkg "$BUILD" --app_platform osx ;;
    *) fail "$BUILD is neither an .ipa nor a .pkg" ;;
esac
require_fastlane
write_api_key
"$FASTLANE" pilot upload "$@" --api_key_path "$API_KEY_JSON" --app_identifier "$BUNDLE_ID" \
    --changelog "$(cat "$NOTES")" --groups "${TESTFLIGHT_GROUPS:-Public beta}" --distribute_external
