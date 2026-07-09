#!/usr/bin/env bash
# Shared assertions for the myprompts test suite.

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

test_start() {
    TESTS_RUN=$((TESTS_RUN + 1))
    printf 'Testing %s... ' "$1"
}

test_pass() {
    TESTS_PASSED=$((TESTS_PASSED + 1))
    printf '%b\n' "${GREEN}✓${NC}"
}

test_fail() {
    TESTS_FAILED=$((TESTS_FAILED + 1))
    printf '%b\n' "${RED}✗${NC}"
    printf '  %bFailed: %s%b\n' "${RED}" "$1" "${NC}"
}

assert_eq() {
    if [ "$1" = "$2" ]; then
        test_pass
    else
        test_fail "$3 (expected '$1', got '$2')"
    fi
}

assert_contains() {
    if [ -z "$2" ]; then
        test_fail "$3 (assertion error: empty needle)"
        return
    fi
    case "$1" in
        *"$2"*) test_pass ;;
        *) test_fail "$3 (expected '$1' to contain '$2')" ;;
    esac
}

test_summary() {
    printf '\n%s run, %s passed, %s failed\n' "$TESTS_RUN" "$TESTS_PASSED" "$TESTS_FAILED"
    [ "$TESTS_FAILED" -eq 0 ]
}
