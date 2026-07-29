#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")" || exit 1
# shellcheck disable=SC1091 # test_helpers.sh is committed alongside this script
source ./test_helpers.sh

test_uninstall_restores_rc_files_byte_identical() {
    test_start "uninstall restores rc files byte-identically"
    local T; T=$(mktemp -d)
    local repo="$PWD"

    printf '# my bashrc\nexport FOO=1\n' > "$T/.bashrc"
    printf '# my zshrc\nexport BAR=2\n'  > "$T/.zshrc"
    local bash_before zsh_before
    bash_before=$(cksum < "$T/.bashrc")
    zsh_before=$(cksum < "$T/.zshrc")

    ( cd "$repo" && HOME="$T" INSTALL_ROOT="$T/ir" BASE_URL="file://$repo" \
        MYPROMPTS_NONINTERACTIVE=1 PROMPT_STYLE=compact SHELL=/bin/bash \
        bash ./install.sh >/dev/null 2>&1 ) || true

    # Sanity: install must actually have modified .bashrc, else the test is vacuous.
    if [ "$(cksum < "$T/.bashrc")" = "$bash_before" ]; then
        test_fail "install did not modify .bashrc; test would be vacuous"
        rm -rf "$T"; return
    fi

    ( cd "$repo" && HOME="$T" INSTALL_ROOT="$T/ir" MYPROMPTS_NONINTERACTIVE=1 \
        bash ./uninstall.sh >/dev/null 2>&1 ) || true

    local bash_after zsh_after
    bash_after=$(cksum < "$T/.bashrc")
    zsh_after=$(cksum < "$T/.zshrc")

    if [ "$bash_before" = "$bash_after" ] && [ "$zsh_before" = "$zsh_after" ]; then
        test_pass
    else
        test_fail "rc files differ after uninstall"
        diff <(printf '# my bashrc\nexport FOO=1\n') "$T/.bashrc" || true
    fi
    rm -rf "$T"
}

test_uninstall_removes_install_root() {
    test_start "uninstall removes INSTALL_ROOT"
    local T; T=$(mktemp -d)
    local repo="$PWD"
    ( cd "$repo" && HOME="$T" INSTALL_ROOT="$T/ir" BASE_URL="file://$repo" \
        MYPROMPTS_NONINTERACTIVE=1 PROMPT_STYLE=compact SHELL=/bin/bash \
        bash ./install.sh >/dev/null 2>&1 ) || true
    ( cd "$repo" && HOME="$T" INSTALL_ROOT="$T/ir" MYPROMPTS_NONINTERACTIVE=1 \
        bash ./uninstall.sh >/dev/null 2>&1 ) || true
    if [ ! -d "$T/ir" ]; then test_pass; else test_fail "$T/ir still exists"; fi
    rm -rf "$T"
}

test_uninstall_restores_neofetch_backup() {
    test_start "uninstall restores the neofetch config from backup"
    local T; T=$(mktemp -d)
    local repo="$PWD"
    mkdir -p "$T/.config/neofetch"
    printf 'ORIGINAL\n' > "$T/.config/neofetch/config.conf"
    ( cd "$repo" && HOME="$T" INSTALL_ROOT="$T/ir" BASE_URL="file://$repo" \
        MYPROMPTS_NONINTERACTIVE=1 PROMPT_STYLE=compact SHELL=/bin/bash \
        bash ./install.sh >/dev/null 2>&1 ) || true
    ( cd "$repo" && HOME="$T" INSTALL_ROOT="$T/ir" MYPROMPTS_NONINTERACTIVE=1 \
        bash ./uninstall.sh >/dev/null 2>&1 ) || true
    assert_eq "ORIGINAL" "$(cat "$T/.config/neofetch/config.conf" 2>/dev/null)" "restored config"
    local backup="$T/.config/neofetch/config.conf.myprompts-backup"
    if [ -f "$backup" ]; then
        test_fail "backup file still exists after restore"
    fi
    rm -rf "$T"
}

test_uninstall_idempotent_on_clean_system() {
    test_start "uninstall is a no-op on a clean system"
    local T; T=$(mktemp -d)
    local repo="$PWD"
    local rc
    rc=0
    ( cd "$repo" && HOME="$T" INSTALL_ROOT="$T/ir" MYPROMPTS_NONINTERACTIVE=1 \
        bash ./uninstall.sh >/dev/null 2>&1 ) || rc=$?
    if [ "$rc" -eq 0 ] && [ ! -e "$T/.bashrc" ] && [ ! -e "$T/.zshrc" ] && [ ! -d "$T/ir" ]; then
        test_pass
    else
        test_fail "uninstall on clean system exited $rc or created files"
    fi
    rm -rf "$T"
}

test_uninstall_restores_rc_files_byte_identical
test_uninstall_removes_install_root
test_uninstall_restores_neofetch_backup
test_uninstall_idempotent_on_clean_system
test_summary
