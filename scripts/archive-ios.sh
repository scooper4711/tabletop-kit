#!/usr/bin/env bash
# Archives an app's iOS target and exports the .ipa for App Store Connect. Specified in docs/specs/store-listing.
# Run it from the app's repository; the last line it prints is the .ipa's path.
#
# Usage: archive-ios.sh <project> <scheme> <out-dir>
#   <project>   the Xcode project, such as ios/Pluck.xcodeproj
#   <scheme>    the scheme of the iOS app
#   <out-dir>   gets <scheme>.xcarchive and export/<app>.ipa; both are replaced
#
# VERSION        version of the build (default: scripts/version.sh marketing)
# BUILD_NUMBER   build number, which must grow with every upload (default: scripts/version.sh build)
# ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_FILE   when all are set, sign with this App Store Connect API key, not
#                with the account Xcode is signed in to
set -euo pipefail

fail() { echo "archive-ios: $*" >&2; exit 1; }

PROJECT="${1:-}"
SCHEME="${2:-}"
OUT="${3:-}"
[[ -n "$PROJECT" && -n "$SCHEME" && -n "$OUT" ]] || fail "usage: archive-ios.sh <project> <scheme> <out-dir>"
VERSION="${VERSION:-$(scripts/version.sh marketing)}"
BUILD_NUMBER="${BUILD_NUMBER:-$(scripts/version.sh build)}"
ARCHIVE="$OUT/$SCHEME.xcarchive"
EXPORT="$OUT/export"

SIGNING=(-allowProvisioningUpdates)
if [[ -n "${ASC_KEY_ID:-}" && -n "${ASC_ISSUER_ID:-}" && -n "${ASC_KEY_FILE:-}" ]]; then
    [[ -f "$ASC_KEY_FILE" ]] || fail "there is no key file at $ASC_KEY_FILE"
    # xcodebuild wants the key's full path.
    KEY_FILE="$(cd "$(dirname "$ASC_KEY_FILE")" && pwd)/$(basename "$ASC_KEY_FILE")"
    SIGNING+=(-authenticationKeyPath "$KEY_FILE" -authenticationKeyID "$ASC_KEY_ID"
        -authenticationKeyIssuerID "$ASC_ISSUER_ID")
fi

archive() {
    # The two settings on the command line win over the app's Version.xcconfig.
    xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release -destination 'generic/platform=iOS' \
        -archivePath "$ARCHIVE" "${SIGNING[@]}" MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
        archive -quiet
}

export_ipa() {
    cat > "$OUT/ExportOptions.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>method</key><string>app-store-connect</string>
<key>destination</key><string>export</string>
<key>signingStyle</key><string>automatic</string>
</dict></plist>
PLIST
    xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$EXPORT" \
        -exportOptionsPlist "$OUT/ExportOptions.plist" "${SIGNING[@]}" -quiet
}

mkdir -p "$OUT"
rm -rf "$ARCHIVE" "$EXPORT"
archive
export_ipa
IPA="$(find "$EXPORT" -maxdepth 1 -name '*.ipa' | head -n 1)"
[[ -n "$IPA" ]] || fail "exporting $ARCHIVE gave no .ipa"
"$(dirname "$0")/record-build-source.sh" "$IPA" "$VERSION" "$BUILD_NUMBER"
echo "Archived $SCHEME $VERSION, build $BUILD_NUMBER" >&2
echo "$IPA"
