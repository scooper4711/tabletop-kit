#!/usr/bin/env bash
# Uploads a build to TestFlight with its "What to Test" notes, adds it to the tester groups and sends it to beta
# review, then tags the commit it was built from as testflight/<version>-<build>. The tag doesn't start with "v", so it
# starts no release and doesn't change the marketing version. Specified in docs/specs/store-listing.
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

warn() { echo "$SCRIPT: the build is uploaded, but $*" >&2; }

# Tags the commit in <build>.source (record-build-source.sh). The upload has already happened, so a problem here warns
# rather than fails. iPad and Mac builds of one commit share a tag.
tag_uploaded_build() {
    local version number commit tag existing
    [[ -f "$BUILD.source" ]] || { warn "it has no recorded commit (uncommitted changes?), so it isn't tagged"; return 0; }
    read -r version number commit < "$BUILD.source"
    tag="testflight/$version-$number"
    git fetch --quiet origin "refs/tags/$tag:refs/tags/$tag" 2>/dev/null || true
    existing="$(git rev-parse --quiet --verify "refs/tags/$tag^{commit}" 2>/dev/null || true)"
    if [[ -n "$existing" && "$existing" != "$commit" ]]; then
        warn "$tag already marks another commit, so it isn't tagged"
        return 0
    fi
    if [[ -z "$existing" ]] && ! git tag -s "$tag" "$commit" -m "TestFlight build $number of $version"; then
        warn "tagging it $tag failed"
        return 0
    fi
    git push --quiet origin "refs/tags/$tag" || warn "pushing $tag failed"
}

require_fastlane
write_api_key
"$FASTLANE" pilot upload "$@" --api_key_path "$API_KEY_JSON" --app_identifier "$BUNDLE_ID" \
    --changelog "$(cat "$NOTES")" --groups "${TESTFLIGHT_GROUPS:-Public beta}" --distribute_external
tag_uploaded_build
