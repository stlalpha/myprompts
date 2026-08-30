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
  # Replace BOTH arrows: ${marker/>>>/<<<} substitutes only the first, which
  # produced "# <<< NAME >>>" while uninstall.sh looked for "# <<< NAME <<<".
  # They never matched, so removal fell through to truncating at EOF.
  local end_marker=${marker//>>>/<<<}
  # rc files written before that fix carry the asymmetric form. Recognise it so
  # an existing install stays updatable; the rewrite below normalises it.
  local legacy_end_marker=${marker/>>>/<<<}

  touch "$file"
  # Both markers must be present to rewrite in place. The awk below clears
  # in_block only on an exact match of the end marker, so if the user edited
  # or deleted that line, every remaining line of their rc file would be
  # dropped. Treat a half-open block as absent and append a fresh one: the
  # orphaned opening marker is untidy, but the user's content survives.
  if grep -F "$marker" "$file" >/dev/null 2>&1 &&
     ! grep -F "$end_marker" "$file" >/dev/null 2>&1 &&
     ! grep -F "$legacy_end_marker" "$file" >/dev/null 2>&1; then
    warn "Unterminated myprompts block in ${file/#$HOME/~} (no '$end_marker'); appending a new block and leaving your content untouched."
  fi
  if grep -F "$marker" "$file" >/dev/null 2>&1 &&
     { grep -F "$end_marker" "$file" >/dev/null 2>&1 ||
       grep -F "$legacy_end_marker" "$file" >/dev/null 2>&1; }; then
    info "Updating existing block in ${file/#$HOME/~}."
    local tmp
    tmp=$(mktemp)
    awk -v start="$marker" -v end="$end_marker" \
        -v legacy="$legacy_end_marker" -v line="$line" '
      BEGIN {in_block=0}
      $0 == start {print start; print line; in_block=1; next}
      ($0 == end || $0 == legacy) {in_block=0; print end; next}
      !in_block {print}
    ' "$file" >"$tmp"
    # Write into the existing file (not mv) so its mode, inode and symlink
    # target survive; mktemp's 0600 temp file would otherwise tighten
    # permissions and turn a symlinked rc into a regular file.
    cat "$tmp" > "$file"
    rm -f "$tmp"
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
