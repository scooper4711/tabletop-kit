#!/usr/bin/env bash
# Takes a Mac App Store screenshot of a built app: launches it with its demo arguments, sizes its window to
# 1440x900, saves a picture of the window, and quits the app. Specified in docs/specs/store-screenshots.
# It needs a desktop session, Screen Recording and Accessibility for the terminal, so it runs on a Mac someone
# is logged in to, never on the CI mini. The app must not be running already.
#
# Usage: store-screenshots-mac.sh <app-bundle> <out-file.png> [launch-argument...]
#
# BEFORE_CAPTURE  a file of AppleScript to run in System Events, with the app's process as `appProcess`, after the
#                 window is sized and before it is captured (to open a panel, pick a menu item)
# (The app always launches in the light appearance, whatever the Mac is set to.)
# SETTLE_SECONDS  how long to wait after launching and after BEFORE_CAPTURE (default 6)
# LAUNCH_ENV     environment variables to give the app, as "NAME=value NAME=value" (no spaces in values)
# OPEN_FILE      a document to open with the app (a sheet, a map)
# CLICKS          mouse clicks to make after BEFORE_CAPTURE, as window-relative points "x,y x,y" (a real click,
#                 for what AppleScript can't reach, such as a SwiftUI grid)
# KEEP_RUNNING    set to 1 to leave the app open afterward, for a following shot of the same session
set -euo pipefail

APP="${1:-}"
OUT_FILE="${2:-}"
SETTLE="${SETTLE_SECONDS:-6}"

fail() { echo "store-screenshots-mac failed: $1" >&2; exit 1; }

main() {
    [[ -n "$APP" && -n "$OUT_FILE" ]] || fail "usage: store-screenshots-mac.sh <app-bundle> <out-file.png> [args]"
    [[ -d "$APP" ]] || fail "$APP is not an app bundle"
    local process executable
    executable="$(plutil -extract CFBundleExecutable raw "$APP/Contents/Info.plist")"
    process="$(basename "$APP" .app)"
    ! pgrep -x "$executable" > /dev/null || fail "$process is already running; quit it first"
    shift 2
    local environment=() pair
    for pair in ${LAUNCH_ENV:-}; do environment+=(--env "$pair"); done
    local bundle documents=()
    bundle="$(cd "$(dirname "$APP")" && pwd)/$(basename "$APP")"
    [[ -z "${OPEN_FILE:-}" ]] || documents+=("$OPEN_FILE")
    open -a "$bundle" ${documents[@]+"${documents[@]}"} ${environment[@]+"${environment[@]}"} \
        --args -NSRequiresAquaSystemAppearance YES "$@"
    sleep "$SETTLE"
    size_window "$process"
    [[ -z "${BEFORE_CAPTURE:-}" ]] || run_before_capture "$process"
    click_all
    park_mouse
    capture "$process"
    [[ "${KEEP_RUNNING:-0}" == 1 ]] || osascript -e "tell application \"$process\" to quit"
}

# Usage: size_window <process>; puts the frontmost window at a fixed place, 1440x900.
size_window() {
    osascript > /dev/null 2>&1 <<APPLESCRIPT || fail "sizing $1's window failed: allow Accessibility for this terminal"
tell application "System Events" to tell process "$1"
    set frontmost to true
    set position of window 1 to {300, 60}
    set size of window 1 to {1440, 900}
end tell
APPLESCRIPT
    sleep 2
}

# Usage: run_before_capture <process>
run_before_capture() {
    [[ -f "$BEFORE_CAPTURE" ]] || fail "BEFORE_CAPTURE file $BEFORE_CAPTURE not found"
    { echo "tell application \"System Events\" to tell process \"$1\""; echo "set appProcess to it"; \
      cat "$BEFORE_CAPTURE"; echo "end tell"; } | osascript > /dev/null || fail "running $BEFORE_CAPTURE failed"
    sleep "$SETTLE"
}

# Clicks each point of CLICKS, one second apart, on the window that size_window placed at 300,60.
click_all() {
    local point
    for point in ${CLICKS:-}; do
        osascript -l JavaScript - "$((300 + ${point%,*}))" "$((60 + ${point#*,}))" <<'JAVASCRIPT'
ObjC.import('CoreGraphics');
function run(argv) {
    const at = $.CGPointMake(Number(argv[0]), Number(argv[1]));
    for (const type of [$.kCGEventLeftMouseDown, $.kCGEventLeftMouseUp]) {
        $.CGEventPost($.kCGHIDEventTap, $.CGEventCreateMouseEvent($(), type, at, $.kCGMouseButtonLeft));
    }
}
JAVASCRIPT
        sleep 1
    done
    [[ -z "${CLICKS:-}" ]] || sleep "$SETTLE"
}

# Moves the pointer off the window, so no control looks hovered.
park_mouse() {
    osascript -l JavaScript > /dev/null <<'JAVASCRIPT'
ObjC.import('CoreGraphics');
$.CGWarpMouseCursorPosition($.CGPointMake(60, 600));
JAVASCRIPT
    sleep 1
}

# Usage: capture <process>; saves the app's largest window, without a shadow.
capture() {
    local id
    id="$(window_id "$1")"
    [[ -n "$id" ]] || fail "$1 has no window on screen: allow Screen Recording for this terminal"
    mkdir -p "$(dirname "$OUT_FILE")"
    screencapture -x -o -l "$id" "$OUT_FILE" || fail "capturing $1's window failed"
}

# Usage: window_id <process>; the id of the window sized to 1440x900, else the app's biggest window on screen.
window_id() {
    osascript -l JavaScript - "$1" <<'JAVASCRIPT'
ObjC.import('CoreGraphics');
function run(argv) {
    const info = $.CGWindowListCopyWindowInfo($.kCGWindowListOptionOnScreenOnly, 0);
    const list = ObjC.deepUnwrap(ObjC.castRefToObject(info));
    const mine = list.filter(w => w.kCGWindowOwnerName === argv[0] && w.kCGWindowLayer === 0);
    const sized = mine.filter(w => w.kCGWindowBounds.Width === 1440 && w.kCGWindowBounds.Height === 900);
    const wanted = sized.length ? sized : mine;
    wanted.sort((a, b) => b.kCGWindowBounds.Width * b.kCGWindowBounds.Height
                        - a.kCGWindowBounds.Width * a.kCGWindowBounds.Height);
    return wanted.length ? String(wanted[0].kCGWindowNumber) : '';
}
JAVASCRIPT
}

main "$@"
