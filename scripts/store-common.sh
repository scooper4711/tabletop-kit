#!/usr/bin/env bash
# Shared by store-listing.sh and testflight.sh: finds fastlane and hands it the App Store Connect API key.
# Specified in docs/specs/store-listing. Source it after setting SCRIPT, the name failures start with.
#
# ASC_KEY_ID, ASC_ISSUER_ID   the App Store Connect API key's ID and its issuer
# ASC_KEY_FILE                path to the key's .p8 file
# FASTLANE                    the fastlane to run (default: the one on PATH)

fail() { echo "$SCRIPT: $*" >&2; exit 1; }

# Sets FASTLANE, or stops when there is none.
require_fastlane() {
    FASTLANE="${FASTLANE:-$(command -v fastlane || true)}"
    [[ -n "$FASTLANE" ]] || fail "fastlane is not installed (brew install fastlane)"
}

# Writes the key in the form fastlane reads and sets API_KEY_JSON to it. It is in WORK_DIR, a scratch folder that is
# removed however the script ends.
write_api_key() {
    [[ -n "${ASC_KEY_ID:-}" && -n "${ASC_ISSUER_ID:-}" && -n "${ASC_KEY_FILE:-}" ]] \
        || fail "ASC_KEY_ID, ASC_ISSUER_ID and ASC_KEY_FILE must name the App Store Connect API key"
    [[ -f "$ASC_KEY_FILE" ]] || fail "there is no key file at $ASC_KEY_FILE"
    WORK_DIR="$(mktemp -d)"
    trap 'rm -rf "$WORK_DIR"' EXIT
    API_KEY_JSON="$WORK_DIR/api-key.json"
    # A .p8 is base64 text between two marker lines, so only its line ends need escaping.
    printf '{"key_id": "%s", "issuer_id": "%s", "key": "%s"}\n' "$ASC_KEY_ID" "$ASC_ISSUER_ID" \
        "$(awk '{ printf "%s\\n", $0 }' "$ASC_KEY_FILE")" > "$API_KEY_JSON"
}
