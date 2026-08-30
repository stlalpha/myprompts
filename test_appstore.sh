#!/usr/bin/env bash
# Mac App Store integration tests.
#
# This suite used to consist of five substring greps that never set an exit
# status. Deleting `mas` from the package list, renaming the appstore array and
# stripping `community.general.mas` from the playbook left all five printing a
# tick and the script exiting 0 -- "mas" matched inside "macos_brew_formulae",
# and so on. It could not detect any regression it was written to catch.
#
# These assert the path that actually runs. Note that the install_appstore_apps
# function in lib/packages.sh is dead code -- nothing calls it -- so asserting
# its existence proves nothing. The live path is:
#
#   config/packages.sh (macos_appstore_apps)
#     -> filter_missing_packages appstore
#     -> pending_macos_appstore_apps
#     -> generate_ansible_vars   (appstore_apps: in the vars file)
#     -> ansible/playbook.yml    (community.general.mas)

set -uo pipefail

cd "$(dirname "$0")" || exit 1
# shellcheck disable=SC1091 # test_helpers.sh is committed alongside this script
source ./test_helpers.sh

echo "Testing Mac App Store package support..."
echo "========================================"

# --- config/packages.sh declares what to install -------------------------

test_mas_in_brew_formulae() {
    test_start "mas is an element of macos_brew_formulae"
    local found
    found=$(
        # shellcheck disable=SC1091 # sourced for its arrays, as install.sh does
        source ./config/packages.sh
        for f in "${macos_brew_formulae[@]}"; do
            [ "$f" = "mas" ] && { printf yes; exit 0; }
        done
        printf no
    )
    assert_eq "yes" "$found" "mas present as a distinct array element"
}

test_appstore_array_populated() {
    test_start "macos_appstore_apps holds numeric app IDs"
    local ids
    ids=$(
        # shellcheck disable=SC1091 # sourced for its arrays, as install.sh does
        source ./config/packages.sh
        printf '%s' "${macos_appstore_apps[*]:-}"
    )
    if [ -z "$ids" ]; then
        test_fail "macos_appstore_apps is empty or undefined"
        return
    fi
    case "$ids" in
        *[!0-9\ ]*) test_fail "macos_appstore_apps contains a non-numeric entry: $ids" ;;
        *) test_pass ;;
    esac
}

# --- filter_missing_packages routes App Store IDs ------------------------

# Sourcing lib/packages.sh needs the globals install.sh defines before it.
load_packages_lib() {
    INTERACTIVE=0
    PROMPT_FD=0
    pending_macos_brew_formulae=()
    pending_macos_brew_casks=()
    pending_macos_appstore_apps=()
    pending_linux_apt_packages=()
    pending_linux_dnf_packages=()
    pending_linux_pacman_packages=()
    pending_linux_paru_packages=()
    pending_linux_paru_blocked=()
    # Silence the lib's output helpers. They are called by the sourced code,
    # not from here, which older shellcheck reports as SC2317 and newer as
    # SC2329 -- disable both so CI and local agree.
    # shellcheck disable=SC2317,SC2329
    info() { :; }
    # shellcheck disable=SC2317,SC2329
    warn() { :; }
    # shellcheck disable=SC2317,SC2329
    error() { :; }
    # shellcheck disable=SC1091 # committed alongside this script
    source ./lib/packages.sh
}

test_filter_handles_appstore() {
    test_start "filter_missing_packages accepts the appstore manager"
    local out
    # An ID that cannot be installed must come back as still-pending rather
    # than being silently dropped or crashing the filter.
    out=$(
        set +e
        load_packages_lib
        filter_missing_packages appstore 441258766 2>/dev/null
    )
    assert_contains "$out" "441258766" "uninstalled App Store ID survives filtering"
}

# --- the vars file the playbook actually reads ---------------------------

test_ansible_vars_emit_appstore_apps() {
    test_start "generate_ansible_vars writes appstore_apps into the vars file"
    local tmp out
    tmp=$(mktemp)
    out=$(
        load_packages_lib
        # Deliberately scoped to this subshell: generate_ansible_vars runs and
        # its output is read here too, so nothing needs to escape. Contrast
        # with a test_pass inside a subshell, which loses its counter.
        # shellcheck disable=SC2030
        pending_macos_appstore_apps=(441258766)
        # shellcheck disable=SC1091 # committed alongside this script
        source ./lib/ansible.sh
        generate_ansible_vars "$tmp" macos brew >/dev/null 2>&1
        cat "$tmp"
    )
    rm -f "$tmp"
    assert_contains "$out" "441258766" "app ID reaches the generated vars file"
}

test_ansible_vars_empty_appstore_is_valid() {
    test_start "generate_ansible_vars emits an empty list when no apps are pending"
    local tmp out
    tmp=$(mktemp)
    out=$(
        load_packages_lib
        # shellcheck disable=SC1091 # committed alongside this script
        source ./lib/ansible.sh
        generate_ansible_vars "$tmp" macos brew >/dev/null 2>&1
        cat "$tmp"
    )
    rm -f "$tmp"
    case "$out" in
        *"appstore_apps:"*"[]"*) test_pass ;;
        *) test_fail "expected an empty appstore_apps list, got: $(printf '%s' "$out" | head -20 | tr '\n' ' ')" ;;
    esac
}

# --- the playbook consumes them ------------------------------------------

test_playbook_uses_mas_module() {
    test_start "playbook installs App Store apps via community.general.mas"
    if grep -Eq '^[[:space:]]*community\.general\.mas:' ansible/playbook.yml; then
        test_pass
    else
        test_fail "no community.general.mas task found in ansible/playbook.yml"
    fi
}

test_playbook_gates_mas_on_macos() {
    test_start "the mas task is gated on target_os == 'macos'"
    local block
    block=$(awk '/community\.general\.mas:/,/^$/' ansible/playbook.yml)
    assert_contains "$block" "target_os == 'macos'" "macOS gate on the mas task"
}

test_mas_in_brew_formulae
test_appstore_array_populated
test_filter_handles_appstore
test_ansible_vars_emit_appstore_apps
test_ansible_vars_empty_appstore_is_valid
test_playbook_uses_mas_module
test_playbook_gates_mas_on_macos

echo
echo "========================================"
test_summary
