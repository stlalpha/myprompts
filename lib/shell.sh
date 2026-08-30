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

# True only when every opening marker is closed by a later terminator, with no
# stray terminator before one and none left open at EOF. uninstall.sh carries
# an identical copy: it is deliberately standalone and does not source lib/.
markers_well_formed() {
  local file=$1 start=$2 end=$3 legacy=$4
  awk -v start="$start" -v end="$end" -v legacy="$legacy" '
    $0 == start { if (open) { exit 1 } open = 1; next }
    ($0 == end || $0 == legacy) { if (!open) { exit 1 } open = 0; next }
    END { if (open) exit 1 }
  ' "$file"
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
  # Rewriting in place is only safe when the markers form ordered pairs. A
  # mere presence check is not enough: an orphaned end marker sitting BEFORE
  # an unmatched start marker satisfies "both strings appear", and the awk
  # below would then enter in_block at the unmatched start and run to EOF,
  # discarding the rest of the user's rc file. Anything malformed -- reversed,
  # duplicated or unterminated -- falls through to appending a fresh block,
  # which leaves existing content alone.
  if grep -F "$marker" "$file" >/dev/null 2>&1 &&
     ! markers_well_formed "$file" "$marker" "$end_marker" "$legacy_end_marker"; then
    warn "Malformed myprompts block in ${file/#$HOME/~}; appending a new block and leaving your content untouched."
  fi
  if grep -F "$marker" "$file" >/dev/null 2>&1 &&
     markers_well_formed "$file" "$marker" "$end_marker" "$legacy_end_marker"; then
    info "Updating existing block in ${file/#$HOME/~}."
    local tmp tmp_base
    # An explicit template so TMPDIR is honoured on macOS too, where a bare
    # `mktemp` uses the Darwin per-user directory regardless.
    tmp_base=${TMPDIR:-/tmp}
    tmp_base=${tmp_base%/}
    if ! tmp=$(mktemp "$tmp_base/myprompts.XXXXXX"); then
      warn "Could not create a temporary file; leaving ${file/#$HOME/~} unchanged."
      return 1
    fi
    if ! awk -v start="$marker" -v end="$end_marker" \
        -v legacy="$legacy_end_marker" -v line="$line" '
      BEGIN {in_block=0}
      $0 == start {print start; print line; in_block=1; next}
      ($0 == end || $0 == legacy) {in_block=0; print end; next}
      !in_block {print}
    ' "$file" >"$tmp"; then
      warn "Failed to stage the update; leaving ${file/#$HOME/~} unchanged."
      rm -f "$tmp"
      return 1
    fi
    # `cat "$tmp" > "$file"` truncates $file before it can discover the
    # staged copy is unusable, so validate first and keep a backup to restore
    # from if the write itself fails partway.
    if [[ ! -s $tmp ]]; then
      warn "Staged update was empty; leaving ${file/#$HOME/~} unchanged."
      rm -f "$tmp"
      return 1
    fi
    local backup="$tmp.orig"
    cp "$file" "$backup" 2>/dev/null || true
    # Write into the existing file (not mv) so its mode, inode and symlink
    # target survive; mktemp's 0600 temp file would otherwise tighten
    # permissions and turn a symlinked rc into a regular file.
    if ! cat "$tmp" > "$file"; then
      warn "Write to ${file/#$HOME/~} failed; restoring the original."
      [[ -f $backup ]] && cat "$backup" > "$file"
      rm -f "$tmp" "$backup"
      return 1
    fi
    rm -f "$tmp" "$backup"
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
