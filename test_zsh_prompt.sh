#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")" || exit 1
# shellcheck disable=SC1091 # test_helpers.sh is committed alongside this script
source ./test_helpers.sh

if ! command -v zsh >/dev/null 2>&1; then
    printf 'zsh not installed; skipping zsh prompt tests\n'
    exit 0
fi

test_zsh_prompt_sources() {
    test_start "vaporwave_zsh_prompt sources cleanly"
    local err
    if err=$(zsh -f -c 'source ./vaporwave_zsh_prompt' 2>&1); then
        test_pass
    else
        test_fail "sourcing failed: $err"
    fi
}

test_zsh_prompt_sets_prompt() {
    test_start "vaporwave_zsh_prompt sets a non-empty PROMPT"
    local out
    out=$(zsh -f -c 'source ./vaporwave_zsh_prompt >/dev/null 2>&1; print -rn -- "$PROMPT"')
    if [ -n "$out" ]; then test_pass; else test_fail "PROMPT was empty"; fi
}

test_zsh_exit_status() {
    test_start "zsh prompt shows the exit code of a failing command"
    local out
    out=$(zsh -f -c '
        source ./vaporwave_zsh_prompt >/dev/null 2>&1
        (exit 42); prompt_myprompts_precmd
        print -rn -- "$PROMPT"' | sed 's/\x1b\[[0-9;]*m//g')
    assert_contains "$out" "42" "exit code 42 in PROMPT"
}

test_zsh_duration() {
    test_start "zsh prompt shows duration above the threshold"
    local out
    out=$(MYPROMPTS_DURATION_MIN=5 zsh -f -c '
        source ./vaporwave_zsh_prompt >/dev/null 2>&1
        myprompts_timer=$((SECONDS - 9)); prompt_myprompts_precmd
        print -rn -- "$PROMPT"' | sed 's/\x1b\[[0-9;]*m//g')
    assert_contains "$out" "9s" "9s duration in PROMPT"
}

test_zsh_prompt_sources
test_zsh_prompt_sets_prompt
test_zsh_exit_status
test_zsh_duration
test_summary
