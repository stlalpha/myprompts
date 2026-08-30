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

# install.sh / uninstall.sh must succeed. Masking their exit status with
# `|| true` lets a test pass when the command died before changing anything --
# which is how a truncating uninstall stayed green. These record the status so
# a caller can fail the test explicitly.
run_install() {
    local home=$1; shift
    ( cd "$PWD" && HOME="$home" INSTALL_ROOT="$home/ir" \
        MYPROMPTS_NONINTERACTIVE=1 PROMPT_STYLE=compact SHELL=/bin/bash \
        bash ./install.sh >/dev/null 2>&1 )
}

run_uninstall() {
    local home=$1; shift
    ( cd "$PWD" && HOME="$home" INSTALL_ROOT="$home/ir" MYPROMPTS_NONINTERACTIVE=1 \
        bash ./uninstall.sh >/dev/null 2>&1 )
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

    if ! run_install "$T"; then
        test_fail "install.sh failed"; rm -rf "$T"; return
    fi

    # Sanity: install must actually have modified .bashrc, else the test is vacuous.
    if [ "$(cksum < "$T/.bashrc")" = "$bash_before" ]; then
        test_fail "install did not modify .bashrc; test would be vacuous"
        rm -rf "$T"; return
    fi

    if ! run_uninstall "$T"; then
        test_fail "uninstall.sh failed"; rm -rf "$T"; return
    fi

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

    if ! run_install "$T"; then
        test_fail "install.sh failed"; rm -rf "$T"; return
    fi

    # Sanity: install must actually have modified the rc files, else the test is vacuous.
    if [ "$(cksum < "$T/.bashrc")" = "$bash_before" ]; then
        test_fail "install did not modify .bashrc; test would be vacuous"
        rm -rf "$T"; return
    fi
    if [ "$(cksum < "$T/.zshrc")" = "$zsh_before" ]; then
        test_fail "install did not modify .zshrc; test would be vacuous"
        rm -rf "$T"; return
    fi

    if ! run_uninstall "$T"; then
        test_fail "uninstall.sh failed"; rm -rf "$T"; return
    fi

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

    if ! run_uninstall "$T"; then
        test_fail "uninstall.sh failed"; rm -rf "$T"; return
    fi

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

    # INSTALL_ROOT deliberately points at a path that does not exist; uninstall
    # must still succeed and must not touch the rc file's mode.
    if ! ( cd "$repo" && HOME="$T" INSTALL_ROOT="$T/none" MYPROMPTS_NONINTERACTIVE=1 \
        bash ./uninstall.sh >/dev/null 2>&1 ); then
        test_fail "uninstall.sh failed against a missing INSTALL_ROOT"; rm -rf "$T"; return
    fi

    after=$(rc_mode "$T/.bashrc")
    assert_eq "$before" "$after" "rc file permissions changed after uninstall"
    rm -rf "$T"
}

test_uninstall_removes_install_root() {
    test_start "uninstall removes INSTALL_ROOT"
    local T; T=$(mktemp -d)
    local repo="$PWD"
    if ! run_install "$T"; then
        test_fail "install.sh failed"; rm -rf "$T"; return
    fi
    if ! run_uninstall "$T"; then
        test_fail "uninstall.sh failed"; rm -rf "$T"; return
    fi
    if [ ! -d "$T/ir" ]; then test_pass; else test_fail "$T/ir still exists"; fi
    rm -rf "$T"
}

test_uninstall_restores_fastfetch_backup() {
    test_start "uninstall restores the fastfetch config from backup"
    local T; T=$(mktemp -d)
    local repo="$PWD"
    mkdir -p "$T/.config/fastfetch"
    printf 'ORIGINAL\n' > "$T/.config/fastfetch/config.jsonc"
    if ! run_install "$T"; then
        test_fail "install.sh failed"; rm -rf "$T"; return
    fi
    if ! run_uninstall "$T"; then
        test_fail "uninstall.sh failed"; rm -rf "$T"; return
    fi
    assert_eq "ORIGINAL" "$(cat "$T/.config/fastfetch/config.jsonc" 2>/dev/null)" "restored config"
    local backup="$T/.config/fastfetch/config.jsonc.myprompts-backup"
    if [ -f "$backup" ]; then
        test_fail "backup file still exists after restore"
    fi
    rm -rf "$T"
}

# Regression test for real data loss: both block editors decide a block is
# present by finding its opening marker, then let awk run to EOF looking for the
# closing one. If a user edits or deletes the "# <<< myprompts NAME <<<" line,
# in_block never clears and every following line of the rc file is discarded.
# Reproduced against the shipped uninstall.sh: a 5-line .bashrc came back as 1.
test_uninstall_keeps_content_when_end_marker_missing() {
    test_start "uninstall preserves rc content when the end marker is missing"
    local T; T=$(mktemp -d)
    local repo="$PWD"

    # An rc file whose closing marker the user removed, with their own content
    # after it -- exactly the shape that used to get truncated.
    {
        printf 'export IMPORTANT_BEFORE=1\n'
        printf '# >>> myprompts prompt >>>\n'
        printf 'source ~/.local/share/myprompts/vaporwave_bash_prompt\n'
        printf 'export IMPORTANT_AFTER=1\n'
        printf "alias deploy='make deploy'\n"
    } > "$T/.bashrc"

    if ! run_uninstall "$T"; then
        test_fail "uninstall.sh failed"; rm -rf "$T"; return
    fi

    local after; after=$(cat "$T/.bashrc")
    rm -rf "$T"
    case "$after" in
        *IMPORTANT_AFTER*)
            case "$after" in
                *"alias deploy"*) test_pass ;;
                *) test_fail "uninstall discarded the user's alias after an unterminated block" ;;
            esac ;;
        *) test_fail "uninstall discarded user content after an unterminated block: $(printf '%s' "$after" | tr '\n' '|')" ;;
    esac
}

# Same hazard on the install side: append_block's awk rewrite runs whenever the
# opening marker is found, so an unterminated block truncated the rc file on
# reinstall.
test_install_keeps_content_when_end_marker_missing() {
    test_start "install preserves rc content when the end marker is missing"
    local T; T=$(mktemp -d)
    local repo="$PWD"

    {
        printf 'export IMPORTANT_BEFORE=1\n'
        printf '# >>> myprompts prompt >>>\n'
        printf 'source ~/.local/share/myprompts/vaporwave_bash_prompt\n'
        printf 'export IMPORTANT_AFTER=1\n'
        printf "alias deploy='make deploy'\n"
    } > "$T/.bashrc"

    if ! run_install "$T"; then
        test_fail "install.sh failed"; rm -rf "$T"; return
    fi

    local after; after=$(cat "$T/.bashrc")
    rm -rf "$T"
    case "$after" in
        *IMPORTANT_AFTER*"alias deploy"*) test_pass ;;
        *) test_fail "install discarded user content after an unterminated block: $(printf '%s' "$after" | tr '\n' '|')" ;;
    esac
}

# append_block's update path uses a temp file. Written back with `mv`, the rc
# file inherits mktemp's 0600 -- and a symlinked rc (a dotfiles-repo setup) is
# replaced by a regular file, so the user's repo silently stops receiving
# changes. uninstall.sh already documents this hazard and writes with `cat`.
#
# These call append_block directly rather than running install.sh twice: a
# non-interactive reinstall refuses ("run interactively to confirm reinstall"),
# so a reinstall-based test never reaches the update path and passes vacuously.
load_shell_lib() {
    INTERACTIVE=0
    PROMPT_FD=1
    # shellcheck disable=SC2317,SC2329 # called by the sourced lib, not from here
    info() { :; }
    # shellcheck disable=SC2317,SC2329
    warn() { :; }
    # shellcheck disable=SC2317,SC2329
    error() { :; }
    # shellcheck disable=SC1091 # committed alongside this script
    source ./lib/shell.sh
}

test_append_block_update_preserves_mode() {
    test_start "append_block's update path preserves rc file permissions"
    local T; T=$(mktemp -d)
    local marker="# >>> myprompts prompt >>>"
    {
        printf '# my bashrc\n'
        printf '%s\n' "$marker"
        printf 'source old\n'
        printf '%s\n' "${marker/>>>/<<<}"
    } > "$T/.bashrc"
    chmod 644 "$T/.bashrc"

    local mode
    mode=$(
        HOME="$T"
        load_shell_lib
        append_block "$T/.bashrc" "$marker" "source new" >/dev/null 2>&1
        rc_mode "$T/.bashrc"
    )
    rm -rf "$T"
    assert_eq "644" "$mode" "rc mode after append_block update"
}

test_append_block_update_preserves_symlink() {
    test_start "append_block's update path keeps a symlinked rc a symlink"
    local T; T=$(mktemp -d)
    local marker="# >>> myprompts prompt >>>"
    mkdir -p "$T/dotfiles"
    {
        printf '# my bashrc\n'
        printf '%s\n' "$marker"
        printf 'source old\n'
        printf '%s\n' "${marker/>>>/<<<}"
    } > "$T/dotfiles/bashrc"
    ln -s "$T/dotfiles/bashrc" "$T/.bashrc"

    local result
    result=$(
        HOME="$T"
        load_shell_lib
        append_block "$T/.bashrc" "$marker" "source new" >/dev/null 2>&1
        if [ -L "$T/.bashrc" ] && grep -q "source new" "$T/dotfiles/bashrc" 2>/dev/null; then
            printf 'ok'
        elif [ -L "$T/.bashrc" ]; then
            printf 'link-but-target-unchanged'
        else
            printf 'symlink-replaced'
        fi
    )
    rm -rf "$T"
    assert_eq "ok" "$result" "symlinked rc survives an append_block update"
}

# append_block derived its end marker with ${marker/>>>/<<<}, which replaces
# only the FIRST occurrence -- writing "# <<< NAME >>>" while strip_block looked
# for "# <<< NAME <<<". The two never matched, so strip_block's awk ran to EOF
# and uninstall only produced the right bytes because the blocks happen to sit
# at the end of the file. Assert the markers agree.
test_install_writes_symmetric_end_marker() {
    test_start "install writes a symmetric end marker"
    local T; T=$(mktemp -d)
    local repo="$PWD"
    printf '# my bashrc\n' > "$T/.bashrc"
    if ! run_install "$T"; then
        test_fail "install.sh failed"; rm -rf "$T"; return
    fi
    # grep -c prints 0 AND exits 1 when nothing matches, so a `|| printf 0`
    # fallback would append a second zero. Count lines instead.
    local bad
    bad=$(grep -c '^# <<< myprompts .* >>>$' "$T/.bashrc" 2>/dev/null); bad=${bad:-0}
    bad=$(printf '%s' "$bad" | head -1)
    rm -rf "$T"
    assert_eq "0" "$bad" "asymmetric '# <<< NAME >>>' end markers written"
}

# rc files written by earlier versions carry the asymmetric end marker. They
# must still be removable, and removal must not eat what follows them.
test_uninstall_removes_legacy_end_marker_block() {
    test_start "uninstall removes a legacy-marker block without eating what follows"
    local T; T=$(mktemp -d)
    local repo="$PWD"
    {
        printf 'export BEFORE=1\n'
        printf '\n'
        printf '# >>> myprompts prompt >>>\n'
        printf 'source "%s/vaporwave_bash_prompt"\n' "$T/ir"
        printf '# <<< myprompts prompt >>>\n'
        printf 'export AFTER=1\n'
        printf "alias deploy='make deploy'\n"
    } > "$T/.bashrc"

    if ! run_uninstall "$T"; then
        test_fail "uninstall.sh failed"; rm -rf "$T"; return
    fi

    local after; after=$(cat "$T/.bashrc")
    rm -rf "$T"
    case "$after" in
        *myprompts*) test_fail "legacy block was not removed: $(printf '%s' "$after" | tr '\n' '|')" ;;
        *AFTER=1*"alias deploy"*) test_pass ;;
        *) test_fail "content after the legacy block was destroyed: $(printf '%s' "$after" | tr '\n' '|')" ;;
    esac
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
test_uninstall_restores_fastfetch_backup
test_uninstall_idempotent_on_clean_system
test_install_writes_symmetric_end_marker
test_uninstall_removes_legacy_end_marker_block
test_uninstall_keeps_content_when_end_marker_missing
test_install_keeps_content_when_end_marker_missing
test_append_block_update_preserves_mode
test_append_block_update_preserves_symlink
test_summary
