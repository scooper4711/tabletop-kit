# shellcheck shell=bash disable=SC2034  # The constants are used by the scripts that source this file.
# Shared by backup-libraries.sh and restore-libraries.sh. Not meant to run on its own.

readonly BACKUP_ROOT="${TABLESIDE_BACKUP_ROOT:-$HOME/TablesideBackups}"
readonly LIBRARY_ROOT="$HOME/Library"
readonly CONTAINERS="$LIBRARY_ROOT/Containers"
readonly GROUP_CONTAINERS="$LIBRARY_ROOT/Group Containers"
readonly GROUP_SUFFIX="io.github.scooper4711.tableside"
# Written last into a backup that holds every library folder there was. Only such a backup tells restore what
# was created after it; one without the file is older or was interrupted.
readonly COMPLETE_MARKER="complete"
# The Tableside Toolkit apps' bundle IDs (macOS matches them without regard to case).
readonly TOOLKIT_APPS=(
  io.github.scooper4711.FieldGuide
  io.github.scooper4711.Mapsmith
  io.github.scooper4711.PawnShop
  io.github.scooper4711.pluck
  io.github.scooper4711.Scrollkeeper
  io.github.scooper4711.Turnkeeper
)

# Every folder the apps keep their libraries in, one per line, whether or not it exists yet.
library_folders() {
  app_container_folders
  group_container_items
}

# Where a library folder goes inside a backup: its path below ~/Library.
backup_path() {
  echo "${1#"$LIBRARY_ROOT/"}"
}

# The bundle IDs of the toolkit apps that are running, one per line.
running_toolkit_apps() {
  lsappinfo list 2>/dev/null \
    | awk -F'"' '/bundleID=/ { for (i = 1; i < NF; i++) if ($i ~ /bundleID=$/) print $(i + 1) }' \
    | grep -ixF "$(printf '%s\n' "${TOOLKIT_APPS[@]}")" || true
}

# The library folders and App Group containers that exist but that macOS won't let this terminal read, one per
# line. macOS keeps other apps' data from a terminal until it is allowed in, and a folder that can't be listed
# looks empty to the scripts.
unreadable_library_folders() {
  local folder
  while IFS= read -r folder; do
    [[ -e "$folder" ]] || continue
    ls "$folder" > /dev/null 2>&1 || echo "$folder"
  done < <(app_container_folders; group_containers)
}

app_container_folders() {
  local bundle
  for bundle in "${TOOLKIT_APPS[@]}"; do
    echo "$CONTAINERS/$bundle/Data/Library/Application Support"
    echo "$CONTAINERS/$bundle/Data/Library/Preferences"
  done
}

# Everything in the App Group containers: the shared art library (`Tableside`), Scrollkeeper's PDFs and whatever
# a later version adds. The glob skips dotfiles, which leaves the system's own container metadata alone.
group_container_items() {
  local group item
  while IFS= read -r group; do
    for item in "$group"/*; do
      [[ -e "$item" ]] && echo "$item"
    done
  done < <(group_containers)
}

# The App Group containers themselves, one per line.
group_containers() {
  local group
  for group in "$GROUP_CONTAINERS"/*"$GROUP_SUFFIX"; do
    [[ -d "$group" ]] && echo "$group"
  done
  return 0
}
