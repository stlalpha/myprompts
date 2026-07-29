#!/usr/bin/env bash
# Shell rc file management: existing-install detection, marker blocks, aliases.
# Expects: INSTALL_ROOT, INTERACTIVE, PROMPT_FD from install.sh.
# shellcheck disable=SC2154  # INSTALL_ROOT, INTERACTIVE, PROMPT_FD come from install.sh

apply_aliases_for_shell() {
  local rc_file=$1
  local alias_array_name=$2

  if ! declare -p "$alias_array_name" >/dev/null 2>&1; then
    return
  fi

  local aliases
  eval "aliases=(\"\${${alias_array_name}[@]}\")"

  [[ ${#aliases[@]} -eq 0 ]] && return

  local content
  content=$(printf '%s\n' "${aliases[@]}")
  append_block "$rc_file" "# >>> myprompts aliases >>>" "$content"
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
    # Capitalize first letter of summary
    local first_char first_upper rest
    first_char=${summary:0:1}
    rest=${summary:1}
    first_upper=$(echo "$first_char" | tr '[:lower:]' '[:upper:]')
    error "${first_upper}${rest}; run interactively to confirm reinstall."
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
