#!/usr/bin/env bash
# Prompt behavior tests. Must pass under Bash 3.2 (the macOS system bash).
set -uo pipefail

cd "$(dirname "$0")" || exit 1
# shellcheck disable=SC1091 # test_helpers.sh is committed alongside this script
source ./test_helpers.sh

# Bash 3.2 is the floor: macOS ships 3.2.57 as /bin/bash.
BASH32=/bin/bash

# Interrogate the actual bash under test (not the shell running this script —
# on Linux CI /bin/bash is typically 5.x, so the 3.2-only regression this
# suite was written for cannot reproduce there).
bash32_version=$("$BASH32" --version | head -n 1 | grep -Eo '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -n 1)
bash32_major=${bash32_version%%.*}

if [ -n "$bash32_major" ] && [ "$bash32_major" -ge 4 ] 2>/dev/null; then
    printf '[env] %s is %s — bash 3.2 regression coverage: NO (macOS runner provides it)\n' "$BASH32" "$bash32_version"
else
    printf '[env] %s is %s — bash 3.2 regression coverage: YES\n' "$BASH32" "$bash32_version"
fi

# Returns the layout a given style string actually produces. The extended
# layout is the only one containing a newline, so that is the discriminator.
# An empty result means the nested bash never assigned PS1 at all (e.g. it
# crashed before reaching the assignment) — report that as 'error' rather
# than silently falling back to 'compact', which would let the assertion
# pass vacuously.
prompt_layout_for_style() {
    local ps1
    ps1=$("$BASH32" -c "MYPROMPTS_PROMPT_STYLE=$1 source ./vaporwave_bash_prompt 2>/dev/null; printf '%s' \"\$PS1\"")
    case "$ps1" in
        '') printf 'error' ;;
        *$'\n'*) printf 'extended' ;;
        *) printf 'compact' ;;
    esac
}

# NOTE: bash does NOT abort on `bad substitution` inside a sourced file — it
# prints to stderr and keeps going, so `source` still returns 0. Asserting on
# the exit status would silently pass. Assert on stderr instead.
# Static, platform-independent check: bash-4-only case-modification parameter
# expansions (${var,,}, ${var,}, ${var^^}, ${var^}) are a hard "bad
# substitution" under bash 3.2. This must fail on any bash, macOS or Linux.
test_no_bash4_only_syntax() {
    test_start "vaporwave_bash_prompt has no bash-4-only case-modification expansions"
    if grep -Eq '\$\{[A-Za-z_][A-Za-z0-9_]*(\^\^|,,|\^|,)\}' vaporwave_bash_prompt; then
        test_fail "found \${var,,}/\${var,}/\${var^^}/\${var^} — bash 4+ only, breaks under bash 3.2"
    else
        test_pass
    fi
}

test_bash_prompt_sources_silently_under_bash32() {
    test_start "vaporwave_bash_prompt sources without stderr output under bash 3.2"
    local err
    err=$("$BASH32" -c 'MYPROMPTS_PROMPT_STYLE=compact source ./vaporwave_bash_prompt' 2>&1 >/dev/null)
    if [ -z "$err" ]; then
        test_pass
    else
        test_fail "sourcing wrote to stderr: $err"
    fi
}

test_bash_prompt_sets_ps1() {
    test_start "vaporwave_bash_prompt sets a non-empty PS1"
    local out
    # shellcheck disable=SC2016 # single-quoted: $PS1 must expand inside the nested bash -c, not here
    out=$("$BASH32" -c 'MYPROMPTS_PROMPT_STYLE=compact source ./vaporwave_bash_prompt >/dev/null 2>&1; printf %s "${PS1:-}"' 2>&1)
    if [ -n "$out" ]; then test_pass; else test_fail "PS1 was empty"; fi
}

# The failed `${style,,}` assignment leaves $style uppercased, so an uppercase
# style silently falls through to the compact branch.
test_bash_prompt_style_is_case_insensitive() {
    local s
    for s in extended EXTENDED Extended; do
        test_start "MYPROMPTS_PROMPT_STYLE=$s selects the extended layout"
        assert_eq "extended" "$(prompt_layout_for_style "$s")" "layout for style '$s'"
    done
    test_start "MYPROMPTS_PROMPT_STYLE=compact selects the compact layout"
    assert_eq "compact" "$(prompt_layout_for_style compact)" "layout for style 'compact'"
}

if [ -n "$bash32_major" ] && [ "$bash32_major" -ge 4 ] 2>/dev/null; then
    test_skip "bash 3.2 regression reproduction" "\$BASH32 is bash $bash32_version, not 3.2 — cannot reproduce the bad-substitution symptom here"
fi

test_no_bash4_only_syntax
test_bash_prompt_sources_silently_under_bash32
test_bash_prompt_sets_ps1
test_bash_prompt_style_is_case_insensitive

export MYPROMPTS_THEME=signalmine
export MYPROMPTS_PROMPT_STYLE=compact

# Strip SGR sequences so assertions match on visible text only.
strip_ansi() { sed 's/\x1b\[[0-9;]*m//g'; }

test_exit_status_segment() {
    test_start "prompt shows the exit code of a failing command"
    local out
    out=$("$BASH32" -c '
        source ./vaporwave_bash_prompt >/dev/null 2>&1
        (exit 42); myprompts_build_ps1
        printf %s "$PS1"' 2>&1 | strip_ansi)
    assert_contains "$out" "42" "exit code 42 in PS1"
}

test_no_exit_status_on_success() {
    test_start "prompt omits the exit code after a successful command"
    local out
    out=$("$BASH32" -c '
        source ./vaporwave_bash_prompt >/dev/null 2>&1
        true; myprompts_build_ps1
        printf %s "$PS1"' 2>&1 | strip_ansi)
    case "$out" in
        *✗*) test_fail "failure marker present after success: $out" ;;
        *) test_pass ;;
    esac
}

test_duration_segment_above_threshold() {
    test_start "prompt shows duration above MYPROMPTS_DURATION_MIN"
    local out
    out=$(MYPROMPTS_DURATION_MIN=5 "$BASH32" -c '
        source ./vaporwave_bash_prompt >/dev/null 2>&1
        myprompts_timer=$((SECONDS - 9)); myprompts_build_ps1
        printf %s "$PS1"' 2>&1 | strip_ansi)
    assert_contains "$out" "9s" "9s duration in PS1"
}

test_duration_segment_below_threshold() {
    test_start "prompt omits duration below MYPROMPTS_DURATION_MIN"
    local out
    out=$(MYPROMPTS_DURATION_MIN=5 "$BASH32" -c '
        source ./vaporwave_bash_prompt >/dev/null 2>&1
        myprompts_timer=$((SECONDS - 1)); myprompts_build_ps1
        printf %s "$PS1"' 2>&1 | strip_ansi)
    case "$out" in
        *1s*) test_fail "duration shown below threshold: $out" ;;
        *) test_pass ;;
    esac
}

test_root_marker() {
    test_start "prompt shows a root marker when EUID is 0"
    local out
    out=$("$BASH32" -c '
        source ./vaporwave_bash_prompt >/dev/null 2>&1
        myprompts_root_segment 0' 2>&1 | strip_ansi)
    assert_contains "$out" "#" "root marker"
}

test_ssh_marker() {
    test_start "prompt shows an ssh marker when SSH_CONNECTION is set"
    local out
    out=$(SSH_CONNECTION="1.2.3.4 5 6.7.8.9 22" "$BASH32" -c '
        source ./vaporwave_bash_prompt >/dev/null 2>&1
        myprompts_ssh_segment' 2>&1 | strip_ansi)
    assert_contains "$out" "ssh" "ssh marker"
}

test_debug_trap_chains() {
    test_start "DEBUG trap chains rather than clobbering a pre-existing trap"
    local out
    out=$("$BASH32" -c '
        trap "MARKER=touched" DEBUG
        source ./vaporwave_bash_prompt >/dev/null 2>&1
        trap -p DEBUG' 2>&1)
    assert_contains "$out" "MARKER=touched" "original DEBUG trap preserved"
}

test_exit_status_segment
test_no_exit_status_on_success
test_duration_segment_above_threshold
test_duration_segment_below_threshold
test_root_marker
test_ssh_marker
test_debug_trap_chains

test_summary
