#!/usr/bin/env bash
set -euo pipefail

# Reverses install.sh. Removes the sentinel-marked blocks it wrote, deletes the
# install root, and restores any fastfetch config it displaced.

INSTALL_ROOT=${INSTALL_ROOT:-"$HOME/.local/share/myprompts"}

MARKERS=(
  "myprompts prompt"
  "myprompts prompt style"
  "myprompts lscolors"
  "myprompts ls alias"
  "myprompts aliases"
)

info()  { printf '\033[1;36m[info]\033[0m %s\n' "$*"; }

# Remove the opening marker .. closing marker span, inclusive, plus exactly
# one of the blank lines preceding it. append_block writes
# "\n# >>> NAME >>>\n<line>\n# <<< NAME <<<\n" -- it owns exactly one blank
# line immediately before the marker. Any additional blank lines buffered
# ahead of the marker belonged to the user's file (e.g. a pre-existing
# trailing blank line before the block was appended) and must survive, or a
# round trip of install then uninstall will not be byte-identical.
strip_block() {
  local file=$1 name=$2
  [[ -f $file ]] || return 0

  local start="# >>> $name >>>"
  local end="# <<< $name <<<"
  grep -Fq "$start" "$file" || return 0

  local tmp
  tmp=$(mktemp)
  awk -v start="$start" -v end="$end" '
    # Buffer blank lines; they are only emitted if not followed by a marker.
    /^$/ && !in_block { blanks = blanks "\n"; next }
    # append_block owns exactly one buffered blank line before the marker;
    # drop that one and re-emit the rest (the caller'"'"'s own blank lines).
    $0 == start { printf "%s", substr(blanks, 2); blanks = ""; in_block = 1; next }
    $0 == end   { in_block = 0; next }
    in_block { next }
    { printf "%s", blanks; blanks = ""; print }
    END { printf "%s", blanks }
  ' "$file" > "$tmp"
  # Write into the existing file (not mv) so its original mode/inode survive;
  # mktemp's 0600 temp file would otherwise silently tighten permissions.
  cat "$tmp" > "$file"
  rm -f "$tmp"
  info "Removed '$name' block from ${file/#$HOME/~}"
}

restore_fastfetch() {
  local target="$HOME/.config/fastfetch/config.jsonc"
  local backup="$target.myprompts-backup"
  if [[ -f $backup ]]; then
    mv "$backup" "$target"
    info "Restored fastfetch config from backup"
  elif [[ -f $target ]]; then
    rm -f "$target"
    info "Removed the fastfetch config written by myprompts"
  fi
  rm -f "$HOME/.config/fastfetch/signalmine.txt"
}

main() {
  local rc
  for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
    local name
    for name in "${MARKERS[@]}"; do
      strip_block "$rc" "$name"
    done
  done

  restore_fastfetch

  if [[ -d $INSTALL_ROOT ]]; then
    rm -rf "$INSTALL_ROOT"
    info "Removed ${INSTALL_ROOT/#$HOME/~}"
  fi

  printf '\nUninstalled. Restart your shell.\n'
}

main "$@"
