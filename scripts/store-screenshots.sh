#!/usr/bin/env bash
# Makes an app's App Store screenshots by running its StoreScreenshots UI tests on a fresh iPhone and iPad simulator.
# Specified in docs/specs/store-screenshots. A failure leaves the output folder as it was.
#
# Usage: store-screenshots.sh <project> <scheme> <out-dir>
#
# UI_TESTS       the UI test target (default: the scheme's name up to its first hyphen, plus "UITests")
# IPHONE_MODEL   the iPhone simulator (default "iPhone 18 Pro", 1206x2622)
# IPAD_MODEL     the iPad simulator (default "iPad Pro 13-inch (M5)", 2064x2752)
set -euo pipefail

PROJECT="${1:-}"
SCHEME="${2:-}"
OUT_DIR="${3:-}"
UI_TESTS="${UI_TESTS:-${SCHEME%%-*}UITests}"
CLONE=""

fail() { echo "store-screenshots failed: $1" >&2; exit 1; }

[[ -n "$PROJECT" && -n "$SCHEME" && -n "$OUT_DIR" ]] || fail "usage: store-screenshots.sh <project> <scheme> <out-dir>"
WORK_DIR="$(mktemp -d)"

cleanup() {
    [[ -z "$CLONE" ]] || xcrun simctl delete "$CLONE" > /dev/null 2>&1 || true
    rm -rf "$WORK_DIR"
}
trap cleanup EXIT

main() {
    shoot iphone "${IPHONE_MODEL:-iPhone 18 Pro}" 1206 2622
    shoot ipad "${IPAD_MODEL:-iPad Pro 13-inch (M5)}" 2064 2752
    mkdir -p "$OUT_DIR"
    rm -f "$OUT_DIR"/iphone-*.png "$OUT_DIR"/ipad-*.png
    cp "$WORK_DIR"/final/*.png "$OUT_DIR"/
}

# Usage: shoot <prefix> <model> <width> <height>
shoot() {
    local pictures="$WORK_DIR/$1" source
    mkdir -p "$pictures" "$WORK_DIR/final"
    source="$(simulator_id "$2")"
    [[ -n "$source" ]] || fail "no simulator named $2 is installed"
    CLONE="$(xcrun simctl clone "$source" "Store screenshots $1 $$")"
    prepare_clone
    run_tests "$pictures" "$WORK_DIR/$1.log" || { report_failure "$WORK_DIR/$1.log"; fail "the $1 UI tests failed"; }
    xcrun simctl delete "$CLONE"
    CLONE=""
    collect "$1" "$3" "$4"
}

# Usage: simulator_id <model>; the exact name on the newest runtime, which simctl lists last.
simulator_id() {
    xcrun simctl list devices available \
        | sed -nE 's/^ *(.*) \(([0-9A-F-]{36})\) \(.*$/\1|\2/p' \
        | awk -F'|' -v name="$1" '$1 == name { id = $2 } END { print id }'
}

prepare_clone() {
    xcrun simctl erase "$CLONE"
    xcrun simctl bootstatus "$CLONE" -b > /dev/null
    xcrun simctl status_bar "$CLONE" override --time 9:41 --dataNetwork wifi --wifiMode active --wifiBars 3 \
        --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100
}

# Usage: run_tests <pictures-folder> <log-file>
run_tests() {
    TEST_RUNNER_SCREENSHOT_DIR="$1" xcodebuild test -project "$PROJECT" -scheme "$SCHEME" \
        -destination "platform=iOS Simulator,id=$CLONE" -only-testing:"$UI_TESTS/StoreScreenshots" \
        -derivedDataPath "$WORK_DIR/build" -skipPackageUpdates > "$2" 2>&1
}

# Usage: report_failure <log-file>; xcodebuild's log leaves out why a test failed, which the result bundle has.
report_failure() {
    local result
    tail -n 20 "$1" >&2
    result="$(find "$WORK_DIR/build/Logs/Test" -name '*.xcresult' -maxdepth 1 2> /dev/null | tail -n 1)"
    [[ -z "$result" ]] || xcrun xcresulttool get test-results summary --path "$result" >&2 || true
}

# Usage: collect <prefix> <width> <height>
collect() {
    local file count=0
    for file in "$WORK_DIR/$1"/*.png; do
        [[ -f "$file" ]] || fail "the $1 UI tests saved no pictures"
        check_size "$file" "$2" "$3"
        cp "$file" "$WORK_DIR/final/$1-$(basename "$file")"
        count=$((count + 1))
    done
    echo "$1: $count pictures"
}

# Usage: check_size <file> <width> <height>
check_size() {
    local width height
    width="$(sips -g pixelWidth "$1" | awk '/pixelWidth/ { print $2 }')"
    height="$(sips -g pixelHeight "$1" | awk '/pixelHeight/ { print $2 }')"
    [[ "$width" == "$2" && "$height" == "$3" ]] || fail "$(basename "$1") is ${width}x$height, not $2x$3"
}

main
