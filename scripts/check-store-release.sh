#!/usr/bin/env bash
# Guards an App Store build. Specified in docs/specs/app-store-pipeline. Run it from the app's repository.
#
# Usage: check-store-release.sh source             before building: clean, an open version, on the branch that builds
#        check-store-release.sh package <bundle-id>  after building: universal, signed, this build number
#
# REQUIRE_ICLOUD=1   the signed app must also carry the iCloud entitlements for the Production environment
set -euo pipefail

OUT=build/appstore

fail() { echo "check-store-release: $*" >&2; exit 1; }

# Whether HEAD is on the given branch of origin. A branch that doesn't exist counts as no.
head_is_on() { git merge-base --is-ancestor HEAD "$1" 2>/dev/null; }

# R2: main builds a version until it goes to App Review. From then on only its release branch does, since a build
# number is the commit count and a fix on the branch counts lower than main.
check_source() {
    local version head in_review
    [[ -z "$(git status --porcelain)" ]] || fail "the working tree has changes"
    version="$(scripts/version.sh marketing)"
    head="$(git rev-parse --short HEAD)"
    if git rev-parse --quiet --verify "refs/tags/v$version" > /dev/null; then
        fail "version $version is closed: v$version marks the build Apple accepted, so raise VERSION first"
    fi
    in_review="$(git for-each-ref --format='%(refname:short)' refs/remotes/origin/release | paste -sd' ' -)"
    if [[ -z "$in_review" ]]; then
        head_is_on origin/main || fail "$head is not on origin/main"
    else
        head_is_on "origin/release/$version" \
            || fail "$head is not on origin/release/$version, and nothing else may build while $in_review exists"
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
