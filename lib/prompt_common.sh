#!/usr/bin/env bash
# Shell-agnostic prompt helpers. Sourced by both the bash and zsh prompts.
# Emits RAW escape sequences; callers wrap them for their own shell.

# Resolve our own directory so we can find themes/ regardless of cwd.
# Must not use zsh-only expansions here: this file is sourced by bash too, and
# ${(%):-%x} is a bad substitution under bash.
if [ -z "${MP_ROOT_DIR:-}" ]; then
    if [ -n "${BASH_SOURCE:-}" ]; then
        _mp_self=${BASH_SOURCE[0]}
    else
        _mp_self=$0          # zsh sets $0 to the sourced file
    fi
    MP_LIB_DIR=$(cd "$(dirname "$_mp_self")" && pwd)
    MP_ROOT_DIR=$(dirname "$MP_LIB_DIR")
    unset _mp_self
fi

mp_truecolor() {
    case "${COLORTERM:-}" in
        truecolor|24bit) return 0 ;;
        *) return 1 ;;
    esac
}

# mp_fg <256index>:<hex>  -> raw SGR foreground sequence
mp_fg() {
    local pair=$1
    local idx=${pair%%:*}
    local hex=${pair#*:}
    if mp_truecolor; then
        printf '\033[38;2;%d;%d;%dm' \
            "$((0x${hex:0:2}))" "$((0x${hex:2:2}))" "$((0x${hex:4:2}))"
    else
        printf '\033[38;5;%sm' "$idx"
    fi
}

mp_reset() { printf '\033[0m'; }
mp_bold()  { printf '\033[1m'; }

# mp_load_theme [name]
mp_load_theme() {
    local name=${1:-${MYPROMPTS_THEME:-signalmine}}
    local file="$MP_ROOT_DIR/themes/$name.sh"
    if [ ! -f "$file" ]; then
        file="$MP_ROOT_DIR/themes/signalmine.sh"
    fi
    # shellcheck source=/dev/null
    # Path is resolved at runtime from MP_ROOT_DIR, which is only known at
    # source time -- shellcheck cannot follow it statically.
    . "$file"
}

# mp_git_segment -> "[branch]" or "[branch*]" or "[@abc1234]" or nothing.
# Exactly one subprocess. --untracked-files=no keeps it fast in large trees.
mp_git_segment() {
    if [ "${MYPROMPTS_GIT:-1}" = "0" ]; then
        return 0
    fi
    local out head oid line dirty=0
    out=$(git status --porcelain=v2 --branch --untracked-files=no 2>/dev/null) || return 0
    head=""
    oid=""
    while IFS= read -r line; do
        case "$line" in
            '# branch.head '*) head=${line#\# branch.head } ;;
            '# branch.oid '*)  oid=${line#\# branch.oid } ;;
            '#'*) ;;
            ?*) dirty=1 ;;
        esac
    done <<EOF
$out
EOF
    [ -n "$head" ] || return 0
    if [ "$head" = "(detached)" ]; then
        head="@${oid:0:7}"
    fi
    if [ "$dirty" -eq 1 ]; then
        printf '[%s*]' "$head"
    else
        printf '[%s]' "$head"
    fi
}
