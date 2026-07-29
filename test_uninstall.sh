#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")" || exit 1
# shellcheck disable=SC1091 # test_helpers.sh is committed alongside this script
source ./test_helpers.sh

# Portable octal permission bits: BSD/macOS stat and GNU/Linux stat take
# different flags, so try both.
rc_mode() {
    stat -f '%Lp' "$1" 2>/dev/null || stat -c '%a' "$1"
}

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

test_uninstall_preserves_trailing_blank_line_byte_identical() {
    test_start "uninstall preserves a pre-existing trailing blank line (byte-identical round trip)"
    local T; T=$(mktemp -d)
    local repo="$PWD"

    # Both rc files already end in a blank line before install.sh ever touches
    # them. append_block only ever contributes one blank line ahead of its
    # marker; if strip_block ate every buffered blank line instead of just
    # the one append_block owns, this pre-existing trailing blank would be
    # lost on uninstall.
    printf '# my bashrc\nexport FOO=1\n\n' > "$T/.bashrc"
    # shellcheck disable=SC2016 # single-quoted: literal $HOME/$ZSH text belongs in the seeded .zshrc, not expanded here
    printf '# .zshrc\nexport ZSH="$HOME/.oh-my-zsh"\nplugins=(git)\nsource "$ZSH/oh-my-zsh.sh"\n\nalias ll="ls -la"\n\n' > "$T/.zshrc"
    local bash_before zsh_before
    bash_before=$(cksum < "$T/.bashrc")
    zsh_before=$(cksum < "$T/.zshrc")

    ( cd "$repo" && HOME="$T" INSTALL_ROOT="$T/ir" BASE_URL="file://$repo" \
        MYPROMPTS_NONINTERACTIVE=1 PROMPT_STYLE=compact SHELL=/bin/bash \
        bash ./install.sh >/dev/null 2>&1 ) || true

    # Sanity: install must actually have modified the rc files, else the test is vacuous.
    if [ "$(cksum < "$T/.bashrc")" = "$bash_before" ]; then
        test_fail "install did not modify .bashrc; test would be vacuous"
        rm -rf "$T"; return
    fi
    if [ "$(cksum < "$T/.zshrc")" = "$zsh_before" ]; then
        test_fail "install did not modify .zshrc; test would be vacuous"
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
        test_fail "rc files with a pre-existing trailing blank line differ after uninstall"
        diff <(printf '# my bashrc\nexport FOO=1\n\n') "$T/.bashrc" || true
    fi
    rm -rf "$T"
}

test_uninstall_preserves_foreign_lines_before_and_after_blocks() {
    test_start "uninstall preserves foreign lines before, between, and after stripped blocks"
    local T; T=$(mktemp -d)
    local repo="$PWD"

    # Hand-craft a .bashrc as if myprompts blocks were already installed
    # (the exact shape append_block produces: one blank line, then the
    # marker span), interleaved with lines myprompts never touched. Only
    # 3 of the 5 known markers are present; the other 2 must be no-ops.
    {
        printf '# foreign top line\n'
        printf 'export BEFORE=1\n'
        printf '\n'
        printf '# >>> myprompts prompt >>>\n'
        printf 'source "%s/vaporwave_bash_prompt"\n' "$T/ir"
        printf '# <<< myprompts prompt <<<\n'
        printf '\n'
        printf '# >>> myprompts prompt style >>>\n'
        printf 'export MYPROMPTS_PROMPT_STYLE=compact\n'
        printf '# <<< myprompts prompt style <<<\n'
        printf '\n'
        printf '# foreign middle line\n'
        printf 'export MIDDLE=1\n'
        printf '\n'
        printf '# >>> myprompts lscolors >>>\n'
        printf 'source "%s/vaporwave_ls_setup.sh"\n' "$T/ir"
        printf '# <<< myprompts lscolors <<<\n'
        printf '\n'
        printf 'export AFTER=1\n'
        printf '# foreign bottom line\n'
    } > "$T/.bashrc"

    printf '# foreign top line\nexport BEFORE=1\n\n# foreign middle line\nexport MIDDLE=1\n\nexport AFTER=1\n# foreign bottom line\n' \
        > "$T/.bashrc.expected"

    ( cd "$repo" && HOME="$T" INSTALL_ROOT="$T/ir" MYPROMPTS_NONINTERACTIVE=1 \
        bash ./uninstall.sh >/dev/null 2>&1 ) || true

    if cmp -s "$T/.bashrc" "$T/.bashrc.expected"; then
        test_pass
    else
        test_fail "foreign lines around blocks were not preserved exactly"
        diff "$T/.bashrc.expected" "$T/.bashrc" || true
    fi
    rm -rf "$T"
}

test_uninstall_preserves_rc_permissions() {
    test_start "uninstall preserves the rc file's original permissions"
    local T; T=$(mktemp -d)
    local repo="$PWD"

    printf '# x\n\n# >>> myprompts prompt >>>\nsource /x\n# <<< myprompts prompt <<<\n' > "$T/.bashrc"
    chmod 644 "$T/.bashrc"
    local before after
    before=$(rc_mode "$T/.bashrc")

    ( cd "$repo" && HOME="$T" INSTALL_ROOT="$T/none" MYPROMPTS_NONINTERACTIVE=1 \
        bash ./uninstall.sh >/dev/null 2>&1 ) || true

    after=$(rc_mode "$T/.bashrc")
    assert_eq "$before" "$after" "rc file permissions changed after uninstall"
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
test_uninstall_preserves_trailing_blank_line_byte_identical
test_uninstall_preserves_foreign_lines_before_and_after_blocks
test_uninstall_preserves_rc_permissions
test_uninstall_removes_install_root
test_uninstall_restores_neofetch_backup
test_uninstall_idempotent_on_clean_system
test_summary
