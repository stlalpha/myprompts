#!/usr/bin/env bash
set -euo pipefail

# Interactive installer for the myprompts collection.
# Downloads vaporwave prompt themes and configures the detected shell.

BASE_URL=${BASE_URL:-"https://raw.githubusercontent.com/stlalpha/myprompts/main"}
INSTALL_ROOT=${INSTALL_ROOT:-"$HOME/.local/share/myprompts"}
PROMPT_STATIC=vaporwave_bash_prompt
PROMPT_LIQUID=vaporwave_liquid_prompt
PROMPT_ZSH=vaporwave_zsh_prompt
LS_COLORS_FILE=vaporwave_lscolors

INTERACTIVE=0
if [[ -t 0 && -t 1 ]]; then
  INTERACTIVE=1
fi

info()  { printf '\e[1;36m[info]\e[0m %s\n' "$*"; }
warn()  { printf '\e[1;33m[warn]\e[0m %s\n' "$*"; }
error() { printf '\e[1;31m[fail]\e[0m %s\n' "$*" >&2; }

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    error "Missing required command '$1'. Please install it and rerun." 
    exit 1
  fi
}

prompt_yes_no() {
  local message=$1
  local default=${2:-Y}
  local default_lower=${default,,}

  if (( ! INTERACTIVE )); then
    [[ $default_lower == y* ]]
    return
  fi

  local reply prompt
  if [[ $default_lower == y* ]]; then
    prompt="${message} [Y/n] "
  else
    prompt="${message} [y/N] "
  fi

  while true; do
    read -r -p "$prompt" reply
    reply=${reply:-$default}
    reply=${reply,,}
    case "$reply" in
      y|yes) return 0 ;;
      n|no)  return 1 ;;
      *)     echo "Please answer yes or no." ;;
    esac
  done
}

choose_prompt_variant() {
  local choice

  if (( ! INTERACTIVE )); then
    echo "$PROMPT_STATIC"
    return
  fi

  cat <<CHOICES
Select Bash prompt variant:
  [1] Vaporwave classic (static)
  [2] Vaporwave liquid (animated)
CHOICES

  while true; do
    read -r -p "Enter choice [1/2]: " choice
    choice=${choice:-1}
    case "$choice" in
      1) echo "$PROMPT_STATIC"; return ;;
      2) echo "$PROMPT_LIQUID"; return ;;
      *) echo "Please enter 1 or 2." ;;
    esac
  done
}

append_block() {
  local file=$1
  local marker=$2
  local line=$3
  local end_marker=${marker/>>>/<<<}

  touch "$file"
  if grep -F "$marker" "$file" >/dev/null 2>&1; then
    info "Updating existing block in ${file/#$HOME/~}."
    local tmp
    tmp=$(mktemp)
    awk -v start="$marker" -v end="$end_marker" -v line="$line" '
      BEGIN {in_block=0}
      $0 == start {print start; print line; in_block=1; next}
      $0 == end {in_block=0; print end; next}
      !in_block {print}
    ' "$file" >"$tmp"
    mv "$tmp" "$file"
  else
    {
      printf '\n%s\n' "$marker"
      printf '%s\n' "$line"
      printf '%s\n' "$end_marker"
    } >>"$file"
    info "Added block to ${file/#$HOME/~}."
  fi
}

download_asset() {
  local name=$1
  local target="$INSTALL_ROOT/$name"
  info "Fetching $name"
  curl -fsSL "$BASE_URL/$name" -o "$target"
  chmod 644 "$target"
}

main() {
  require_command curl

  info "Installing myprompts assets to ${INSTALL_ROOT/#$HOME/~}"
  mkdir -p "$INSTALL_ROOT"

  download_asset "$PROMPT_STATIC"
  download_asset "$PROMPT_LIQUID"
  download_asset "$PROMPT_ZSH"
  download_asset "$LS_COLORS_FILE"

  local default_shell
  default_shell=$(basename "${SHELL:-bash}")
  info "Detected default shell: $default_shell"

  local configure_bash=0
  local configure_zsh=0

  local bash_default="N"
  [[ $default_shell == bash ]] && bash_default="Y"

  if prompt_yes_no "Configure Bash prompt?" "$bash_default"; then
    local bash_prompt_file
    bash_prompt_file=$(choose_prompt_variant)
    append_block "$HOME/.bashrc" "# >>> myprompts prompt >>>" "source \"$INSTALL_ROOT/$bash_prompt_file\""
    configure_bash=1
  fi

  local zsh_default="N"
  [[ $default_shell == zsh ]] && zsh_default="Y"

  if prompt_yes_no "Configure Zsh prompt?" "$zsh_default"; then
    append_block "$HOME/.zshrc" "# >>> myprompts prompt >>>" "[[ -f \"$INSTALL_ROOT/$PROMPT_ZSH\" ]] && source \"$INSTALL_ROOT/$PROMPT_ZSH\""
    configure_zsh=1
  fi

  if prompt_yes_no "Install Vaporwave LS_COLORS theme?" Y; then
    local line="[ -f \"$INSTALL_ROOT/$LS_COLORS_FILE\" ] && source \"$INSTALL_ROOT/$LS_COLORS_FILE\""
    if (( configure_bash )) || [[ -f $HOME/.bashrc ]]; then
      append_block "$HOME/.bashrc" "# >>> myprompts lscolors >>>" "$line"
    fi
    if (( configure_zsh )) || [[ -f $HOME/.zshrc ]]; then
      append_block "$HOME/.zshrc" "# >>> myprompts lscolors >>>" "$line"
    fi
  fi

  cat <<'SUMMARY'

Installation complete!
- Restart your shell or run "source ~/.bashrc" / "source ~/.zshrc" to activate.
- Re-run this installer anytime to change variants; existing blocks are updated in place.
SUMMARY
}

main "$@"
