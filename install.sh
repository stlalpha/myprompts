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
PROMPT_FD=0
TTY_FD_OPENED=0

if [[ -n ${MYPROMPTS_NONINTERACTIVE:-} ]]; then
  PROMPT_FD=0
  INTERACTIVE=0
else
  if [[ -r /dev/tty && -w /dev/tty ]]; then
    if exec 3<>/dev/tty; then
      PROMPT_FD=3
      INTERACTIVE=1
      TTY_FD_OPENED=1
    else
      echo "Unable to open /dev/tty for interactive prompts." >&2
      exit 1
    fi
  elif [[ -t 0 ]]; then
    PROMPT_FD=0
    INTERACTIVE=1
  else
    echo "No interactive terminal detected; run the installer from an interactive shell." >&2
    exit 1
  fi
fi

cleanup() {
  if [[ $TTY_FD_OPENED -eq 1 ]]; then
    exec 3>&-
  fi
}

trap cleanup EXIT

info()  { printf '\e[1;36m[info]\e[0m %s\n' "$*"; }
warn()  { printf '\e[1;33m[warn]\e[0m %s\n' "$*"; }
error() { printf '\e[1;31m[fail]\e[0m %s\n' "$*" >&2; }

print_header() {
  local reset=$'\033[0m'
  local pink=$'\033[38;5;198m'
  local cyan=$'\033[38;5;51m'
  local purple=$'\033[38;5;141m'
  local blue=$'\033[38;5;39m'

  cat <<BANNER
${pink}╔════════════════════════════════════════════════════════════╗${reset}
${pink}║${reset}  ${cyan}Spaceman's Auto-Personalizer${reset} ${purple}v0.1b${reset}                    ${pink}║${reset}
${pink}║${reset}  ${blue}Bootstrapping vaporwave shell and LS aesthetic...${reset}      ${pink}║${reset}
${pink}╚════════════════════════════════════════════════════════════╝${reset}
BANNER
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    error "Missing required command '$1'. Please install it and rerun." 
    exit 1
  fi
}

existing_install_present() {
  [[ -d $INSTALL_ROOT ]] && [[ -n $(ls -A "$INSTALL_ROOT" 2>/dev/null) ]]
}

describe_install_state() {
  local target=$1
  if [[ ! -d $target ]]; then
    printf 'fresh install'
    return
  fi

  if [[ -f $target/.install-meta ]]; then
    local meta
    meta=$(<"$target/.install-meta")
    printf 'update of existing install (%s)' "$meta"
  else
    printf 'existing directory detected'
  fi
}

handle_existing_install() {
  if ! existing_install_present; then
    return
  fi

  local summary
  summary=$(describe_install_state "$INSTALL_ROOT")

  if (( ! INTERACTIVE )); then
    error "${summary^}; run interactively to confirm reinstall."
    exit 1
  fi

  printf '\nDetected %s at %s.\n' "$summary" "${INSTALL_ROOT/#$HOME/~}" >&"$PROMPT_FD"
  printf 'Reinstall will remove and replace this directory.\n' >&"$PROMPT_FD"

if prompt_yes_no "Proceed with reinstall?" N; then
    info "Removing previous installation."
    rm -rf "$INSTALL_ROOT"
  else
    info "Installation cancelled; existing setup left untouched."
    exit 0
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
    if ! read -r -u "$PROMPT_FD" -p "$prompt" reply; then
      error "Failed to read response; aborting installation."
      exit 1
    fi
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
  local __out_var=$1
  local preset=""
  local selection=""

  if (( ! INTERACTIVE )); then
    preset=${PROMPT_VARIANT:-}
    preset=${preset,,}
    case "$preset" in
      liquid|animated)
        selection="$PROMPT_LIQUID"
        ;;
      classic|static|vaporwave|"")
        selection="$PROMPT_STATIC"
        ;;
      *) error "Unknown PROMPT_VARIANT '$preset'; expected 'classic' or 'liquid'."; exit 1 ;;
    esac
    printf -v "$__out_var" '%s' "$selection"
    return
  fi

  local reset=$'\033[0m'
  local bold=$'\033[1m'
  local pink=$'\033[38;5;198m'
  local cyan=$'\033[38;5;51m'
  local purple=$'\033[38;5;141m'
  local dark_purple=$'\033[38;5;93m'
  local blue=$'\033[38;5;39m'
  local orange=$'\033[38;5;209m'
  local green=$'\033[38;5;85m'
  local magenta=$'\033[38;5;201m'
  local wave=$'\033[38;5;123m'
  local bg_dark=$'\033[48;5;234m'

  printf '\nPrompt variant options:\n' >&"$PROMPT_FD"
  printf '  [1] Classic – static vaporwave prompt\n' >&"$PROMPT_FD"
  printf '      %s%s◤%suser%s@%shost%s◢%s %s【%s~/project%s】%s %s『main』%s %s%s▸%s\n' \
    "$bg_dark" "$pink" "$cyan" "$dark_purple" "$purple" "$pink" "$reset" "$orange" "$green" "$orange" "$reset" "$magenta" "$reset" "$blue" "$bold" "$reset" >&"$PROMPT_FD"
  printf '  [2] Liquid – animated waveform prompt\n' >&"$PROMPT_FD"
  printf '      %s%s◤%suser%s@%shost%s◢%s %s≈≋≈%s %s~/project%s %s≈≋≈%s %s『main』%s %s%s∼▸%s%s\n' \
    "$bg_dark" "$pink" "$cyan" "$dark_purple" "$purple" "$pink" "$reset" "$wave" "$reset" "$green" "$reset" "$wave" "$reset" "$magenta" "$reset" "$wave" "$bold" "$reset" "$reset" >&"$PROMPT_FD"

  local choice
  while true; do
    if ! printf 'Select prompt variant [1-2] (default: 1): ' >&"$PROMPT_FD"; then
      error "Failed to display prompt variant question."
      exit 1
    fi
    if ! IFS= read -r -u "$PROMPT_FD" choice; then
      error "Failed to read response; aborting installation."
      exit 1
    fi
    choice=${choice:-1}
    case "$choice" in
      1) selection="$PROMPT_STATIC"; break ;;
      2) selection="$PROMPT_LIQUID"; break ;;
      *) printf 'Please enter 1 or 2.\n' >&"$PROMPT_FD" ;;
    esac
  done

  printf -v "$__out_var" '%s' "$selection"
}

choose_prompt_style() {
  local __out_var=$1
  local preset=""
  local selection=""
  if (( ! INTERACTIVE )); then
    preset=${PROMPT_STYLE:-}
    preset=${preset,,}
    case "$preset" in
      extended|multi-line)
        selection="extended"
        ;;
      compact|single-line|default|"")
        selection="compact"
        ;;
      *) error "Unknown PROMPT_STYLE '$preset'; expected 'compact' or 'extended'."; exit 1 ;;
    esac
    printf -v "$__out_var" '%s' "$selection"
    return
  fi

  local current=${MYPROMPTS_PROMPT_STYLE:-compact}
  current=${current,,}
  local default_choice_num=1
  local default_choice_label="Compact"
  if [[ $current == extended ]]; then
    default_choice_num=2
    default_choice_label="Extended"
  fi

  local reset=$'\033[0m'
  local bold=$'\033[1m'
  local pink=$'\033[38;5;198m'
  local cyan=$'\033[38;5;51m'
  local purple=$'\033[38;5;141m'
  local dark_purple=$'\033[38;5;93m'
  local blue=$'\033[38;5;39m'
  local orange=$'\033[38;5;209m'
  local green=$'\033[38;5;85m'
  local magenta=$'\033[38;5;201m'
  local bg_dark=$'\033[48;5;234m'

  printf '\nPrompt layout options (current: %s):\n' "$default_choice_label" >&"$PROMPT_FD"
  printf '  [1] Compact – single-line prompt\n' >&"$PROMPT_FD"
  printf '      %s%s◤%suser%s@%shost%s◢%s %s【%s~/project%s】%s %s『main』%s %s%s▸%s\n' \
    "$bg_dark" "$pink" "$cyan" "$dark_purple" "$purple" "$pink" "$reset" "$orange" "$green" "$orange" "$reset" "$magenta" "$reset" "$blue" "$bold" "$reset" >&"$PROMPT_FD"
  printf '  [2] Extended – multi-line prompt with decorative header\n' >&"$PROMPT_FD"
  printf '      %s◤%suser%s◢%s %s◆%s %s◤%shost%s◢%s %s➤ %s~/project%s %s『main』%s\n' \
    "$pink" "$cyan" "$pink" "$reset" "$cyan" "$reset" "$pink" "$purple" "$pink" "$reset" "$green" "$blue" "$reset" "$magenta" "$reset" >&"$PROMPT_FD"
  printf '      %s╰─%s%s▸%s\n' "$orange" "$blue" "$bold" "$reset" >&"$PROMPT_FD"

  local choice
  while true; do
    if ! printf 'Select prompt layout [1-2] (default: %s [%d]): ' "$default_choice_label" "$default_choice_num" >&"$PROMPT_FD"; then
      error "Failed to display prompt layout question."
      exit 1
    fi
    if ! IFS= read -r -u "$PROMPT_FD" choice; then
      error "Failed to read response; aborting installation."
      exit 1
    fi
    choice=${choice:-$default_choice_num}
    case "$choice" in
      1) selection="compact"; break ;;
      2) selection="extended"; break ;;
      *) printf 'Please enter 1 or 2.\n' >&"$PROMPT_FD" ;;
    esac
  done

  printf -v "$__out_var" '%s' "$selection"
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

ensure_ls_alias() {
  local file=$1
  local marker="# >>> myprompts ls alias >>>"
  local alias_line="alias ls='ls --color=auto'"

  if [[ -f $file ]] && grep -qE '^[[:space:]]*alias[[:space:]]+ls=' "$file"; then
    info "Existing ls alias detected in ${file/#$HOME/~}; skipping alias install."
    return
  fi

  append_block "$file" "$marker" "$alias_line"
}

write_prompt_style() {
  local file=$1
  local style=$2
  local marker="# >>> myprompts prompt style >>>"
  local line="export MYPROMPTS_PROMPT_STYLE=$style"
  append_block "$file" "$marker" "$line"
}

main() {
  require_command curl

  print_header

  handle_existing_install

  info "Installing myprompts assets to ${INSTALL_ROOT/#$HOME/~}"
  mkdir -p "$INSTALL_ROOT"

  download_asset "$PROMPT_STATIC"
  download_asset "$PROMPT_LIQUID"
  download_asset "$PROMPT_ZSH"
  download_asset "$LS_COLORS_FILE"

  printf 'installed %s\n' "$(date -u +%FT%TZ)" >"$INSTALL_ROOT/.install-meta"

  local default_shell
  default_shell=$(basename "${SHELL:-bash}")
  info "Detected default shell: $default_shell"

  local configure_bash=0
  local configure_zsh=0
  local prompt_style=""

  local bash_default="N"
  [[ $default_shell == bash ]] && bash_default="Y"

  if prompt_yes_no "Configure Bash prompt?" "$bash_default"; then
    if [[ -z $prompt_style ]]; then
      choose_prompt_style prompt_style
      info "Using $prompt_style layout for prompts."
    fi
    local bash_prompt_file=""
    choose_prompt_variant bash_prompt_file
    write_prompt_style "$HOME/.bashrc" "$prompt_style"
    append_block "$HOME/.bashrc" "# >>> myprompts prompt >>>" "source \"$INSTALL_ROOT/$bash_prompt_file\""
    configure_bash=1
  fi

  local zsh_default="N"
  [[ $default_shell == zsh ]] && zsh_default="Y"

  if prompt_yes_no "Configure Zsh prompt?" "$zsh_default"; then
    if [[ -z $prompt_style ]]; then
      choose_prompt_style prompt_style
      info "Using $prompt_style layout for prompts."
    fi
    local zsh_prompt_file="$PROMPT_ZSH"
    write_prompt_style "$HOME/.zshrc" "$prompt_style"
    append_block "$HOME/.zshrc" "# >>> myprompts prompt >>>" "[[ -f \"$INSTALL_ROOT/$zsh_prompt_file\" ]] && source \"$INSTALL_ROOT/$zsh_prompt_file\""
    configure_zsh=1
  fi

  if prompt_yes_no "Install Vaporwave LS_COLORS theme?" Y; then
    local line="[ -f \"$INSTALL_ROOT/$LS_COLORS_FILE\" ] && source \"$INSTALL_ROOT/$LS_COLORS_FILE\""

    if (( configure_bash )); then
      append_block "$HOME/.bashrc" "# >>> myprompts lscolors >>>" "$line"
      ensure_ls_alias "$HOME/.bashrc"
    elif [[ -f $HOME/.bashrc ]]; then
      if prompt_yes_no "Add LS colors to Bash (.bashrc)?" N; then
        append_block "$HOME/.bashrc" "# >>> myprompts lscolors >>>" "$line"
        ensure_ls_alias "$HOME/.bashrc"
      fi
    fi

    if (( configure_zsh )); then
      append_block "$HOME/.zshrc" "# >>> myprompts lscolors >>>" "$line"
      ensure_ls_alias "$HOME/.zshrc"
    elif [[ -f $HOME/.zshrc ]]; then
      if prompt_yes_no "Add LS colors to Zsh (.zshrc)?" Y; then
        append_block "$HOME/.zshrc" "# >>> myprompts lscolors >>>" "$line"
        ensure_ls_alias "$HOME/.zshrc"
      fi
    fi
  fi

  cat <<'SUMMARY'

Installation complete!
- Restart your shell or run "source ~/.bashrc" / "source ~/.zshrc" to activate.
- Re-run this installer anytime to change variants; existing blocks are updated in place.
SUMMARY
}

main "$@"
