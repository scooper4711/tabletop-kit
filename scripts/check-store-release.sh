#!/usr/bin/env bash
# Guards an App Store build. Specified in docs/specs/app-store-pipeline. Run it from the app's repository.
#
# Usage: check-store-release.sh source             before building: the commit is on main, clean, and matches any tag
#        check-store-release.sh package <bundle-id>  after building: universal, signed, this build number
#
# REQUIRE_ICLOUD=1   the signed app must also carry the iCloud entitlements for the Production environment
set -euo pipefail

OUT=build/appstore

fail() { echo "check-store-release: $*" >&2; exit 1; }

check_source() {
    git merge-base --is-ancestor HEAD origin/main || fail "$(git rev-parse --short HEAD) is not on origin/main"
    [[ -z "$(git status --porcelain)" ]] || fail "the working tree has changes"
    if [[ "${GITHUB_REF_TYPE:-}" == tag ]]; then
        [[ "${GITHUB_REF_NAME:-}" == "v$(scripts/version.sh marketing)" ]] \
            || fail "tag ${GITHUB_REF_NAME:-} doesn't match version $(scripts/version.sh marketing)"
    fi
}

only_match() {
    local matches=("$OUT"/*"$1")
    [[ ${#matches[@]} -eq 1 && -e "${matches[0]}" ]] || fail "expected one $1 in $OUT"
    printf '%s' "${matches[0]}"
}

check_icloud() {
    local entitlements="$1"
    grep -q 'com.apple.developer.icloud-container-identifiers' <<< "$entitlements" \
        || fail "the app has no iCloud container, so it wouldn't sync"
    if grep -q '<string>Development</string>' <<< "$entitlements"; then
        fail "the app is signed for the Development iCloud environment"
    fi
}

check_package() {
    local bundle_id="${1:-}" app pkg info build executable archs entitlements
    [[ -n "$bundle_id" ]] || fail "usage: check-store-release.sh package <bundle-id>"
    app="$(only_match .app)"
    pkg="$(only_match .pkg)"
    info="$app/Contents/Info.plist"
    build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$info")"
    [[ "$build" == "$(scripts/version.sh build)" ]] || fail "the package has build $build"
    executable="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$info")"
    archs="$(lipo -archs "$app/Contents/MacOS/$executable")"
    [[ "$archs" == *arm64* && "$archs" == *x86_64* ]] || fail "the app isn't universal: $archs"
    codesign --verify --strict "$app" || fail "the app's signature is invalid"
    entitlements="$(codesign -d --entitlements - --xml "$app" 2>/dev/null)"
    grep -q "$bundle_id" <<< "$entitlements" || fail "the app's entitlements don't name $bundle_id"
    [[ "${REQUIRE_ICLOUD:-0}" != "1" ]] || check_icloud "$entitlements"
    pkgutil --check-signature "$pkg" | grep -q 'signed' || fail "the package isn't signed"
}

case "${1:-}" in
    source) check_source ;;
    package) check_package "${2:-}" ;;
    *) fail "usage: check-store-release.sh source | package <bundle-id>" ;;
esac
