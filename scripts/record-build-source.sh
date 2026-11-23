#!/usr/bin/env bash
# Records which commit a store build came from, in <artifact>.source, so testflight.sh can tag that commit after the
# upload. Specified in docs/specs/store-listing (R3.4). Records nothing for a build with uncommitted changes, or
# outside a git checkout, since no commit describes it. Never fails the build.
#
# Usage: record-build-source.sh <artifact> <version> <build-number>
set -uo pipefail

ARTIFACT="${1:?artifact}"
VERSION="${2:-}"
BUILD_NUMBER="${3:-}"
SOURCE="$ARTIFACT.source"

rm -f "$SOURCE"
[[ -n "$VERSION" && -n "$BUILD_NUMBER" ]] || exit 0
COMMIT="$(git rev-parse --verify HEAD 2>/dev/null)" || exit 0
git diff --quiet HEAD 2>/dev/null || exit 0
echo "$VERSION $BUILD_NUMBER $COMMIT" > "$SOURCE"
