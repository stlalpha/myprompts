#!/usr/bin/env bash
# Test suite for myprompts installer
# Tests for common issues like unbound variables with set -u

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Test framework functions
test_start() {
    local test_name=$1
    TESTS_RUN=$((TESTS_RUN + 1))
    echo -n "Testing $test_name... "
}

test_pass() {
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo -e "${GREEN}✓${NC}"
}

test_fail() {
    local message=$1
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo -e "${RED}✗${NC}"
    echo -e "  ${RED}Failed: $message${NC}"
}

# Create a test environment
setup_test_env() {
    TEST_DIR=$(mktemp -d)
    export HOME="$TEST_DIR"
    export INSTALL_ROOT="$TEST_DIR/.local/share/myprompts"
    export BASE_URL="file://$PWD"
    export MYPROMPTS_NONINTERACTIVE=1
    export CONFIG_TMP_DIR="$TEST_DIR/config"
    mkdir -p "$CONFIG_TMP_DIR"
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
    (
        set -euo pipefail
        local empty_array=()

        # This should not cause "unbound variable" error
        if [[ ${#empty_array[@]} -gt 0 ]]; then
            for item in "${empty_array[@]}"; do
                echo "$item"
            done
        fi

        # Test parameter expansion for empty arrays
        local result
        result=${empty_array[@]+"${empty_array[@]}"}

        test_pass
    ) 2>/dev/null || test_fail "Empty array caused unbound variable error"
}

test_filter_missing_packages_empty() {
    test_start "filter_missing_packages with all installed"

    setup_test_env

    # Source the function
    source ./install.sh 2>/dev/null || true

    # Mock brew command to say everything is installed
    brew() {
        if [[ $1 == "list" ]]; then
            return 0  # Success means installed
        fi
    }
    export -f brew

    # Test with packages that are all "installed"
    local result
    result=$(filter_missing_packages brew_formulae gh nmap netcat 2>&1) || {
        test_fail "Function failed: $result"
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

    (
        set -euo pipefail

        # Simulate the fixed code
        local ansible_args=()
        local os="macos"

        if [[ $os == linux ]]; then
            ansible_args+=(-b)
        fi

        # This should not fail with empty array
        local cmd="ansible-playbook test.yml ${ansible_args[@]+"${ansible_args[@]}"}"

        test_pass
    ) 2>/dev/null || test_fail "Empty ansible_args caused error"
}

test_packages_array_iteration() {
    test_start "packages array iteration safety"

    (
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

        test_pass
    ) 2>/dev/null || test_fail "Package array iteration failed"
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
       BASE_URL="file://$PWD" \
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
    BASE_URL="file://$PWD" \
    INSTALL_ROOT="$TEST_DIR/.myprompts" \
    MYPROMPTS_NONINTERACTIVE=1 \
    bash ./install.sh >/dev/null 2>&1

    # Reinstall should fail in non-interactive mode
    if HOME="$TEST_DIR" \
       BASE_URL="file://$PWD" \
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

test_shellcheck() {
    test_start "shellcheck validation"

    if command -v shellcheck >/dev/null 2>&1; then
        if shellcheck -S error install.sh >/dev/null 2>&1; then
            test_pass
        else
            test_fail "Shellcheck found errors"
        fi
    else
        echo -e "${YELLOW}SKIP${NC} (shellcheck not installed)"
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
    test_shellcheck

    echo
    echo "========================================"
    echo "Test Results:"
    echo "  Total: $TESTS_RUN"
    echo -e "  Passed: ${GREEN}$TESTS_PASSED${NC}"
    if [[ $TESTS_FAILED -gt 0 ]]; then
        echo -e "  Failed: ${RED}$TESTS_FAILED${NC}"
        exit 1
    else
        echo -e "  ${GREEN}All tests passed!${NC}"
    fi
}

# Run tests
main "$@"