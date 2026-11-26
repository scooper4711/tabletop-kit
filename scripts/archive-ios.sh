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

# Usage: bundle_ids <scheme-settings>; the bundle identifiers to sign, one per line: the scheme's app, then the
# project's app extensions whose identifiers start with the app's, as Apple requires of the extensions an app embeds.
# A scheme's own settings leave those out.
bundle_ids() {
    local app
    app="$(product_ids application <<< "$1")" || return 1
    [[ -n "$app" ]] || return 1
    echo "$app"
    settings_json -alltargets -sdk iphoneos | product_ids app-extension "$app." || return 1
}

settings_json() {
    xcodebuild -showBuildSettings -json -project "$PROJECT" -configuration Release "$@"
}

# The development team of the app in the JSON settings on stdin; nothing when the app has none.
app_team() {
    # shellcheck disable=SC2016  # The Ruby program is meant to be literal.
    ruby -rjson -e '
        apps = JSON.parse($stdin.read).map { |target| target["buildSettings"] }
                   .select { |s| s["PRODUCT_TYPE"] == "com.apple.product-type.application" }
        puts apps.map { |s| s["DEVELOPMENT_TEAM"].to_s }.reject(&:empty?).first.to_s'
}

# Usage: product_ids <product-type> [<prefix>]; the bundle identifiers of that type in the JSON settings on stdin.
product_ids() {
    # shellcheck disable=SC2016  # The Ruby program is meant to be literal.
    ruby -rjson -e '
        type, prefix = "com.apple.product-type.#{ARGV[0]}", ARGV[1].to_s
        ids = JSON.parse($stdin.read).map { |target| target["buildSettings"] }
                  .select { |s| s["PRODUCT_TYPE"] == type }.map { |s| s["PRODUCT_BUNDLE_IDENTIFIER"] }
        puts ids.select { |id| id.start_with?(prefix) }.uniq' "$@"
}

# Manual signing creates nothing: no certificate, and no profile beyond the named ones. The profile is chosen per
# target from its wrapper, so Swift package targets, which take no profile, are left without one. The team is the
# app's, for every target: a Swift package's resource bundle inherits none from the project, and signing by hand
# wants one.
manual_signing() {
    local ids=() settings listed team
    [[ -f "$ASC_KEY_FILE" ]] || fail "there is no key file at $ASC_KEY_FILE"
    settings="$(settings_json -scheme "$SCHEME" -destination 'generic/platform=iOS')" \
        || fail "couldn't read the bundle identifiers of $SCHEME in $PROJECT"
    listed="$(bundle_ids "$settings")" || fail "couldn't read the bundle identifiers of $SCHEME in $PROJECT"
    team="$(app_team <<< "$settings")" || fail "couldn't read the development team of $SCHEME in $PROJECT"
    [[ -n "$team" ]] || fail "the app of $SCHEME in $PROJECT has no DEVELOPMENT_TEAM"
    read -r -a ids <<< "$(tr '\n' ' ' <<< "$listed")"
    # CI exports PROVISIONING_PROFILE, the Mac App Store profile, and xcodebuild reads the environment as build
    # settings. Manual signing would apply it to every target.
    unset PROVISIONING_PROFILE
    "${STORE_PROFILES:-$SCRIPTS/ios-store-profiles.rb}" "$PROFILE_PREFIX" "${ids[@]}" >&2
    cat > "$OUT/Signing.xcconfig" <<XCCONFIG
CODE_SIGN_STYLE = Manual
CODE_SIGN_IDENTITY = $DISTRIBUTION
DEVELOPMENT_TEAM = $team
PROVISIONING_PROFILE =
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
