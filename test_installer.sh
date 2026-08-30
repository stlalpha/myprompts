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
    test_no_neofetch_references
    test_fastfetch_configs_parse
    test_shellcheck

    echo
    echo "========================================"
    test_summary
}

# Run tests
main "$@"