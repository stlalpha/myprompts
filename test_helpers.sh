#!/usr/bin/env bash
# Shared assertions for the myprompts test suite.

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

test_start() {
    TESTS_RUN=$((TESTS_RUN + 1))
    printf 'Testing %s... ' "$1"
}

test_skip() {
    TESTS_SKIPPED=$((TESTS_SKIPPED + 1))
    printf 'Testing %s... SKIPPED (%s)\n' "$1" "$2"
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
    printf '\n%s run, %s passed, %s failed, %s skipped\n' "$TESTS_RUN" "$TESTS_PASSED" "$TESTS_FAILED" "$TESTS_SKIPPED"
    # Accounting invariant: every started test must resolve exactly once.
    # A test_pass called inside a subshell -- ( ... ) or $( ... ) -- increments
    # a copy of the counter that dies with the subshell, so the tick still
    # prints while the total silently drifts. That reads as "12 run, 9 passed,
    # all tests passed!", which is nonsense a reader will either believe or
    # ignore. Fail loudly instead. test_skip deliberately does not touch
    # TESTS_RUN, so skips are excluded from this check.
    local resolved=$((TESTS_PASSED + TESTS_FAILED))
    if [ "$resolved" -ne "$TESTS_RUN" ]; then
        printf '%bACCOUNTING ERROR: %s tests started but %s resolved -- a test_pass/test_fail was lost, most likely inside a subshell%b\n' \
            "$RED" "$TESTS_RUN" "$resolved" "$NC"
        return 1
    fi
    [ "$TESTS_FAILED" -eq 0 ]
}
