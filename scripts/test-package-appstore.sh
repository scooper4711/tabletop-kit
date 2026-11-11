#!/usr/bin/env bash
# Packages a tiny generated app as a trial and checks what package-appstore.sh promises (R2 in the spec).
set -euo pipefail
cd "$(dirname "$0")/.."
DIR="$(mktemp -d)"; trap 'rm -rf "$DIR"' EXIT
APP="$DIR/Demo.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$DIR/icon.iconset"
cp /usr/bin/true "$APP/Contents/MacOS/Demo"
cat > "$APP/Contents/Info.plist" <<P
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict><key>CFBundleExecutable</key><string>Demo</string>
<key>CFBundleIdentifier</key><string>io.example.demo</string><key>CFBundleVersion</key><string>1</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>LSMinimumSystemVersion</key><string>14.0</string></dict></plist>
P
for size in 16 32 128 256 512; do
    sips -z $size $size /System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/GenericApplicationIcon.icns \
        --out "$DIR/icon.iconset/icon_${size}x${size}.png" >/dev/null 2>&1 \
        || sips -s format png -z $size $size /System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/GenericApplicationIcon.icns \
            --out "$DIR/icon.iconset/icon_${size}x${size}.png" >/dev/null
done
iconutil -c icns "$DIR/icon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"
cat > "$DIR/app.entitlements" <<P
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict><key>com.apple.security.app-sandbox</key><true/>
<key>com.apple.application-identifier</key><string>STALE.io.example.demo</string></dict></plist>
P
touch "$APP/Contents/embedded.provisionprofile"
# As a resource downloaded with a browser carries it (ITMS-91109).
echo '{}' > "$APP/Contents/Resources/data.json"
xattr -w com.apple.quarantine "0081;00000000;Safari;" "$APP/Contents/Resources/data.json"

TRIAL=1 BUILD_NUMBER=42 TEAM_ID=ABCDE12345 scripts/package-appstore.sh "$APP" "$DIR/app.entitlements" io.example.demo

OUT="$DIR/appstore"
check() { if ! eval "$2"; then echo "FAIL: $1" >&2; exit 1; fi; }
PLIST="$OUT/Demo.app/Contents/Info.plist"
check "Assets.car is compiled"      '[[ -f "$OUT/Demo.app/Contents/Resources/Assets.car" ]]'
check "build number is 42"          '[[ "$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$PLIST")" == 42 ]]'
check "encryption declared false"   '[[ "$(/usr/libexec/PlistBuddy -c "Print :ITSAppUsesNonExemptEncryption" "$PLIST")" == false ]]'
check "icon is named"              '[[ "$(/usr/libexec/PlistBuddy -c "Print :CFBundleIconName" "$PLIST")" == AppIcon ]]'
check "catalog targets the app's system" 'grep -q -- "--minimum-deployment-target 14.0" "$OUT/work/actool.log"'
check "stale identifier replaced"   '! grep -q STALE "$OUT/work/signing.entitlements"'
check "trial drops the old profile" '[[ ! -e "$OUT/Demo.app/Contents/embedded.provisionprofile" ]]'
check "identifiers in entitlements" 'grep -q "ABCDE12345.io.example.demo" "$OUT/work/signing.entitlements"'
check "source app is untouched"     '[[ "$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$APP/Contents/Info.plist")" == 1 ]]'
check "package exists"              '[[ -f "$OUT/Demo.pkg" ]]'
check "no file is quarantined"      '[[ -z "$(xattr -r "$OUT/Demo.app" | grep com.apple.quarantine || true)" ]]'
check "upload of a trial refused"   '! TRIAL=1 UPLOAD=1 BUILD_NUMBER=1 TEAM_ID=X scripts/package-appstore.sh "$APP" "$DIR/app.entitlements" a.b 2>/dev/null'
/usr/libexec/PlistBuddy -c "Delete :LSMinimumSystemVersion" "$APP/Contents/Info.plist"
check "validating a trial refused" '! TRIAL=1 VALIDATE=1 BUILD_NUMBER=1 TEAM_ID=X scripts/package-appstore.sh "$APP" "$DIR/app.entitlements" a.b 2>/dev/null'
check "missing system version refused" '! TRIAL=1 BUILD_NUMBER=1 TEAM_ID=X scripts/package-appstore.sh "$APP" "$DIR/app.entitlements" a.b 2>/dev/null'
echo "package-appstore: all checks passed"
