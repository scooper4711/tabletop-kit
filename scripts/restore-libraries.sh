#!/usr/bin/env bash
# Restores a backup made by scripts/backup-libraries.sh, putting every folder it holds back where it came from.
# Library folders created after the backup, such as a shared library a test run synced down, are set aside too,
# so the apps don't go on using them.
#
# The folders being replaced are moved aside into the backup's `replaced-<time>` folder rather than deleted, and the
# backup itself is cloned back, not moved, so it can be restored again after the next test run.
#
# Usage: scripts/restore-libraries.sh [backup-folder] [--yes]
#   With no folder, restores the latest backup in $TABLESIDE_BACKUP_ROOT (default ~/TablesideBackups).
set -euo pipefail
source "$(dirname "$0")/libraries-common.sh"

main() {
  local backup="" confirmed=false argument
  for argument in "$@"; do
    case "$argument" in
      --yes) confirmed=true ;;
      *) backup="$argument" ;;
    esac
  done
  backup="${backup:-$(latest_backup)}"
  require_backup "$backup"
  require_apps_quit
  describe_restore "$backup"
  [[ "$confirmed" == true ]] || confirm
  restore_all "$backup"
}

latest_backup() {
  [[ -d "$BACKUP_ROOT" ]] || return 0
  find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d | sort | tail -1
}

require_backup() {
  local backup="$1"
  if [[ -z "$backup" || ! -f "$backup/manifest.tsv" ]]; then
    echo "restore-libraries: no backup with a manifest.tsv found at '${backup:-$BACKUP_ROOT}'" >&2
    exit 1
  fi
}

require_apps_quit() {
  local running
  running="$(running_toolkit_apps)"
  [[ -z "$running" ]] && return 0
  echo "restore-libraries: quit these apps first, or they will write over the restored files:" >&2
  echo "$running" | sed 's/^/  /' >&2
  exit 1
}

describe_restore() {
  local backup="$1" relative live created
  echo "Restoring $backup:"
  while IFS=$'\t' read -r relative live; do
    echo "  $live"
  done < "$backup/manifest.tsv"
  if [[ ! -f "$backup/$COMPLETE_MARKER" ]]; then
    echo "This backup doesn't say it is complete, so folders created after it are left in place."
    return 0
  fi
  created="$(folders_created_since "$backup")"
  [[ -z "$created" ]] && return 0
  echo "Setting aside what was created after the backup:"
  echo "$created" | sed 's/^/  /'
}

confirm() {
  local answer
  read -r -p "Replace these folders with the backup? [y/N] " answer
  [[ "$answer" =~ ^[Yy]$ ]] || { echo "Nothing restored."; exit 1; }
}

restore_all() {
  local backup="$1" relative live
  local replaced
  replaced="$backup/replaced-$(date +%Y-%m-%d_%H%M%S)"
  while IFS=$'\t' read -r relative live; do
    restore_item "$backup/$relative" "$live" "$replaced/$relative"
  done < "$backup/manifest.tsv"
  set_aside_created_folders "$backup" "$replaced"
  # The preferences daemon caches the old values; restarting it makes the apps read the restored plists.
  killall -u "$USER" cfprefsd 2>/dev/null || true
  echo
  echo "Restored. The folders that were replaced are in:"
  echo "  $replaced"
}

# Moves the live folder aside and clones the backup into its place.
restore_item() {
  local saved="$1" live="$2" aside="$3"
  move_aside "$live" "$aside"
  mkdir -p "$(dirname "$live")"
  cp -cRp "$saved" "$live"
  echo "  restored $live"
}

set_aside_created_folders() {
  local backup="$1" replaced="$2" folder
  while IFS= read -r folder; do
    [[ -n "$folder" ]] || continue
    move_aside "$folder" "$replaced/$(backup_path "$folder")"
    echo "  set aside $folder"
  done < <(folders_created_since "$backup")
}

# The library folders that exist now and aren't in a complete backup, one per line.
folders_created_since() {
  local backup="$1" folder
  [[ -f "$backup/$COMPLETE_MARKER" ]] || return 0
  while IFS= read -r folder; do
    [[ -e "$folder" ]] || continue
    is_in_manifest "$backup" "$folder" || echo "$folder"
  done < <(library_folders)
}

is_in_manifest() {
  awk -F'\t' -v live="$2" '$2 == live { found = 1 } END { exit !found }' "$1/manifest.tsv"
}

# A rename on the same volume, so instant.
move_aside() {
  local live="$1" aside="$2"
  [[ -e "$live" ]] || return 0
  mkdir -p "$(dirname "$aside")"
  mv "$live" "$aside"
}

main "$@"
