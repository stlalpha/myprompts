#!/usr/bin/env bash
# Prompt behavior tests. Must pass under Bash 3.2 (the macOS system bash).
set -uo pipefail

cd "$(dirname "$0")" || exit 1
# shellcheck disable=SC1091 # test_helpers.sh is committed alongside this script
source ./test_helpers.sh

# Bash 3.2 is the floor: macOS ships 3.2.57 as /bin/bash.
BASH32=/bin/bash

# Returns the layout a given style string actually produces. The extended
# layout is the only one containing a newline, so that is the discriminator.
prompt_layout_for_style() {
    local ps1
    ps1=$("$BASH32" -c "MYPROMPTS_PROMPT_STYLE=$1 source ./vaporwave_bash_prompt 2>/dev/null; printf '%s' \"\$PS1\"")
    case "$ps1" in
        *$'\n'*) printf 'extended' ;;
        *) printf 'compact' ;;
    esac
}

# NOTE: bash does NOT abort on `bad substitution` inside a sourced file — it
# prints to stderr and keeps going, so `source` still returns 0. Asserting on
# the exit status would silently pass. Assert on stderr instead.
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

test_bash_prompt_sources_silently_under_bash32
test_bash_prompt_sets_ps1
test_bash_prompt_style_is_case_insensitive
test_summary
