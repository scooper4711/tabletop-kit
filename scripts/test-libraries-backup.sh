#!/usr/bin/env bash
# Backs up and restores a made-up home folder and checks what backup-libraries.sh and restore-libraries.sh promise.
set -euo pipefail
cd "$(dirname "$0")/.."
DIR="$(mktemp -d)"; trap 'rm -rf "$DIR"' EXIT
export HOME="$DIR/home" TABLESIDE_BACKUP_ROOT="$DIR/backups"
# Stand-ins, so the test neither sees the apps really running nor restarts the real preferences daemon.
mkdir -p "$DIR/bin"
printf '#!/bin/sh\n' > "$DIR/bin/lsappinfo"
printf '#!/bin/sh\n' > "$DIR/bin/killall"
chmod +x "$DIR/bin/lsappinfo" "$DIR/bin/killall"
export PATH="$DIR/bin:$PATH"

APP="$HOME/Library/Containers/io.github.scooper4711.PawnShop/Data/Library"
NEW_APP="$HOME/Library/Containers/io.github.scooper4711.Turnkeeper/Data/Library"
GROUP="$HOME/Library/Group Containers/TEAM123456.io.github.scooper4711.tableside"
NEW_GROUP="$HOME/Library/Group Containers/group.io.github.scooper4711.tableside"
METADATA=".com.apple.containermanagerd.metadata.plist"

check() { if ! eval "$2"; then echo "FAIL: $1" >&2; exit 1; fi; }
write() { mkdir -p "$(dirname "$1")"; echo "$2" > "$1"; }
# What a test run does to the libraries: changes what was there and creates what wasn't.
run_pretend_test() {
  write "$GROUP/Tableside/Library.sqlite" "changed by the test"
  write "$APP/Preferences/app.plist" "changed by the test"
  write "$GROUP/Later/file.txt" "created by the test"
  write "$NEW_GROUP/Tableside/Library.sqlite" "created by the test"
  write "$NEW_APP/Application Support/data.json" "created by the test"
}

check "no backup folder is reported" \
  '[[ "$(scripts/restore-libraries.sh --yes 2>&1 || true)" == *"no backup with a manifest.tsv"* ]]'

write "$APP/Application Support/data.json" "app data"
write "$APP/Preferences/app.plist" "preferences"
write "$GROUP/Tableside/Library.sqlite" "shared library"
write "$GROUP/Tableside/Pictures/one.heic" "picture"
write "$GROUP/Scrollkeeper/library.json" "scrolls"
write "$GROUP/$METADATA" "system metadata"

# macOS keeps a terminal out of other apps' data until it is allowed in. A folder that can't be read mustn't be
# left out of a backup that calls itself complete.
chmod 000 "$GROUP"
check "an unreadable folder stops the backup" \
  '[[ "$(scripts/backup-libraries.sh locked 2>&1 || true)" == *"won'"'"'t let this terminal read"*"$GROUP"* ]]'
check "a stopped backup leaves no folder" '[[ ! -e "$TABLESIDE_BACKUP_ROOT" ]]'
chmod 700 "$GROUP"

scripts/backup-libraries.sh before-test > /dev/null
BACKUP="$(find "$TABLESIDE_BACKUP_ROOT" -mindepth 1 -maxdepth 1 -name '*-before-test')"
check "shared library is backed up" \
  '[[ "$(cat "$BACKUP/Group Containers/$(basename "$GROUP")/Tableside/Library.sqlite")" == "shared library" ]]'
check "container metadata is left out" '[[ -z "$(find "$BACKUP" -name "$METADATA")" ]]'
check "four folders are in the manifest" '[[ "$(wc -l < "$BACKUP/manifest.tsv" | tr -d " ")" == 4 ]]'

run_pretend_test
scripts/restore-libraries.sh --yes > /dev/null
REPLACED="$(find "$BACKUP" -mindepth 1 -maxdepth 1 -name 'replaced-*')"
check "shared library is restored"   '[[ "$(cat "$GROUP/Tableside/Library.sqlite")" == "shared library" ]]'
check "pictures are restored"        '[[ -f "$GROUP/Tableside/Pictures/one.heic" ]]'
check "preferences are restored"     '[[ "$(cat "$APP/Preferences/app.plist")" == "preferences" ]]'
check "app data is restored"         '[[ "$(cat "$APP/Application Support/data.json")" == "app data" ]]'
check "Scrollkeeper is restored"     '[[ "$(cat "$GROUP/Scrollkeeper/library.json")" == "scrolls" ]]'
check "container metadata stays"     '[[ "$(cat "$GROUP/$METADATA")" == "system metadata" ]]'
check "a folder made later is gone"  '[[ ! -e "$GROUP/Later" ]]'
check "a library made later is gone" '[[ ! -e "$NEW_GROUP/Tableside" ]]'
check "app data made later is gone"  '[[ ! -e "$NEW_APP/Application Support" ]]'
check "what was replaced is kept" \
  '[[ "$(cat "$REPLACED/Group Containers/$(basename "$GROUP")/Tableside/Library.sqlite")" == "changed by the test" ]]'
check "what was set aside is kept" \
  '[[ "$(cat "$REPLACED/Group Containers/$(basename "$GROUP")/Later/file.txt")" == "created by the test" ]]'
check "the backup can be restored again" \
  '[[ "$(cat "$BACKUP/Group Containers/$(basename "$GROUP")/Tableside/Library.sqlite")" == "shared library" ]]'

# A backup that was interrupted, or made before backups were complete, can't tell what was created after it.
rm "$BACKUP/complete"
run_pretend_test
sleep 1 # So this restore's `replaced-<time>` folder isn't the last one's.
scripts/restore-libraries.sh "$BACKUP" --yes > /dev/null
check "an incomplete backup still restores"       '[[ "$(cat "$GROUP/Tableside/Library.sqlite")" == "shared library" ]]'
check "an incomplete backup leaves later folders" '[[ -f "$GROUP/Later/file.txt" ]]'
# Nightly backups to another place: PDFs left out, unchanged files hard-linked to the last backup, old ones pruned.
REMOTE="$DIR/remote"
write "$GROUP/Scrollkeeper/Files/book.pdf" "a downloaded PDF"
write "$GROUP/Tableside/Sources/source.PDF" "a source PDF"
remote_backup() { TABLESIDE_BACKUP_SKIP_PDFS=1 TABLESIDE_BACKUP_REMOTE="$REMOTE" TABLESIDE_BACKUP_KEEP=2 \
  scripts/backup-libraries.sh "$1" > /dev/null; }
remote_backup night-1
FIRST="$(find "$REMOTE" -mindepth 1 -maxdepth 1 -name '*-night-1')"
check "the backup arrives"             '[[ -f "$FIRST/complete" && -f "$FIRST/manifest.tsv" ]]'
check "PDFs are left out"              '[[ -z "$(find "$FIRST" -iname "*.pdf")" && -f "$FIRST/pdfs-left-out" ]]'
check "the PDFs themselves stay"       '[[ -f "$GROUP/Scrollkeeper/Files/book.pdf" ]]'
check "the local copy is removed"      '[[ -z "$(find "$TABLESIDE_BACKUP_ROOT" -maxdepth 1 -name "*-night-1")" ]]'
write "$GROUP/Scrollkeeper/library.json" "changed overnight"
remote_backup night-2
SECOND="$(find "$REMOTE" -mindepth 1 -maxdepth 1 -name '*-night-2')"
LIBRARY="Group Containers/$(basename "$GROUP")/Tableside/Library.sqlite"
SCROLLS="Group Containers/$(basename "$GROUP")/Scrollkeeper/library.json"
check "unchanged files are hard links" '[[ "$(stat -f %i "$FIRST/$LIBRARY")" == "$(stat -f %i "$SECOND/$LIBRARY")" ]]'
check "changed files are new copies"   '[[ "$(cat "$SECOND/$SCROLLS")" == "changed overnight" ]]'
check "the older copy keeps its file"  '[[ "$(cat "$FIRST/$SCROLLS")" == "scrolls" ]]'
mkdir -p "$REMOTE/@eaDir"
remote_backup night-3
check "only the newest are kept"       '[[ "$(find "$REMOTE" -mindepth 1 -maxdepth 1 -type d -name "2*" | wc -l | tr -d " ")" == 2 ]]'
check "folders that aren't backups stay" '[[ -d "$REMOTE/@eaDir" ]]'
check "the oldest is the one removed"  '[[ ! -e "$FIRST" ]]'
check "no partial backup is left"      '[[ -z "$(find "$REMOTE" -maxdepth 1 -name "*.partial")" ]]'
echo "libraries-backup: all checks passed"
