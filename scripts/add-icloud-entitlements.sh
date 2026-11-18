#!/bin/sh
# Lets a Developer ID build of a Mac app sync through iCloud (docs/specs/library-sync, R6.2): adds the CloudKit
# container and push entitlements to the entitlements to sign with, embeds the provisioning profile that allows
# them, and names the suite's container in the Info.plist, which turns syncing on (R6.1). Keys that are there
# already are replaced, so it can run again on the same files.
#
# Usage: scripts/add-icloud-entitlements.sh <app> <entitlements> <team ID> <provisioning profile>
# ICLOUD_CONTAINERS   The app's CloudKit containers, separated by spaces. Default: the suite's, which the shared
#                     library syncs through. An app with a container of its own names both.
# ICLOUD_ENVIRONMENT  CloudKit environment, Production (default) or Development. An iPad build installed from
#                     Xcode uses Development, so to sync with one, build the Mac app for Development too.
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
ENVIRONMENT="${ICLOUD_ENVIRONMENT:-Production}"
INFO="$APP/Contents/Info.plist"

case "$ENVIRONMENT" in
    Production) PUSH=production ;;
    Development) PUSH=development ;;
    *) echo "Adding iCloud failed: ICLOUD_ENVIRONMENT must be Production or Development." >&2; exit 1 ;;
esac

# Sets a key of the entitlements, in place of the value it had.
set_entitlement() {
    /usr/libexec/PlistBuddy -c "Delete :$1" "$ENTITLEMENTS" >/dev/null 2>&1 || true
    /usr/libexec/PlistBuddy -c "Add :$1 $2" "$ENTITLEMENTS"
}

BUNDLE_ID="$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$INFO")"
cp "$PROFILE" "$APP/Contents/embedded.provisionprofile"
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
else
    plutil -remove TablesideSyncContainer "$INFO" >/dev/null 2>&1 || true
fi
echo "Added iCloud ($ENVIRONMENT) for $CONTAINERS"
