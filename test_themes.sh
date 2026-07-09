#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")" || exit
# shellcheck disable=SC1091 # test_helpers.sh is committed alongside this script
source ./test_helpers.sh

BASH32=/bin/bash
ROLES="MP_ACCENT1 MP_ACCENT2 MP_ACCENT3 MP_OK MP_INFO MP_ERR MP_MUTED"

test_theme_defines_all_roles() {
    local theme=$1
    test_start "themes/$theme.sh defines every role"
    local missing=""
    for role in $ROLES; do
        local val
        val=$("$BASH32" -c "set -u; source ./themes/$theme.sh; printf '%s' \"\${$role:-}\"" 2>&1)
        [ -n "$val" ] || missing="$missing $role"
    done
    if [ -z "$missing" ]; then test_pass; else test_fail "missing:$missing"; fi
}

test_role_format() {
    test_start "roles use <256index>:<hex> format"
    local val
    # shellcheck disable=SC2016
    # Single quotes are intentional: $MP_ACCENT3 must expand inside the
    # nested bash -c, not in this outer shell.
    val=$("$BASH32" -c 'set -u; source ./themes/signalmine.sh; printf "%s" "$MP_ACCENT3"')
    assert_eq "198:FF0090" "$val" "signalmine MP_ACCENT3"
}

test_mp_fg_256() {
    test_start "mp_fg emits a 256-color code when COLORTERM is unset"
    local out
    # shellcheck disable=SC1007,SC2016
    # COLORTERM= clears the var for the subprocess (not an assignment typo);
    # single quotes keep $-expansion inside the nested bash -c.
    out=$(COLORTERM= "$BASH32" -c 'set -u; source ./lib/prompt_common.sh; mp_fg 198:FF0090' | cat -v)
    assert_eq '^[[38;5;198m' "$out" "256-color output"
}

test_mp_fg_truecolor() {
    test_start "mp_fg emits a 24-bit code when COLORTERM=truecolor"
    local out
    # shellcheck disable=SC2016
    # Single quotes are intentional: expansion happens in the nested bash -c.
    out=$(COLORTERM=truecolor "$BASH32" -c 'set -u; source ./lib/prompt_common.sh; mp_fg 198:FF0090' | cat -v)
    assert_eq '^[[38;2;255;0;144m' "$out" "truecolor output"
}

test_theme_fallback() {
    test_start "mp_load_theme falls back to signalmine for an unknown theme"
    local val
    # shellcheck disable=SC2016
    # Single quotes are intentional: expansion happens in the nested bash -c.
    val=$(MYPROMPTS_THEME=nonesuch "$BASH32" -c 'set -u; source ./lib/prompt_common.sh; mp_load_theme; printf "%s" "$MP_ACCENT3"')
    assert_eq "198:FF0090" "$val" "fallback palette"
}

test_theme_defines_all_roles signalmine
test_theme_defines_all_roles vaporwave
test_role_format
test_mp_fg_256
test_mp_fg_truecolor
test_theme_fallback
test_summary
