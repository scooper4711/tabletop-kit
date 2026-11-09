#!/usr/bin/env bash
# Turns a built Tableside Toolkit app into a Mac App Store installer package, and optionally uploads it.
# Specified in docs/specs/appstore-build.
#
# Usage: package-appstore.sh <app> <entitlements> <bundle-id>
#   <app>           the built bundle, such as build/Pluck.app (left untouched; a copy is packaged)
#   <entitlements>  the entitlements for this channel with the team ID already filled in; an app whose App Store
#                   build needs fewer or more than its disk image (no Downloads folder, iCloud) passes its own file
#   <bundle-id>     for the application identifier entitlement
#
# BUILD_NUMBER           must increase with every upload (required)
# TEAM_ID                the developer team (required)
# PROVISIONING_PROFILE   path to the Mac App Store provisioning profile
# APP_SIGNING_IDENTITY   "Apple Distribution: …" (or its hash)
# INSTALLER_IDENTITY     "3rd Party Mac Developer Installer: …" (or "Mac Installer Distribution: …")
# TRIAL=1                sign ad hoc and leave the package unsigned, to check the rest; it can't be uploaded
# UPLOAD=1               validate and upload with ASC_KEY_ID, ASC_ISSUER_ID and ASC_KEY_FILE
set -euo pipefail

APP_SOURCE="${1:?app bundle}"
ENTITLEMENTS_SOURCE="${2:?entitlements}"
BUNDLE_ID="${3:?bundle id}"
: "${BUILD_NUMBER:?BUILD_NUMBER must increase with every upload}"
: "${TEAM_ID:?TEAM_ID is the developer team}"
TRIAL="${TRIAL:-0}"

fail() { echo "package-appstore: $*" >&2; exit 1; }

if [[ "$TRIAL" != "1" ]]; then
    [[ -f "${PROVISIONING_PROFILE:-}" ]] || fail "PROVISIONING_PROFILE must name the Mac App Store profile"
    : "${APP_SIGNING_IDENTITY:?APP_SIGNING_IDENTITY is the Apple Distribution identity}"
    : "${INSTALLER_IDENTITY:?INSTALLER_IDENTITY is the Mac Installer Distribution identity}"
fi
[[ "${UPLOAD:-0}" != "1" || "$TRIAL" != "1" ]] || fail "a trial package can't be uploaded"

# Absolute: actool resolves relative paths against a directory of its own, not the current one.
OUT="$(cd "$(dirname "$APP_SOURCE")" && pwd)/appstore"
APP="$OUT/$(basename "$APP_SOURCE")"
WORK="$OUT/work"
rm -rf "$OUT"
mkdir -p "$WORK"
ditto "$APP_SOURCE" "$APP"
RESOURCES="$APP/Contents/Resources"
INFO_PLIST="$APP/Contents/Info.plist"

# The asset catalog is compiled for the system the app itself says it needs.
deployment_target() {
    /usr/libexec/PlistBuddy -c "Print :LSMinimumSystemVersion" "$INFO_PLIST" 2>/dev/null \
        || fail "$INFO_PLIST has no LSMinimumSystemVersion"
}

compile_icon() {
    local icns="$RESOURCES/AppIcon.icns"
    [[ -f "$icns" ]] || fail "$icns is missing"
    local catalog="$WORK/Icons.xcassets" target
    target="$(deployment_target)"
    local iconset="$catalog/AppIcon.appiconset"
    mkdir -p "$catalog"
    iconutil -c iconset "$icns" -o "$WORK/AppIcon.iconset"
    mkdir -p "$iconset"
    cp "$WORK"/AppIcon.iconset/*.png "$iconset/"
    write_icon_catalog "$iconset"
    echo '{"info":{"version":1,"author":"xcode"}}' > "$catalog/Contents.json"
    echo "actool --minimum-deployment-target $target" >"$WORK/actool.log"
    xcrun actool "$catalog" --compile "$RESOURCES" --platform macosx --minimum-deployment-target "$target" \
        --app-icon AppIcon --output-partial-info-plist "$WORK/partial.plist" >>"$WORK/actool.log" 2>&1 || true
    # actool exits 0 when it fails, so look for what it should have written.
    [[ -f "$RESOURCES/Assets.car" ]] || { cat "$WORK/actool.log" >&2; fail "actool didn't compile the icon"; }
    name_icon
}

# App Store Connect wants CFBundleIconName (ITMS-90236), which actool reports in its partial Info.plist.
name_icon() {
    local name
    name="$(/usr/libexec/PlistBuddy -c "Print :CFBundleIconName" "$WORK/partial.plist" 2>/dev/null)" \
        || fail "actool didn't name the icon in $WORK/partial.plist"
    set_plist_key CFBundleIconName string "$name"
}

# Usage: set_plist_key <key> <type> <value> [plist]; replaces the key when it is already there.
set_plist_key() {
    local plist="${4:-$INFO_PLIST}"
    /usr/libexec/PlistBuddy -c "Delete :$1" "$plist" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Add :$1 $2 $3" "$plist"
}

# Lists the iconutil sizes (icon_16x16.png, icon_16x16@2x.png, …) the way an appiconset's Contents.json wants them.
write_icon_catalog() {
    local iconset="$1" images="" file size scale
    for file in "$iconset"/icon_*.png; do
        file="$(basename "$file")"
        size="${file#icon_}"; size="${size%%[@.]*}"
        scale="1x"; [[ "$file" == *@2x.png ]] && scale="2x"
        images+="{\"filename\":\"$file\",\"idiom\":\"mac\",\"scale\":\"$scale\",\"size\":\"$size\"},"
    done
    echo "{\"images\":[${images%,}],\"info\":{\"version\":1,\"author\":\"xcode\"}}" > "$iconset/Contents.json"
}

set_plist_keys() {
    set_plist_key CFBundleVersion string "$BUILD_NUMBER"
    set_plist_key ITSAppUsesNonExemptEncryption bool false
}

write_entitlements() {
    local file="$WORK/signing.entitlements"
    cp "$ENTITLEMENTS_SOURCE" "$file"
    # Replaced rather than added: entitlements that already carry iCloud name both identifiers themselves.
    set_plist_key com.apple.application-identifier string "$TEAM_ID.$BUNDLE_ID" "$file"
    set_plist_key com.apple.developer.team-identifier string "$TEAM_ID" "$file"
    echo "$file"
}

sign_and_package() {
    local entitlements="$1" name pkg
    name="$(basename "$APP" .app)"
    pkg="$OUT/$name.pkg"
    if [[ "$TRIAL" == "1" ]]; then
        # An ad hoc signature can't carry the application identifier, which only a profile can approve; a
        # profile the disk image build embedded would not match it either.
        rm -f "$APP/Contents/embedded.provisionprofile"
        codesign --force --sign - "$APP"
        productbuild --component "$APP" /Applications "$pkg" >&2
    else
        cp "$PROVISIONING_PROFILE" "$APP/Contents/embedded.provisionprofile"
        codesign --force --sign "$APP_SIGNING_IDENTITY" --options runtime --entitlements "$entitlements" "$APP"
        productbuild --component "$APP" /Applications --sign "$INSTALLER_IDENTITY" "$pkg" >&2
    fi
    echo "$pkg"
}

upload() {
    : "${ASC_KEY_ID:?}" "${ASC_ISSUER_ID:?}" "${ASC_KEY_FILE:?}"
    # altool looks for AuthKey_<id>.p8 in ./private_keys among other places.
    mkdir -p "$WORK/private_keys"
    cp "$ASC_KEY_FILE" "$WORK/private_keys/AuthKey_$ASC_KEY_ID.p8"
    (cd "$WORK" && API_PRIVATE_KEYS_DIR="$WORK/private_keys" \
        xcrun altool --validate-app -f "$1" -t macos --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID" \
        && API_PRIVATE_KEYS_DIR="$WORK/private_keys" \
        xcrun altool --upload-package "$1" -t macos --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID")
}

compile_icon
set_plist_keys
PKG="$(sign_and_package "$(write_entitlements)")"
echo "Packaged $PKG (build $BUILD_NUMBER)"
[[ "${UPLOAD:-0}" != "1" ]] || upload "$PKG"
