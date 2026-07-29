#!/usr/bin/env bash
set -euo pipefail

# Reverses install.sh. Removes the sentinel-marked blocks it wrote, deletes the
# install root, and restores any neofetch config it displaced.

INSTALL_ROOT=${INSTALL_ROOT:-"$HOME/.local/share/myprompts"}

MARKERS=(
  "myprompts prompt"
  "myprompts prompt style"
  "myprompts lscolors"
  "myprompts ls alias"
  "myprompts aliases"
)

info()  { printf '\033[1;36m[info]\033[0m %s\n' "$*"; }

# Remove the blank line + opening marker .. closing marker span, inclusive.
# append_block writes "\n# >>> NAME >>>\n<line>\n# <<< NAME <<<\n", so the
# leading blank line must go too or the file will not match byte-for-byte.
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
    $0 == start { blanks = ""; in_block = 1; next }
    $0 == end   { in_block = 0; next }
    in_block { next }
    { printf "%s", blanks; blanks = ""; print }
    END { printf "%s", blanks }
  ' "$file" > "$tmp"
  mv "$tmp" "$file"
  info "Removed '$name' block from ${file/#$HOME/~}"
}

restore_neofetch() {
  local target="$HOME/.config/neofetch/config.conf"
  local backup="$target.myprompts-backup"
  if [[ -f $backup ]]; then
    mv "$backup" "$target"
    info "Restored neofetch config from backup"
  elif [[ -f $target ]]; then
    rm -f "$target"
    info "Removed the neofetch config written by myprompts"
  fi
  rm -f "$HOME/.config/neofetch/signalmine.txt"
}

main() {
  local rc
  for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
    local name
    for name in "${MARKERS[@]}"; do
      strip_block "$rc" "$name"
    done
  done

  restore_neofetch

  if [[ -d $INSTALL_ROOT ]]; then
    rm -rf "$INSTALL_ROOT"
    info "Removed ${INSTALL_ROOT/#$HOME/~}"
  fi

  printf '\nUninstalled. Restart your shell.\n'
}

main "$@"
