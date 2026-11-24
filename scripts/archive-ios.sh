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
# ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_FILE   when all are set, sign by hand with the keychain's Apple Distribution
#                identity and an App Store profile per bundle identifier, which ios-store-profiles.rb finds or makes
#                with this App Store Connect API key. Otherwise Xcode signs automatically with the account it's signed
#                in to, which can make it create a development certificate.
# STORE_PROFILES  stands in for ios-store-profiles.rb in tests
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
OPTIONS="$OUT/ExportOptions.plist"
SCRIPTS="$(dirname "$0")"
PROFILE_PREFIX="Tableside App Store "
DISTRIBUTION="Apple Distribution"

# The bundle identifiers of the project's iOS apps and app extensions, which are what gets signed.
bundle_ids() {
    # shellcheck disable=SC2016  # The Ruby program is meant to be literal.
    xcodebuild -showBuildSettings -json -project "$PROJECT" -alltargets -configuration Release -sdk iphoneos \
        2>/dev/null | ruby -rjson -e '
            signed = %w[com.apple.product-type.application com.apple.product-type.app-extension]
            settings = JSON.parse($stdin.read).map { |target| target["buildSettings"] }
            puts settings.select { |s| signed.include?(s["PRODUCT_TYPE"]) }
                         .map { |s| s["PRODUCT_BUNDLE_IDENTIFIER"] }.uniq'
}

# Manual signing creates nothing: no certificate, and no profile beyond the named ones. The profile is chosen per
# target from its wrapper, so Swift package targets, which take no profile, are left without one.
manual_signing() {
    local ids=()
    [[ -f "$ASC_KEY_FILE" ]] || fail "there is no key file at $ASC_KEY_FILE"
    read -r -a ids <<< "$(bundle_ids | tr '\n' ' ')"
    [[ ${#ids[@]} -gt 0 ]] || fail "$PROJECT has no iOS app to sign"
    "${STORE_PROFILES:-$SCRIPTS/ios-store-profiles.rb}" "$PROFILE_PREFIX" "${ids[@]}" >&2
    cat > "$OUT/Signing.xcconfig" <<XCCONFIG
CODE_SIGN_STYLE = Manual
CODE_SIGN_IDENTITY = $DISTRIBUTION
STORE_PROFILE_app = $PROFILE_PREFIX\$(PRODUCT_BUNDLE_IDENTIFIER)
STORE_PROFILE_appex = \$(STORE_PROFILE_app)
PROVISIONING_PROFILE_SPECIFIER = \$(STORE_PROFILE_\$(WRAPPER_EXTENSION))
XCCONFIG
    SIGNING=(-xcconfig "$OUT/Signing.xcconfig")
    EXPORT_SIGNING=()
    write_options manual "$(profiles_entry "${ids[@]}")"
}

automatic_signing() {
    SIGNING=(-allowProvisioningUpdates)
    EXPORT_SIGNING=(-allowProvisioningUpdates)
    write_options automatic ""
}

profiles_entry() {
    local id
    printf '<key>signingCertificate</key><string>%s</string>\n<key>provisioningProfiles</key><dict>\n' "$DISTRIBUTION"
    for id in "$@"; do printf '<key>%s</key><string>%s%s</string>\n' "$id" "$PROFILE_PREFIX" "$id"; done
    printf '</dict>\n'
}

write_options() {
    cat > "$OPTIONS" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>method</key><string>app-store-connect</string>
<key>destination</key><string>export</string>
<key>signingStyle</key><string>$1</string>
$2</dict></plist>
PLIST
}

archive() {
    # The two settings on the command line win over the app's Version.xcconfig.
    xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release -destination 'generic/platform=iOS' \
        -archivePath "$ARCHIVE" "${SIGNING[@]}" MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
        archive -quiet
}

export_ipa() {
    xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$EXPORT" -exportOptionsPlist "$OPTIONS" \
        ${EXPORT_SIGNING[@]+"${EXPORT_SIGNING[@]}"} -quiet
}

mkdir -p "$OUT"
rm -rf "$ARCHIVE" "$EXPORT"
if [[ -n "${ASC_KEY_ID:-}" && -n "${ASC_ISSUER_ID:-}" && -n "${ASC_KEY_FILE:-}" ]]; then
    manual_signing
else
    automatic_signing
fi
archive
export_ipa
IPA="$(find "$EXPORT" -maxdepth 1 -name '*.ipa' | head -n 1)"
[[ -n "$IPA" ]] || fail "exporting $ARCHIVE gave no .ipa"
"$SCRIPTS/record-build-source.sh" "$IPA" "$VERSION" "$BUILD_NUMBER"
echo "Archived $SCHEME $VERSION, build $BUILD_NUMBER" >&2
echo "$IPA"
