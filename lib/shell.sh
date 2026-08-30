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
# stray terminator before one and none left open at EOF. uninstall.sh carries a
# byte-identical copy: it is the recovery tool and runs `set -euo pipefail`, so
# sourcing a lib/ that had gone missing would abort the uninstall outright --
# a worse failure than duplication. test_uninstall.sh asserts the two copies
# never drift.
markers_well_formed() {
  local file=$1 start=$2 end=$3 legacy=$4
  awk -v start="$start" -v end="$end" -v legacy="$legacy" '
    $0 == start { if (open) { exit 1 } open = 1; next }
    ($0 == end || $0 == legacy) { if (!open) { exit 1 } open = 0; next }
    END { if (open) exit 1 }
  ' "$file"
}

# An explicit template so TMPDIR is honoured on macOS too, where a bare
# `mktemp` uses the Darwin per-user directory regardless. Prints the path.
# True when any of the given marker strings appears in the file. The repair gate
# cannot key on the start marker alone: an rc file carrying only an orphaned END
# marker has no start, so repair was skipped and a fresh block appended after
# the orphan -- leaving the file malformed and the new block unremovable.
markers_present() {
  local file=$1
  shift
  local m
  for m in "$@"; do
    if grep -Fq "$m" "$file"; then
      return 0
    fi
  done
  return 1
}

stage_file() {
  local tmp_base=${TMPDIR:-/tmp}
  tmp_base=${tmp_base%/}
  mktemp "$tmp_base/myprompts.XXXXXX"
}

# Overwrite $file with the staged copy. Writes into the existing file (not mv)
# so its mode, inode and symlink target survive; mktemp's 0600 temp file would
# otherwise tighten permissions and turn a symlinked rc into a regular file.
# `cat "$tmp" > "$file"` truncates $file before it can discover the staged copy
# is unusable, so keep a backup to restore from if the write fails partway.
# $3 permits a legitimately empty result -- an rc file that was nothing but
# marker lines repairs to empty, and the guard would otherwise block the only
# thing that can heal it.
commit_staged() {
  local file=$1 tmp=$2 allow_empty=${3:-0}
  if [[ $allow_empty -eq 0 && ! -s $tmp ]]; then
    warn "Staged update was empty; leaving ${file/#$HOME/~} unchanged."
    rm -f "$tmp"
    return 1
  fi
  local backup="$tmp.orig"
  cp "$file" "$backup" 2>/dev/null || true
  if ! cat "$tmp" > "$file"; then
    warn "Write to ${file/#$HOME/~} failed; restoring the original."
    [[ -f $backup ]] && cat "$backup" > "$file"
    rm -f "$tmp" "$backup"
    return 1
  fi
  rm -f "$tmp" "$backup"
}

# Drop marker lines that have no partner, leaving everything else in place.
# Only the marker LINES go: the extent of an unterminated block is unknowable,
# so its body stays as ordinary content rather than being guessed at and
# deleted. Where a second start opens while one is still open, the EARLIER one
# is dropped -- that keeps the tighter pair, and dropping the later start
# instead would sweep the lines between the two into the block, where the next
# update would delete them.
strip_unpaired_markers() {
  local file=$1 start=$2 end=$3 legacy=$4
  local tmp
  if ! tmp=$(stage_file); then
    warn "Could not create a temporary file; leaving ${file/#$HOME/~} unchanged."
    return 1
  fi
  # Two passes over the same file: the first records the line numbers of
  # unpaired markers, the second prints everything else. `FNR == NR` is true
  # only on the first pass (on the second, NR is already past it).
  if ! awk -v start="$start" -v end="$end" -v legacy="$legacy" '
    FNR == NR {
      if ($0 == start) { if (open) { drop[open] = 1 } open = FNR; next }
      if ($0 == end || $0 == legacy) { if (open) { open = 0 } else { drop[FNR] = 1 } }
      next
    }
    FNR == 1 { if (open) { drop[open] = 1 } open = 0 }
    !(FNR in drop)
  ' "$file" "$file" >"$tmp"; then
    warn "Failed to stage the repair; leaving ${file/#$HOME/~} unchanged."
    rm -f "$tmp"
    return 1
  fi
  commit_staged "$file" "$tmp" 1
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
  # discarding the rest of the user's rc file.
  #
  # Repair the markers rather than appending a fresh block past the damage.
  # Appending kept the user's content but never healed the file: the orphan
  # survived, so every subsequent install appended again while remove_block --
  # which refuses to touch a malformed file -- could never clean any of it up.
  # The installer and the uninstaller took opposite actions on one condition,
  # and the block became unremovable.
  if markers_present "$file" "$marker" "$end_marker" "$legacy_end_marker" &&
     ! markers_well_formed "$file" "$marker" "$end_marker" "$legacy_end_marker"; then
    warn "Repairing a malformed myprompts block in ${file/#$HOME/~}: dropping unmatched marker lines, leaving your content in place."
    strip_unpaired_markers "$file" "$marker" "$end_marker" "$legacy_end_marker" || return 1
  fi
  if grep -F "$marker" "$file" >/dev/null 2>&1 &&
     markers_well_formed "$file" "$marker" "$end_marker" "$legacy_end_marker"; then
    info "Updating existing block in ${file/#$HOME/~}."
    local tmp
    if ! tmp=$(stage_file); then
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
    commit_staged "$file" "$tmp" || return 1
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
