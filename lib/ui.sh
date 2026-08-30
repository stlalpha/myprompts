#!/usr/bin/env bash
# Terminal output and interactive prompts.
# Expects: PROMPT_FD, INTERACTIVE, and the VW_* color variables from install.sh.
# shellcheck disable=SC2154  # PROMPT_FD, INTERACTIVE, VW_* come from install.sh

error() { printf '\e[1;31m[fail]\e[0m %s\n' "$*" >&2; }

print_header() {
  printf '%b%s%b\n' "$VW_PINK" "$VW_TOP_BORDER" "$VW_RESET"
  printf "  %bSpaceman's Auto-Personalizer%b %bv0.1b%b\n" "$VW_CYAN" "$VW_RESET" "$VW_PURPLE" "$VW_RESET"
  printf "  %bBootstrapping vaporwave shell and LS aesthetic...%b\n" "$VW_BLUE" "$VW_RESET"
  printf '%b%s%b\n' "$VW_PINK" "$VW_BOTTOM_BORDER" "$VW_RESET"
}

print_pkg_group() {
  local label=$1
  local array_name=$2
  local color=$3
  local packages=()
  eval "packages=(\"\${${array_name}[@]}\")"

  if [[ ${#packages[@]} -gt 0 ]]; then
    printf '    %b%s%b %b%s:%b %b%s%b\n' \
      "$VW_PINK" "$VW_ITEM_ICON" "$VW_RESET" "$color" "$label" "$VW_RESET" "$color" "${packages[*]}" "$VW_RESET"
  else
    printf '    %b%s%b %b%s:%b %b<none>%b\n' \
      "$VW_PINK" "$VW_ITEM_ICON" "$VW_RESET" "$color" "$label" "$VW_RESET" "$VW_GRAY" "$VW_RESET"
  fi
}

print_pkg_list() {
  local label=$1
  local color=$2
  shift 2
  local packages=("$@")
  if [[ ${#packages[@]} -gt 0 ]]; then
    printf '    %b%s%b %b%s:%b %b%s%b\n' \
      "$VW_PINK" "$VW_ITEM_ICON" "$VW_RESET" "$color" "$label" "$VW_RESET" "$color" "${packages[*]}" "$VW_RESET"
  fi
}

print_none_line() {
  printf '    %b%s%b %b<none>%b\n' "$VW_PINK" "$VW_ITEM_ICON" "$VW_RESET" "$VW_GRAY" "$VW_RESET"
}

print_installed_items() {
  local detected=$1
  if [[ -n $detected ]]; then
    while IFS= read -r line; do
      [[ -z $line ]] && continue
      printf '    %b%s%b %b%s%b\n' "$VW_PINK" "$VW_INSTALLED_ICON" "$VW_RESET" "$VW_GREEN" "$line" "$VW_RESET"
    done <<< "$detected"
  else
    printf '    %b%s%b %b<none detected>%b\n' "$VW_PINK" "$VW_INSTALLED_ICON" "$VW_RESET" "$VW_GRAY" "$VW_RESET"
  fi
}

prompt_yes_no() {
  local message=$1
  local default=${2:-Y}
  local default_lower
  default_lower=$(echo "$default" | tr '[:upper:]' '[:lower:]')

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
    reply=$(echo "$reply" | tr '[:upper:]' '[:lower:]')
    case "$reply" in
      y|yes) return 0 ;;
      n|no)  return 1 ;;
      *)     echo "Please answer yes or no." ;;
    esac
  done
}

choose_neofetch_style() {
  local __out_var=$1
  local preset=""
  local selection=""

  if (( ! INTERACTIVE )); then
    preset=${NEOFETCH_STYLE:-}
    preset=$(echo "$preset" | tr '[:upper:]' '[:lower:]')
    case "$preset" in
      boxed|minimal)
        selection="config-boxed.conf"
        ;;
      vaporwave|classic|"")
        selection="config-vaporwave.conf"
        ;;
      *) error "Unknown NEOFETCH_STYLE '$preset'; expected 'vaporwave' or 'boxed'."; exit 1 ;;
    esac
    printf -v "$__out_var" '%s' "$selection"
    return
  fi

  local reset=$'\033[0m'
  local pink=$'\033[38;5;198m'
  local cyan=$'\033[38;5;51m'
  local purple=$'\033[38;5;141m'
  local orange=$'\033[38;5;209m'
  local green=$'\033[38;5;85m'
  local teal=$'\033[38;5;44m'
  # shellcheck disable=SC2034  # reserved for a future neofetch palette entry
  local dark_teal=$'\033[38;5;24m'

  printf '\nNeofetch style options:\n' >&"$PROMPT_FD"
  printf '  [1] Vaporwave – colorful with ◆ diamonds and 【】 headers\n' >&"$PROMPT_FD"
  printf '      %s◆%s User  %s◆%s OS  %s◆%s Host  %s【%sHARDWARE%s】%s\n' \
    "$pink" "$reset" "$cyan" "$reset" "$purple" "$reset" "$pink" "$cyan" "$pink" "$reset" >&"$PROMPT_FD"
  printf '  [2] Boxed – minimal with .---. borders, cyan/teal\n' >&"$PROMPT_FD"
  printf '      %s.---%s  User: ...  %s---.%s\n' \
    "$teal" "$reset" "$teal" "$reset" >&"$PROMPT_FD"

  local choice
  while true; do
    if ! printf 'Select neofetch style [1-2] (default: 1): ' >&"$PROMPT_FD"; then
      error "Failed to display neofetch style question."
      exit 1
    fi
    if ! IFS= read -r -u "$PROMPT_FD" choice; then
      error "Failed to read response; aborting installation."
      exit 1
    fi
    choice=${choice:-1}
    case "$choice" in
      1) selection="config-vaporwave.conf"; break ;;
      2) selection="config-boxed.conf"; break ;;
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
    preset=$(echo "$preset" | tr '[:upper:]' '[:lower:]')
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
  current=$(echo "$current" | tr '[:upper:]' '[:lower:]')
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
