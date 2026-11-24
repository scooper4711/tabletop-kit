#!/usr/bin/env bash
# Adds iCloud to a tiny generated app and checks what add-icloud-entitlements.sh promises (library sync R6).
set -euo pipefail
cd "$(dirname "$0")/.."
DIR="$(mktemp -d)"; trap 'rm -rf "$DIR"' EXIT
APP="$DIR/Demo.app"
INFO="$APP/Contents/Info.plist"
ENTITLEMENTS="$DIR/app.entitlements"
SUITE="iCloud.io.github.scooper4711.tableside"
mkdir -p "$APP/Contents/MacOS"
cp /usr/bin/true "$APP/Contents/MacOS/Demo"
cat > "$INFO" <<P
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict><key>CFBundleExecutable</key><string>Demo</string>
<key>CFBundleIdentifier</key><string>io.example.demo</string></dict></plist>
P
cat > "$ENTITLEMENTS" <<P
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict><key>com.apple.security.app-sandbox</key><true/>
<key>com.apple.application-identifier</key><string>STALE.io.example.demo</string></dict></plist>
P
echo "profile" > "$DIR/demo.provisionprofile"

check() { if ! eval "$2"; then echo "FAIL: $1" >&2; exit 1; fi; }
entitlement() { /usr/libexec/PlistBuddy -c "Print :$1" "$ENTITLEMENTS"; }
info() { /usr/libexec/PlistBuddy -c "Print :$1" "$INFO" 2>/dev/null; }
add() { scripts/add-icloud-entitlements.sh "$APP" "$ENTITLEMENTS" ABCDE12345 "$DIR/demo.provisionprofile" >/dev/null; }

add
check "profile is embedded"          '[[ "$(cat "$APP/Contents/embedded.provisionprofile")" == profile ]]'
check "stale identifier replaced"    '[[ "$(entitlement com.apple.application-identifier)" == ABCDE12345.io.example.demo ]]'
check "team is named"                '[[ "$(entitlement com.apple.developer.team-identifier)" == ABCDE12345 ]]'
check "the suite's container"        '[[ "$(entitlement com.apple.developer.icloud-container-identifiers:0)" == "$SUITE" ]]'
check "CloudKit is the service"      '[[ "$(entitlement com.apple.developer.icloud-services:0)" == CloudKit ]]'
check "Development by default"       '[[ "$(entitlement com.apple.developer.icloud-container-environment)" == Development ]]'
check "development push by default"  '[[ "$(entitlement com.apple.developer.aps-environment)" == development ]]'
check "other entitlements are kept"  '[[ "$(entitlement com.apple.security.app-sandbox)" == true ]]'
check "Info.plist names the container" '[[ "$(info TablesideSyncContainer)" == "$SUITE" ]]'
check "Info.plist names Development by default" '[[ "$(info TablesideSyncEnvironment)" == Development ]]'

CHANNEL=appstore add
check "Production for the App Store" '[[ "$(entitlement com.apple.developer.icloud-container-environment)" == Production ]]'
check "production push for the App Store" '[[ "$(entitlement com.apple.developer.aps-environment)" == production ]]'
check "Info.plist names Production"  '[[ "$(info TablesideSyncEnvironment)" == Production ]]'

CHANNEL=appstore ICLOUD_ENVIRONMENT=Development ICLOUD_CONTAINERS="iCloud.io.example.demo $SUITE" add
check "Development when asked, even for the App Store"       '[[ "$(entitlement com.apple.developer.icloud-container-environment)" == Development ]]'
check "development push"             '[[ "$(entitlement com.apple.developer.aps-environment)" == development ]]'
check "the app's own container first" '[[ "$(entitlement com.apple.developer.icloud-container-identifiers:0)" == iCloud.io.example.demo ]]'
check "the suite's container second" '[[ "$(entitlement com.apple.developer.icloud-container-identifiers:1)" == "$SUITE" ]]'
check "one service after a second run" '! entitlement com.apple.developer.icloud-services:1 >/dev/null 2>&1'
check "still names the container"    '[[ "$(info TablesideSyncContainer)" == "$SUITE" ]]'
check "Info.plist names Development" '[[ "$(info TablesideSyncEnvironment)" == Development ]]'

ICLOUD_CONTAINERS="iCloud.io.example.demo" add
check "only the app's container"     '! entitlement com.apple.developer.icloud-container-identifiers:1 >/dev/null 2>&1'
check "no container named without the suite's" '[[ -z "$(info TablesideSyncContainer)" ]]'
check "no environment named without the suite's" '[[ -z "$(info TablesideSyncEnvironment)" ]]'
check "unknown environment refused"  '! ICLOUD_ENVIRONMENT=Staging add 2>/dev/null'
check "missing arguments refused"    '! scripts/add-icloud-entitlements.sh "$APP" "$ENTITLEMENTS" 2>/dev/null'
plutil -lint "$ENTITLEMENTS" "$INFO" >/dev/null
echo "add-icloud-entitlements: all checks passed"
