#!/usr/bin/env bash
# Prompt behavior tests. Must pass under Bash 3.2 (the macOS system bash).
set -uo pipefail

cd "$(dirname "$0")" || exit 1
# shellcheck disable=SC1091 # test_helpers.sh is committed alongside this script
source ./test_helpers.sh

# Bash 3.2 is the floor: macOS ships 3.2.57 as /bin/bash. Overridable so the
# same suite can be pointed at a bash 5.x build locally to reproduce what CI
# sees on Linux.
BASH32=${BASH32:-/bin/bash}

# `timeout` is a GNU coreutils tool, not part of stock macOS -- only use it as
# a hang-guard when present, so a regression that reintroduces unbounded
# recursion doesn't wedge the whole suite. Fall back to running unbounded on
# a system without it (correct either way, just without the safety net).
run_bounded() {
    if command -v timeout >/dev/null 2>&1; then
        timeout 5 "$@"
    else
        "$@"
    fi
}

# PS0 is expanded only by an *interactive* shell's read-eval loop, and `bash
# -i -c 'script'` never enters that loop. Feeding the script on stdin does, so
# that is the only way to exercise PS0-based timing.
run_interactive() {
    run_bounded "$BASH32" -i 2>/dev/null
}

# PS0 arrived in bash 4.4. Below that the prompt falls back to a DEBUG trap,
# which carries a limitation the PS0 path does not (see the tests below).
bash32_supports_ps0() {
    # shellcheck disable=SC2016 # single-quoted: expands inside the nested bash, not here
    "$BASH32" -c '
        [ "${BASH_VERSINFO[0]}" -gt 4 ] ||
        { [ "${BASH_VERSINFO[0]}" -eq 4 ] && [ "${BASH_VERSINFO[1]}" -ge 4 ]; }' 2>/dev/null
}

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
    # shellcheck disable=SC2016 # single-quoted: expands inside the nested bash -c, not here
    out=$("$BASH32" -c '
        source ./vaporwave_bash_prompt >/dev/null 2>&1
        (exit 42); myprompts_build_ps1
        printf %s "$PS1"' 2>&1 | strip_ansi)
    assert_contains "$out" "42" "exit code 42 in PS1"
}

test_no_exit_status_on_success() {
    test_start "prompt omits the exit code after a successful command"
    local out
    # shellcheck disable=SC2016 # single-quoted: expands inside the nested bash -c, not here
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
    # shellcheck disable=SC2016 # single-quoted: expands inside the nested bash -c, not here
    out=$(MYPROMPTS_DURATION_MIN=5 "$BASH32" -c '
        source ./vaporwave_bash_prompt >/dev/null 2>&1
        myprompts_timer=$((SECONDS - 9)); myprompts_build_ps1
        printf %s "$PS1"' 2>&1 | strip_ansi)
    assert_contains "$out" "9s" "9s duration in PS1"
}

test_duration_segment_below_threshold() {
    test_start "prompt omits duration below MYPROMPTS_DURATION_MIN"
    local out
    # shellcheck disable=SC2016 # single-quoted: expands inside the nested bash -c, not here
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
    # shellcheck disable=SC2016 # single-quoted: expands inside the nested bash -c, not here
    out=$("$BASH32" -c '
        source ./vaporwave_bash_prompt >/dev/null 2>&1
        out=""
        myprompts_root_segment out 0
        printf %s "$out"' 2>&1 | strip_ansi)
    assert_contains "$out" "#" "root marker"
}

test_ssh_marker() {
    test_start "prompt shows an ssh marker when SSH_CONNECTION is set"
    local out
    # shellcheck disable=SC2016 # single-quoted: expands inside the nested bash -c, not here
    out=$(SSH_CONNECTION="1.2.3.4 5 6.7.8.9 22" "$BASH32" -c '
        source ./vaporwave_bash_prompt >/dev/null 2>&1
        out=""
        myprompts_ssh_segment out
        printf %s "$out"' 2>&1 | strip_ansi)
    assert_contains "$out" "ssh" "ssh marker"
}

# Contract: sourcing the prompt must never silence a DEBUG trap the user
# already had. This is asserted behaviourally -- by whether the user's trap
# body still runs -- because `trap -p DEBUG` is not readable from inside a
# sourced file and grepping its output proves nothing.
#
# The counter is reset AFTER sourcing: a pre-existing DEBUG trap fires during
# the source itself, so a boolean "did it ever fire" check passes even when
# sourcing subsequently destroys the trap.
test_user_debug_trap_survives_sourcing() {
    test_start "a pre-existing DEBUG trap still fires after sourcing"
    local out
    # shellcheck disable=SC2016 # single-quoted: expands inside the nested bash, not here
    out=$(run_bounded "$BASH32" -c '
        trap "COUNT=\$((COUNT+1))" DEBUG
        source ./vaporwave_bash_prompt >/dev/null 2>&1
        COUNT=0
        :
        printf "fired=%s" "$COUNT"' 2>&1)
    case "$out" in
        fired=0) test_fail "sourcing destroyed the user's DEBUG trap (it never fired again)" ;;
        fired=*) test_pass ;;
        *) test_fail "assertion error: unexpected probe output '$out'" ;;
    esac
}

# The timer must still arm when the user already has a DEBUG trap. On bash
# 4.4+ the prompt uses PS0, which is independent of DEBUG, so this holds. On
# bash 3.2 it cannot: a sourced file may not replace an inherited DEBUG trap
# there, so the user's trap wins and no duration is shown -- a documented
# platform limitation, not a regression.
test_timer_arms_with_pre_existing_debug_trap() {
    if ! bash32_supports_ps0; then
        test_skip "timer arms alongside a pre-existing DEBUG trap" \
                  "bash 3.2 cannot install a hook over an inherited DEBUG trap"
        return
    fi
    test_start "timer arms alongside a pre-existing DEBUG trap"
    local out
    # shellcheck disable=SC2016 # single-quoted heredoc: expands inside the nested bash, not here
    out=$(run_interactive <<'EOS' 2>&1
trap 'USERTRAP=1' DEBUG
source ./vaporwave_bash_prompt >/dev/null 2>&1
USERTRAP=
unset myprompts_timer
:
printf "timer=%s usertrap=%s\n" "${myprompts_timer:-none}" "${USERTRAP:-none}"
EOS
)
    case "$out" in
        *timer=none*) test_fail "timer never armed with a pre-existing DEBUG trap: $out" ;;
        *usertrap=none*) test_fail "user's DEBUG trap stopped firing: $out" ;;
        *timer=[0-9]*) test_pass ;;
        *) test_fail "assertion error: unexpected probe output '$out'" ;;
    esac
}

# The timer must arm in the ordinary case (no pre-existing DEBUG trap) on
# every supported bash, including 3.2.
test_timer_arms_without_pre_existing_trap() {
    test_start "timer arms when no DEBUG trap pre-exists"
    local out
    out=$(run_interactive <<'EOS' 2>&1
source ./vaporwave_bash_prompt >/dev/null 2>&1
unset myprompts_timer
:
printf "timer=%s\n" "${myprompts_timer:-none}"
EOS
)
    case "$out" in
        *timer=[0-9]*) test_pass ;;
        *timer=none*) test_fail "timer never armed: $out" ;;
        *) test_fail "assertion error: unexpected probe output '$out'" ;;
    esac
}

# Regression test for a real bug: an empty pre-existing DEBUG trap (the
# standard `trap '' DEBUG` idiom for disabling tracing) used to be recovered
# by string-trimming `trap -p` output, leaving a bare
# "; myprompts_timer_start" that bash rejects with a syntax error before
# every single command -- making the shell unusable.
test_debug_trap_empty_previous() {
    test_start "empty pre-existing DEBUG trap does not corrupt the shell"
    local err
    err=$(run_bounded "$BASH32" -c '
        trap "" DEBUG
        source ./vaporwave_bash_prompt 2>/dev/null
        :
        :' 2>&1 >/dev/null)
    if [ -n "$err" ]; then
        test_fail "sourcing with an empty prior DEBUG trap wrote to stderr: $err"
        return
    fi
    test_pass
}

# Regression test for a real bug: recovering the previous trap body by
# string-trimming did not understand bash's '\'' escaping for a single quote,
# so a body containing one silently defeated the whole mechanism. Asserted
# behaviourally: the user's trap must still run.
test_debug_trap_single_quote_previous() {
    test_start "pre-existing DEBUG trap containing a single quote still fires after sourcing"
    local out
    # shellcheck disable=SC2016 # single-quoted: expands inside the nested bash, not here
    out=$(run_bounded "$BASH32" -c '
        trap "MARK='"'"'yes'"'"'" DEBUG
        source ./vaporwave_bash_prompt >/dev/null 2>&1
        MARK=
        :
        printf "MARK=%s" "$MARK"' 2>&1)
    assert_contains "$out" "MARK=yes" "single-quote trap body still executed after sourcing"
}

# Regression test for a real bug: sourcing twice with a pre-existing trap
# used to recapture the already-installed dispatcher as "the previous trap",
# so the dispatcher called itself, which called itself, ... an unbounded
# recursion (and, if it terminated, the user's trap body running more than
# once per command).
#
# NOTE on the expected count: DEBUG fires before EVERY simple command,
# including the final "after=$COUNT" read itself, so the "before=;:;after="
# idiom counts two firings (one for ":", one for "after=$COUNT") even with
# zero sourcing -- that is plain bash trap semantics, not a myprompts defect.
# The real invariant is that this firing count must not change after sourcing
# once or twice: an extra recapture-as-previous bug would double it (or hang).
test_debug_trap_double_source_no_recursion() {
    test_start "double-sourcing with a pre-existing trap does not recurse or double-run it"
    local baseline single double
    # shellcheck disable=SC2016 # single-quoted: expands inside the nested bash -c, not here
    baseline=$(run_bounded "$BASH32" -c '
        COUNT=0
        trap "COUNT=\$((COUNT+1))" DEBUG
        before=$COUNT
        :
        after=$COUNT
        printf "%s" "$((after - before))"' 2>&1)
    # shellcheck disable=SC2016 # single-quoted: expands inside the nested bash -c, not here
    single=$(run_bounded "$BASH32" -c '
        COUNT=0
        trap "COUNT=\$((COUNT+1))" DEBUG
        source ./vaporwave_bash_prompt >/dev/null 2>&1
        before=$COUNT
        :
        after=$COUNT
        printf "%s" "$((after - before))"' 2>&1)
    # shellcheck disable=SC2016 # single-quoted: expands inside the nested bash -c, not here
    double=$(run_bounded "$BASH32" -c '
        COUNT=0
        trap "COUNT=\$((COUNT+1))" DEBUG
        source ./vaporwave_bash_prompt >/dev/null 2>&1
        source ./vaporwave_bash_prompt >/dev/null 2>&1
        before=$COUNT
        :
        after=$COUNT
        printf "%s" "$((after - before))"' 2>&1)
    if [ -z "$baseline" ] || [ "$baseline" -le 0 ] 2>/dev/null; then
        test_fail "assertion error: baseline firing count was not a positive number ('$baseline')"
    elif [ "$single" = "$baseline" ] && [ "$double" = "$baseline" ]; then
        test_pass
    else
        test_fail "trap firing count changed after sourcing (indicates double-run or recursion): baseline=$baseline single-source=$single double-source=$double"
    fi
}

# Structural regression guard for the fork constraint: myprompts_build_ps1
# must fork exactly once per draw (the sanctioned mp_git_segment/git status
# call). Any other "$(" appearing in the function body would reintroduce a
# gratuitous subprocess.
# `((x = a - b))` returns status 1 when the result is 0, so an arithmetic
# *command* on the elapsed-time line made myprompts_build_ps1's own status
# depend on whether the last command took zero seconds.
test_build_ps1_returns_success() {
    test_start "myprompts_build_ps1 returns success when elapsed is zero"
    local status
    # Two things make this actually catch the arithmetic-command form:
    #   - `unset SECONDS; SECONDS=0` turns SECONDS into an ordinary variable
    #     that stays 0, so `SECONDS - myprompts_timer` is deterministically 0
    #     and `((...))` returns status 1.
    #   - `set -e` turns that status into an abort, so the printf never runs
    #     and the captured output is empty. Without errexit the function would
    #     reach its final PS1 assignment and report 0 with the bug still there.
    # shellcheck disable=SC2016 # single-quoted: expands inside the nested bash, not here
    status=$("$BASH32" -c '
        set -e
        source ./vaporwave_bash_prompt >/dev/null 2>&1
        unset SECONDS
        SECONDS=0
        myprompts_timer=0
        myprompts_build_ps1 >/dev/null 2>&1
        printf %s "$?"' 2>&1)
    assert_eq "0" "$status" "exit status of myprompts_build_ps1 with a zero duration"
}

test_build_ps1_single_command_substitution() {
    test_start "myprompts_build_ps1 contains exactly one command substitution"
    local count
    # Match '$(' but NOT '$((': arithmetic expansion forks nothing, and
    # counting it forced the code into the `(( ))` arithmetic *command* form,
    # which returns status 1 whenever its result is 0. Guard the fork, not the
    # punctuation.
    # shellcheck disable=SC2016 # single-quoted grep pattern is a literal '$(', not an expansion
    count=$(awk '/^myprompts_build_ps1\(\)/,/^}/' vaporwave_bash_prompt | grep -c '\$([^(]')
    assert_eq "1" "$count" "command substitution count in myprompts_build_ps1"
}

test_exit_status_segment
test_no_exit_status_on_success
test_duration_segment_above_threshold
test_duration_segment_below_threshold
test_root_marker
test_ssh_marker
test_user_debug_trap_survives_sourcing
test_timer_arms_with_pre_existing_debug_trap
test_timer_arms_without_pre_existing_trap
test_debug_trap_empty_previous
test_debug_trap_single_quote_previous
test_debug_trap_double_source_no_recursion
test_build_ps1_returns_success
test_build_ps1_single_command_substitution

test_summary
