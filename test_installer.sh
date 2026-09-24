#!/usr/bin/env bash
# Test suite for myprompts installer
# Tests for common issues like unbound variables with set -u

set -euo pipefail

# Shared assertions and counters. This file used to define its own copies,
# which drifted from the shared ones and reported "12 run, 9 passed, all tests
# passed!" -- see the accounting invariant in test_summary.
# shellcheck disable=SC1091 # test_helpers.sh is committed alongside this script
source ./test_helpers.sh

# Create a test environment
setup_test_env() {
    TEST_DIR=$(mktemp -d)
    export HOME="$TEST_DIR"
    export INSTALL_ROOT="$TEST_DIR/.local/share/myprompts"
    export MYPROMPTS_NONINTERACTIVE=1
}

cleanup_test_env() {
    if [[ -d ${TEST_DIR:-} ]]; then
        rm -rf "$TEST_DIR"
    fi
}

# Test functions

test_empty_array_handling() {
    test_start "empty array handling with set -u"

    # Test empty array expansion
    if (
        set -euo pipefail
        local empty_array=()

        # This should not cause "unbound variable" error
        if [[ ${#empty_array[@]} -gt 0 ]]; then
            for item in "${empty_array[@]}"; do
                echo "$item"
            done
        fi

        # Test parameter expansion for empty arrays. The scalar assignment is
        # intentional: this mirrors the empty-array expansion install.sh performs
        # under set -u, and the test only proves it does not throw an unbound
        # error — the joined value itself is never used.
        local result
        # shellcheck disable=SC2124  # scalar-from-array join is the pattern under test
        result=${empty_array[@]+"${empty_array[@]}"}
        : "$result"

    ) 2>/dev/null
    then
        test_pass
    else
        test_fail "Empty array caused unbound variable error"
    fi
}

test_filter_missing_packages_empty() {
    test_start "filter_missing_packages with all installed"

    setup_test_env

    # Source the function
    # shellcheck disable=SC1091  # install.sh is present at runtime; shellcheck cannot follow it without -x
    source ./install.sh 2>/dev/null || true

    # Mock brew command to say everything is installed
    brew() {
        if [[ $1 == "list" ]]; then
            return 0  # Success means installed
        fi
    }
    export -f brew

    # Test with packages that are all "installed". Capture stdout only: the
    # function's return value is the list of packages still to install (empty
    # here), while its "already installed; skipping" notices go to stderr by
    # design. Folding stderr in with 2>&1 would defeat that and never be empty.
    local result
    result=$(filter_missing_packages brew_formulae gh nmap netcat) || {
        test_fail "Function failed"
        cleanup_test_env
        return
    }

    # Result should be empty
    if [[ -z $result ]]; then
        test_pass
    else
        test_fail "Expected empty result, got: $result"
    fi

    cleanup_test_env
}

test_ansible_args_empty() {
    test_start "ansible_args empty array on macOS"

    if (
        set -euo pipefail

        # Simulate the fixed code
        local ansible_args=()
        local os="macos"

        if [[ $os == linux ]]; then
            ansible_args+=(-b)
        fi

        # This should not fail with empty array. As above, the scalar join is
        # the pattern under test; the built string is only checked for not
        # throwing under set -u.
        # shellcheck disable=SC2124  # scalar-from-array join is the pattern under test
        local cmd="ansible-playbook test.yml ${ansible_args[@]+"${ansible_args[@]}"}"
        : "$cmd"

    ) 2>/dev/null
    then
        test_pass
    else
        test_fail "Empty ansible_args caused error"
    fi
}

test_packages_array_iteration() {
    test_start "packages array iteration safety"

    if (
        set -euo pipefail

        # Test the pattern used in filter_missing_packages
        local packages=()
        local result=()

        # Should handle empty packages array
        for pkg in ${packages[@]+"${packages[@]}"}; do
            result+=("$pkg")
        done

        # Should handle empty result array
        if [[ ${#result[@]} -gt 0 ]]; then
            for pkg in "${result[@]}"; do
                echo "$pkg" >/dev/null
            done
        fi

    ) 2>/dev/null
    then
        test_pass
    else
        test_fail "Package array iteration failed"
    fi
}

test_bash_compatibility() {
    test_start "bash 3.2 compatibility"

    # Check for bash 4+ features that shouldn't be present
    if grep -E '\$\{[^}]+(\^\^?|,,?)\}' install.sh >/dev/null 2>&1; then
        test_fail "Found bash 4+ case conversion syntax"
    else
        test_pass
    fi
}

test_installer_noninteractive() {
    test_start "full installer non-interactive mode"

    setup_test_env

    # Run installer in non-interactive mode
    if HOME="$TEST_DIR" \
       INSTALL_ROOT="$TEST_DIR/.myprompts" \
       MYPROMPTS_NONINTERACTIVE=1 \
       PROMPT_VARIANT=bash \
       PROMPT_STYLE=compact \
       bash ./install.sh >/dev/null 2>&1; then
        test_pass
    else
        test_fail "Installer failed in non-interactive mode"
    fi

    cleanup_test_env
}

test_reinstall_flow() {
    test_start "reinstall flow"

    setup_test_env

    # First install
    HOME="$TEST_DIR" \
    INSTALL_ROOT="$TEST_DIR/.myprompts" \
    MYPROMPTS_NONINTERACTIVE=1 \
    bash ./install.sh >/dev/null 2>&1

    # Reinstall should fail in non-interactive mode
    if HOME="$TEST_DIR" \
       INSTALL_ROOT="$TEST_DIR/.myprompts" \
       MYPROMPTS_NONINTERACTIVE=1 \
       bash ./install.sh >/dev/null 2>&1; then
        test_fail "Reinstall should fail in non-interactive mode"
    else
        # This is expected behavior
        test_pass
    fi

    cleanup_test_env
}

# Guard for the neofetch -> fastfetch migration: neofetch was archived
# upstream in 2024 and is no longer packaged by Homebrew, apt, dnf or pacman,
# so any surviving *use* of it is a package install or a file path that fails.
#
# Scoped to the executable surface -- package lists, installer, uninstaller,
# lib modules, playbook. Prose that explains the migration (README, CLAUDE.md,
# the header comments in the ported configs, docs/) is deliberately out of
# scope: describing what was replaced is not the same as still calling it.
# The bootstrap path (curl | bash) is otherwise only covered by manual runs.
# curl speaks file://, so a local tarball exercises fetch + re-exec with no
# network: MYPROMPTS_REPO becomes a file:// base and the tarball is placed at
# the exact path the installer builds.
make_bootstrap_fixture() {
    local dir=$1
    mkdir -p "$dir/archive"
    # Name the tarball after a SHA-shaped ref, not a branch. If the installer
    # still builds ".../archive/refs/heads/<ref>.tar.gz" the fetch 404s, which
    # is the bug: tags and commit SHAs live at different paths and only the
    # generic /archive/<ref>.tar.gz form resolves for all three.
    tar -czf "$dir/archive/deadbeefcafe.tar.gz" \
        --exclude='.git' --exclude='./.git' \
        -s '/^\./myprompts-deadbeefcafe/' . 2>/dev/null ||
    tar -czf "$dir/archive/deadbeefcafe.tar.gz" \
        --exclude='.git' --transform 's,^\./,myprompts-deadbeefcafe/,' . 2>/dev/null
}

test_bootstrap_fetches_non_branch_ref_and_cleans_up() {
    test_start "bootstrap resolves a non-branch ref and removes its temp dir"
    local T fixture tmphome tmpdir
    T=$(mktemp -d); fixture="$T/fixture"; tmphome="$T/home"; tmpdir="$T/tmp"
    mkdir -p "$fixture" "$tmphome" "$tmpdir"

    if ! make_bootstrap_fixture "$fixture"; then
        test_fail "could not build the bootstrap tarball fixture"
        rm -rf "$T"; return
    fi

    # Pipe install.sh on stdin so BASH_SOURCE is unset and the bootstrap takes
    # the fetch-and-re-exec path rather than using the adjacent lib/.
    local rc=0
    env -i PATH="$PATH" HOME="$tmphome" TMPDIR="$tmpdir" SHELL=/bin/bash \
        MYPROMPTS_NONINTERACTIVE=1 PROMPT_STYLE=compact \
        INSTALL_ROOT="$tmphome/ir" \
        MYPROMPTS_REPO="file://$fixture" MYPROMPTS_REF=deadbeefcafe \
        bash < install.sh >/dev/null 2>&1 || rc=$?

    if [[ $rc -ne 0 ]]; then
        test_fail "bootstrap install failed (rc=$rc); the non-branch ref did not resolve"
        rm -rf "$T"; return
    fi
    if [[ ! -f "$tmphome/ir/vaporwave_bash_prompt" ]]; then
        test_fail "bootstrap install did not place the prompt files"
        rm -rf "$T"; return
    fi
    local leftover
    leftover=$(find "$tmpdir" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l | tr -d ' ')
    rm -rf "$T"
    assert_eq "0" "$leftover" "temp directories left behind by the bootstrap"
}

# cleanup() removes the directory named by MYPROMPTS_TMP_SRC. The variable is
# exported by the bootstrap for its re-exec'd child, but nothing distinguished
# that from a value inherited from the caller's environment -- so running the
# installer from a clone with MYPROMPTS_TMP_SRC set in the environment deleted
# whatever it pointed at.
test_inherited_tmp_src_is_not_deleted() {
    test_start "an inherited MYPROMPTS_TMP_SRC is never deleted"
    local T; T=$(mktemp -d)
    mkdir -p "$T/precious" "$T/home"
    printf 'IRREPLACEABLE\n' > "$T/precious/data.txt"

    env HOME="$T/home" INSTALL_ROOT="$T/home/ir" MYPROMPTS_NONINTERACTIVE=1 \
        PROMPT_STYLE=compact SHELL=/bin/bash MYPROMPTS_TMP_SRC="$T/precious" \
        bash ./install.sh >/dev/null 2>&1 || true

    local survived=no
    [[ -f "$T/precious/data.txt" ]] && survived=yes
    rm -rf "$T"
    assert_eq "yes" "$survived" "caller's directory survived the install"
}

# Shape is not proof of ownership. A directory left behind by an earlier
# bootstrap that was killed has the same basename pattern AND the same sentinel
# file, so a later run inheriting MYPROMPTS_TMP_SRC pointed at it would delete
# it -- and anything a user had put inside. Ownership must be proven by a token
# this process generated, not by what the directory looks like.
test_stale_bootstrap_dir_is_not_deleted() {
    test_start "a stale bootstrap directory is not deleted when inherited"
    local T; T=$(mktemp -d)
    local stale="$T/myprompts.abcdef"
    mkdir -p "$stale" "$T/home"
    printf 'old-token-from-a-dead-run\n' > "$stale/.myprompts-bootstrap"
    printf 'IRREPLACEABLE\n' > "$stale/data.txt"

    env HOME="$T/home" INSTALL_ROOT="$T/home/ir" MYPROMPTS_NONINTERACTIVE=1 \
        PROMPT_STYLE=compact SHELL=/bin/bash MYPROMPTS_TMP_SRC="$stale" \
        bash ./install.sh >/dev/null 2>&1 || true

    local survived=no
    [[ -f "$stale/data.txt" ]] && survived=yes
    rm -rf "$T"
    assert_eq "yes" "$survived" "stale bootstrap directory survived the install"
}

# The token is passed through the environment, so a caller can supply a
# matching MYPROMPTS_TMP_SRC, MYPROMPTS_TMP_TOKEN and sentinel together and
# satisfy every check. Ownership has to rest on something the caller cannot
# fabricate: whether this process is actually running from inside that
# directory.
test_forged_token_does_not_authorise_deletion() {
    test_start "a caller-forged token does not authorise deletion"
    local T; T=$(mktemp -d)
    local forged="$T/myprompts.abcdef"
    mkdir -p "$forged" "$T/home"
    printf 'forged-token-value\n' > "$forged/.myprompts-bootstrap"
    printf 'IRREPLACEABLE\n' > "$forged/data.txt"

    env HOME="$T/home" INSTALL_ROOT="$T/home/ir" MYPROMPTS_NONINTERACTIVE=1 \
        PROMPT_STYLE=compact SHELL=/bin/bash \
        MYPROMPTS_TMP_SRC="$forged" MYPROMPTS_TMP_TOKEN=forged-token-value \
        bash ./install.sh >/dev/null 2>&1 || true

    local survived=no
    [[ -f "$forged/data.txt" ]] && survived=yes
    rm -rf "$T"
    assert_eq "yes" "$survived" "caller-controlled directory survived"
}

test_no_neofetch_references() {
    test_start "no neofetch references remain in the executable surface"
    local hits
    hits=$(grep -rIl neofetch \
             install.sh uninstall.sh run_tests.sh config lib ansible themes \
             2>/dev/null || true)
    if [[ -z $hits ]]; then
        test_pass
    else
        test_fail "neofetch still referenced in: $(echo "$hits" | tr '\n' ' ')"
    fi
}

# The shipped configs must actually parse. fastfetch validates its JSONC and
# exits non-zero on a malformed config, which is the only check that proves
# the neofetch -> fastfetch port produced something usable.
test_fastfetch_configs_parse() {
    if ! command -v fastfetch >/dev/null 2>&1; then
        test_skip "shipped fastfetch configs parse" "fastfetch not installed"
        return
    fi
    local cfg
    for cfg in fastfetch/config-*.jsonc; do
        test_start "fastfetch parses $(basename "$cfg")"
        if fastfetch --config "$PWD/$cfg" --structure title --logo none >/dev/null 2>&1; then
            test_pass
        else
            test_fail "fastfetch rejected $cfg: $(fastfetch --config "$PWD/$cfg" --structure title --logo none 2>&1 | head -3)"
        fi
    done
}

# The whole point of boxfetch.sh is the border fastfetch cannot draw: values
# are variable length and fastfetch has no line-padding facility, so a right
# rail is only possible by measuring the rendered output. Assert the frame is
# actually rectangular -- every box row the same display width, closed at both
# ends -- because a drift in the width maths shows up as a ragged right edge.
test_boxfetch_draws_a_closed_box() {
    # test_skip does not resolve a started test, so guard before test_start.
    if ! command -v fastfetch >/dev/null 2>&1; then
        test_skip "boxfetch draws a rectangular closed box" "fastfetch not installed"
        return
    fi
    test_start "boxfetch draws a rectangular closed box"

    local out
    if ! out=$(BOXFETCH_CONFIG="$PWD/fastfetch/config-boxed.jsonc" \
               BOXFETCH_LOGO="$PWD/fastfetch/signalmine_60.txt" \
               BOXFETCH_COLUMNS=120 \
               bash "$PWD/fastfetch/boxfetch.sh" 2>&1); then
        test_fail "boxfetch exited non-zero: $(printf '%s' "$out" | head -3)"
        return
    fi

    # Strip colour, then walk from the info box's top border to its bottom
    # one. The logo carries its own small caption box, so key off the first
    # border wide enough to be the info frame rather than any border at all.
    local report
    report=$(printf '%s\n' "$out" | LC_ALL=C awk '
        { line = $0; gsub(/\033\[[0-9;]*m/, "", line) }
        !width && line ~ /\.-{20,}\.$/ { width = length(line); inbox = 1 }
        inbox {
            n++
            if (length(line) != width) ragged++
            if (line ~ /`-{20,}\047$/) inbox = 0
        }
        END {
            if (!width) print "no info box border found"
            else if (n < 5) print "too few box rows: " n
            else if (ragged) print ragged " of " n " box rows are not " width " wide"
            else print "ok " n " rows @ " width
        }')

    case $report in
        ok\ *) test_pass ;;
        *) test_fail "$report" ;;
    esac
}

test_fastfetch_config_backed_up() {
    test_start "install backs up a pre-existing fastfetch config"
    setup_test_env
    mkdir -p "$HOME/.config/fastfetch"
    printf 'ORIGINAL\n' >"$HOME/.config/fastfetch/config.jsonc"

    # setup_test_env exports MYPROMPTS_NONINTERACTIVE=1, and
    # handle_package_bootstrap returns early when INTERACTIVE is 0. So this
    # installs no packages. Do not add a skip flag; one is not needed.
    PROMPT_STYLE=compact bash ./install.sh >/dev/null 2>&1 || true

    local backup="$HOME/.config/fastfetch/config.jsonc.myprompts-backup"
    if [[ -f $backup ]] && [[ "$(cat "$backup")" == "ORIGINAL" ]]; then
        test_pass
    else
        test_fail "backup missing or wrong contents"
    fi
    cleanup_test_env
}

test_shellcheck() {
    if ! command -v shellcheck >/dev/null 2>&1; then
        test_skip "shellcheck validation" "shellcheck not installed"
        return
    fi
    test_start "shellcheck validation"

    if true; then
        # install.sh sources lib/*.sh via a runtime-computed path; shellcheck
        # only resolves those cross-file globals when both are passed together.
        if shellcheck install.sh lib/*.sh >/dev/null 2>&1; then
            test_pass
        else
            test_fail "Shellcheck found warnings at default severity"
        fi
    fi
}

# Main test runner
main() {
    echo "Running myprompts installer test suite..."
    echo "========================================"
    echo

    # Run tests
    test_empty_array_handling
    test_filter_missing_packages_empty
    test_ansible_args_empty
    test_packages_array_iteration
    test_bash_compatibility
    test_installer_noninteractive
    test_reinstall_flow
    test_fastfetch_config_backed_up
    test_bootstrap_fetches_non_branch_ref_and_cleans_up
    test_inherited_tmp_src_is_not_deleted
    test_stale_bootstrap_dir_is_not_deleted
    test_forged_token_does_not_authorise_deletion
    test_no_neofetch_references
    test_fastfetch_configs_parse
    test_boxfetch_draws_a_closed_box
    test_shellcheck

    echo
    echo "========================================"
    test_summary
}

# Run tests
main "$@"