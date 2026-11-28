#!/bin/sh
# Lets a Developer ID build of a Mac app sync through iCloud (docs/specs/library-sync, R6.2): adds the CloudKit
# container and push entitlements to the entitlements to sign with, embeds the provisioning profile that allows
# them, and names the suite's container in the Info.plist, which turns syncing on (R6.1). Keys that are there
# already are replaced, so it can run again on the same files.
#
# Usage: scripts/add-icloud-entitlements.sh <app> <entitlements> <team ID> <provisioning profile>
# ICLOUD_CONTAINERS   The app's CloudKit containers, separated by spaces. Default: the suite's, which the shared
#                     library syncs through. An app with a container of its own names both.
# ICLOUD_ENVIRONMENT  CloudKit environment, Production or Development. Default: Production for the App Store
#                     (CHANNEL=appstore), Development for every other build, so a local build never touches the
#                     library real devices sync. An iPad build installed from Xcode uses Development too.
set -eu

SUITE_CONTAINER="iCloud.io.github.scooper4711.tableside"

if [ $# -ne 4 ]; then
    echo "Usage: $0 <app> <entitlements> <team ID> <provisioning profile>" >&2
    exit 2
fi
APP="$1"
ENTITLEMENTS="$2"
TEAM_ID="$3"
PROFILE="$4"
CONTAINERS="${ICLOUD_CONTAINERS:-$SUITE_CONTAINER}"
if [ "${CHANNEL:-}" = "appstore" ]; then DEFAULT_ENVIRONMENT=Production; else DEFAULT_ENVIRONMENT=Development; fi
ENVIRONMENT="${ICLOUD_ENVIRONMENT:-$DEFAULT_ENVIRONMENT}"
INFO="$APP/Contents/Info.plist"

case "$ENVIRONMENT" in
    Production) PUSH=production ;;
    Development) PUSH=development ;;
    *) echo "Adding iCloud failed: ICLOUD_ENVIRONMENT must be Production or Development." >&2; exit 1 ;;
esac
# The profile must allow the environment, or macOS refuses to launch the signed app. A Developer ID profile names no
# environment and allows only Production; a development profile names both. A signed profile is decoded with
# security; a plain property list (as the tests use) is read as it is; a file without Entitlements can't be checked.
PROFILE_PLIST="$(mktemp)"
trap 'rm -f "$PROFILE_PLIST"' EXIT
security cms -D -i "$PROFILE" > "$PROFILE_PLIST" 2>/dev/null || cp "$PROFILE" "$PROFILE_PLIST"
if /usr/libexec/PlistBuddy -c "Print :Entitlements" "$PROFILE_PLIST" >/dev/null 2>&1; then
    ALLOWED="$(/usr/libexec/PlistBuddy -c "Print :Entitlements:com.apple.developer.icloud-container-environment" \
        "$PROFILE_PLIST" 2>/dev/null | grep -oE 'Production|Development' || true)"
    ALLOWED="${ALLOWED:-Production}"
    if ! echo "$ALLOWED" | grep -qx "$ENVIRONMENT"; then
        echo "Adding iCloud failed: the profile allows only $(echo "$ALLOWED" | tr '\n' ' ')but this build is" \
            "$ENVIRONMENT. Use a development profile, or ICLOUD_ENVIRONMENT=Production." >&2
        exit 1
    fi
else
    echo "Adding iCloud: $PROFILE isn't a profile this script can read, so its environments aren't checked." >&2
fi

# Sets a key of the entitlements, in place of the value it had.
set_entitlement() {
    /usr/libexec/PlistBuddy -c "Delete :$1" "$ENTITLEMENTS" >/dev/null 2>&1 || true
    /usr/libexec/PlistBuddy -c "Add :$1 $2" "$ENTITLEMENTS"
}

BUNDLE_ID="$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$INFO")"
# Readable by all whatever the source's mode: installed, the bundle belongs to root.
install -m 644 "$PROFILE" "$APP/Contents/embedded.provisionprofile"
set_entitlement com.apple.application-identifier "string $TEAM_ID.$BUNDLE_ID"
set_entitlement com.apple.developer.team-identifier "string $TEAM_ID"
set_entitlement com.apple.developer.icloud-services array
/usr/libexec/PlistBuddy -c "Add :com.apple.developer.icloud-services:0 string CloudKit" "$ENTITLEMENTS"
set_entitlement com.apple.developer.icloud-container-environment "string $ENVIRONMENT"
set_entitlement com.apple.developer.aps-environment "string $PUSH"
set_entitlement com.apple.developer.icloud-container-identifiers array

SYNCS_LIBRARY=0
INDEX=0
for CONTAINER in $CONTAINERS; do
    /usr/libexec/PlistBuddy -c "Add :com.apple.developer.icloud-container-identifiers:$INDEX string $CONTAINER" \
        "$ENTITLEMENTS"
    INDEX=$((INDEX + 1))
    if [ "$CONTAINER" = "$SUITE_CONTAINER" ]; then SYNCS_LIBRARY=1; fi
done

# The app syncs the shared library only when it may use the suite's container.
if [ "$SYNCS_LIBRARY" -eq 1 ]; then
    plutil -replace TablesideSyncContainer -string "$SUITE_CONTAINER" "$INFO"
    plutil -replace TablesideSyncEnvironment -string "$ENVIRONMENT" "$INFO"
else
    plutil -remove TablesideSyncContainer "$INFO" >/dev/null 2>&1 || true
    plutil -remove TablesideSyncEnvironment "$INFO" >/dev/null 2>&1 || true
fi
echo "Added iCloud ($ENVIRONMENT) for $CONTAINERS"
