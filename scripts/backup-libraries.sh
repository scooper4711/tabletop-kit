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
#
# TABLESIDE_BACKUP_SKIP_PDFS=1  leaves out every PDF (Scrollkeeper's downloads, the art library's source PDFs),
#                               which can be downloaded again; a restore then lacks them.
# TABLESIDE_BACKUP_REMOTE       an rsync destination, "host:/path" or a folder. The finished backup is sent there,
#                               its files hard-linked to the previous backup's where unchanged, and the local copy is
#                               removed. Restore by copying a backup back (rsync -a host:/path/<backup> ~/...).
# TABLESIDE_BACKUP_KEEP         how many backups to keep at the remote destination (default 14).
set -euo pipefail
source "$(dirname "$0")/libraries-common.sh"

main() {
  local label="${1:-}"
  local destination
  destination="$BACKUP_ROOT/$(date +%Y-%m-%d_%H%M%S)${label:+-$label}"
  warn_if_apps_running
  stop_if_folders_are_unreadable
  mkdir -p "$destination"
  : > "$destination/manifest.tsv"
  back_up_library_folders "$destination"
  [[ "${TABLESIDE_BACKUP_SKIP_PDFS:-0}" == 1 ]] && leave_out_pdfs "$destination"
  : > "$destination/$COMPLETE_MARKER"
  echo
  echo "Backed up $(wc -l < "$destination/manifest.tsv" | tr -d ' ') folders."
  if [[ -n "${TABLESIDE_BACKUP_REMOTE:-}" ]]; then
    send_to_remote "$destination" "$TABLESIDE_BACKUP_REMOTE"
  else
    echo "  $destination"
    echo "Restore with: scripts/restore-libraries.sh \"$destination\""
  fi
}

# Deletes the PDFs from the backup's clones; the originals are untouched.
leave_out_pdfs() {
  local count
  count="$(find "$1" -type f -iname '*.pdf' | wc -l | tr -d ' ')"
  find "$1" -type f -iname '*.pdf' -delete
  : > "$1/pdfs-left-out"
  echo "Left out $count PDFs."
}

# Runs a command where the remote backups are: over ssh for "host:/path", here for a plain folder.
on_remote() {
  local host="$1"; shift
  if [[ -n "$host" ]]; then ssh -o BatchMode=yes "$host" "$@"; else bash -c "$*"; fi
}

# Sends a finished backup to the remote destination, hard-linking unchanged files to the newest complete backup
# there, keeps the newest $TABLESIDE_BACKUP_KEEP, and removes the local copy. A backup only gets its final name
# once it has fully arrived, so an interrupted send never looks like a backup.
send_to_remote() {
  local local_backup="$1" remote="$2" host="" folder name previous target
  if [[ "$remote" == *:* ]]; then host="${remote%%:*}"; folder="${remote#*:}"; else folder="$remote"; fi
  name="$(basename "$local_backup")"
  target="${host:+$host:}$folder"
  on_remote "$host" "mkdir -p '$folder' && rm -rf '$folder'/*.partial"
  previous="$(on_remote "$host" "cd '$folder' && for b in */; do [ -f \"\${b}$COMPLETE_MARKER\" ] && echo \"\${b%/}\"; done | sort | tail -1")"
  rsync -a ${previous:+--link-dest="../$previous"} "$local_backup/" "$target/$name.partial/"
  on_remote "$host" "mv '$folder/$name.partial' '$folder/$name'"
  prune_remote "$host" "$folder"
  rm -rf "$local_backup"
  echo "Sent to $target/$name${previous:+ (unchanged files linked to $previous)}."
}

prune_remote() {
  local host="$1" folder="$2" keep="${TABLESIDE_BACKUP_KEEP:-14}"
  # Only dated folders are backups; a NAS may add its own beside them (Synology's @eaDir, say).
  on_remote "$host" "cd '$folder' && ls -1d [0-9]*/ | sed 's#/\$##' | sort | awk -v keep=$keep '{ all[NR] = \$0 } END { for (i = 1; i <= NR - keep; i++) print all[i] }' | while read -r old; do rm -rf \"\$old\"; done"
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

# A folder that can't be read would be left out of a backup that then calls itself complete, so nothing is
# backed up until all of them can be.
stop_if_folders_are_unreadable() {
  local unreadable
  unreadable="$(unreadable_library_folders)"
  [[ -z "$unreadable" ]] && return 0
  echo "Backing up failed: macOS won't let this terminal read:" >&2
  echo "$unreadable" | sed 's/^/  /' >&2
  echo "Give your terminal app Full Disk Access (System Settings > Privacy & Security > Full Disk Access)," >&2
  echo "restart it, and run this again. Nothing was backed up." >&2
  exit 1
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
