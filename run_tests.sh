#!/usr/bin/env bash
# Single entry point for the test suite. Runs every test_*.sh file that
# exists and reports pass/fail per file plus an aggregate result.
# Deliberately not `set -e`: we want every suite to run even if an earlier
# one fails, then report which ones failed at the end.
set -uo pipefail
cd "$(dirname "$0")" || exit 1

failed=0

for t in test_themes.sh test_prompts.sh test_zsh_prompt.sh test_uninstall.sh test_installer.sh test_appstore.sh test_linux_brew.sh; do
    if [ ! -f "$t" ]; then
        printf '\n=== %s (skipped: not found) ===\n' "$t"
        continue
    fi

    printf '\n=== %s ===\n' "$t"
    if bash "$t"; then
        printf '=== %s: PASS ===\n' "$t"
    else
        printf '=== %s: FAIL ===\n' "$t"
        failed=1
    fi
done

if [ "$failed" -ne 0 ]; then
    printf '\nSuite FAILED\n'
    exit 1
fi

printf '\nSuite passed\n'
