#!/usr/bin/env bash
# Backs up the Tableside Toolkit apps' libraries before a test run: each app's Application Support and preferences
# in its sandbox container, and everything in the shared App Group containers (the shared art library and
# Scrollkeeper's PDFs).
#
# Files are APFS clones (`cp -c`), so a backup takes almost no disk space and survives the apps moving or rewriting
# the originals. Restore with scripts/restore-libraries.sh.
#
# Usage: scripts/backup-libraries.sh [label]
#   Backups go to $TABLESIDE_BACKUP_ROOT (default ~/TablesideBackups), one folder per run.
set -euo pipefail
source "$(dirname "$0")/libraries-common.sh"

main() {
  local label="${1:-}"
  local destination
  destination="$BACKUP_ROOT/$(date +%Y-%m-%d_%H%M%S)${label:+-$label}"
  warn_if_apps_running
  mkdir -p "$destination"
  : > "$destination/manifest.tsv"
  back_up_library_folders "$destination"
  : > "$destination/$COMPLETE_MARKER"
  echo
  echo "Backed up $(wc -l < "$destination/manifest.tsv" | tr -d ' ') folders to:"
  echo "  $destination"
  echo "Restore with: scripts/restore-libraries.sh \"$destination\""
}

warn_if_apps_running() {
  local running
  running="$(running_toolkit_apps)"
  if [[ -n "$running" ]]; then
    echo "Warning: these apps are running, so files they are writing may be caught half-saved:" >&2
    echo "$running" | sed 's/^/  /' >&2
    echo "Quit them first for a clean backup." >&2
  fi
}

back_up_library_folders() {
  local destination="$1" folder
  while IFS= read -r folder; do
    clone_item "$destination" "$folder"
  done < <(library_folders)
}

# Clones one folder into the backup and records where it came from.
clone_item() {
  local destination="$1" source="$2" relative
  [[ -e "$source" ]] || return 0
  relative="$(backup_path "$source")"
  mkdir -p "$(dirname "$destination/$relative")"
  printf '  %-90s %s\n' "$relative" "$(du -sh "$source" | cut -f1)"
  cp -cRp "$source" "$destination/$relative"
  printf '%s\t%s\n' "$relative" "$source" >> "$destination/manifest.tsv"
}

main "$@"
