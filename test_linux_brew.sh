#!/usr/bin/env bash
# Homebrew-on-Linux (Task 12b) tests.
#
# The opt-in path is: MYPROMPTS_LINUX_BREW (or an interactive prompt)
#   -> select_linux_manager returns "brew"
#   -> handle_package_bootstrap fills pending_macos_brew_formulae and leaves
#      the apt/dnf/pacman arrays empty
#   -> generate_ansible_vars emits package_manager: "brew"
#   -> ansible/playbook.yml runs its Homebrew formulae task on Linux.
#
# Packages are NOT installed by the install_* functions in lib/packages.sh --
# those are dead code. Ansible does the installing, so the contract these tests
# assert is the vars file plus the playbook's `when` gates.

set -uo pipefail

cd "$(dirname "$0")" || exit 1
# shellcheck disable=SC1091 # test_helpers.sh is committed alongside this script
source ./test_helpers.sh

# Sourcing the libs needs the globals install.sh defines first.
load_libs() {
    INTERACTIVE=${INTERACTIVE:-0}
    PROMPT_FD=1
    pending_macos_brew_formulae=()
    pending_macos_brew_casks=()
    pending_macos_appstore_apps=()
    pending_linux_apt_packages=()
    pending_linux_dnf_packages=()
    pending_linux_pacman_packages=()
    pending_linux_paru_packages=()
    pending_linux_paru_blocked=()
    # shellcheck disable=SC2317,SC2329 # called by the sourced libs, not from here
    info() { :; }
    # shellcheck disable=SC2317,SC2329
    warn() { :; }
    # shellcheck disable=SC2317,SC2329
    error() { :; }
    # handle_package_bootstrap draws its UI with these.
    VW_RESET=''; VW_PINK=''; VW_CYAN=''; VW_PURPLE=''; VW_BLUE=''
    VW_ORANGE=''; VW_GREEN=''; VW_MAGENTA=''; VW_GRAY=''
    VW_SECTION_ICON='*'; VW_ITEM_ICON='-'; VW_INSTALLED_ICON='+'
    INSTALL_ROOT=${INSTALL_ROOT:-/nonexistent}
    # shellcheck disable=SC1091
    source ./lib/os.sh
    # shellcheck disable=SC1091
    source ./lib/ui.sh
    # shellcheck disable=SC1091
    source ./lib/packages.sh
    # shellcheck disable=SC1091
    source ./config/packages.sh
}

# --- the opt-in decision -------------------------------------------------

test_opt_in_selects_brew() {
    test_start "MYPROMPTS_LINUX_BREW=1 selects brew as the Linux manager"
    local got
    got=$(
        load_libs
        MYPROMPTS_LINUX_BREW=1 select_linux_manager
    )
    assert_eq "brew" "$got" "manager with the opt-in set"
}

# The default must be unchanged: this is the regression guard proving an
# existing Linux user's install still uses apt/dnf/pacman.
test_default_selects_native() {
    test_start "without the opt-in, the native manager is selected"
    local got native
    got=$(
        load_libs
        unset MYPROMPTS_LINUX_BREW
        select_linux_manager
    )
    native=$(load_libs; detect_linux_package_manager)
    assert_eq "$native" "$got" "manager with the opt-in unset"
}

test_explicit_off_selects_native() {
    test_start "MYPROMPTS_LINUX_BREW=0 selects the native manager"
    local got native
    got=$(
        load_libs
        MYPROMPTS_LINUX_BREW=0 select_linux_manager
    )
    native=$(load_libs; detect_linux_package_manager)
    assert_eq "$native" "$got" "manager with the opt-in explicitly off"
}

# --- PATH resolution -----------------------------------------------------

# Linuxbrew installs to /home/linuxbrew/.linuxbrew or ~/.linuxbrew, neither of
# which the original ensure_homebrew_in_path knew about. The candidate list is
# injectable so this can be exercised without those paths existing.
test_brew_path_resolution_covers_linuxbrew() {
    test_start "ensure_homebrew_in_path picks up a Linuxbrew location"
    local T; T=$(mktemp -d)
    mkdir -p "$T/home/linuxbrew/.linuxbrew/bin"
    cat > "$T/home/linuxbrew/.linuxbrew/bin/brew" <<'EOS'
#!/bin/sh
[ "$1" = shellenv ] && echo 'export MYPROMPTS_SHELLENV_RAN=1'
EOS
    chmod +x "$T/home/linuxbrew/.linuxbrew/bin/brew"

    local got
    got=$(
        load_libs
        MYPROMPTS_BREW_CANDIDATES="$T/home/linuxbrew/.linuxbrew/bin/brew"
        ensure_homebrew_in_path
        printf '%s' "${MYPROMPTS_SHELLENV_RAN:-no}"
    )
    rm -rf "$T"
    assert_eq "1" "$got" "shellenv evaluated from the Linuxbrew path"
}

test_brew_path_resolution_still_prefers_macos_paths() {
    test_start "ensure_homebrew_in_path is a no-op when no candidate exists"
    local got
    got=$(
        load_libs
        MYPROMPTS_BREW_CANDIDATES="/nonexistent/brew"
        ensure_homebrew_in_path
        printf '%s' "${MYPROMPTS_SHELLENV_RAN:-none}"
    )
    assert_eq "none" "$got" "no shellenv run when nothing is installed"
}

# --- the vars file the playbook reads ------------------------------------

test_vars_carry_brew_manager_on_linux() {
    test_start "generate_ansible_vars emits package_manager brew on Linux"
    local tmp out
    tmp=$(mktemp)
    out=$(
        load_libs
        # shellcheck disable=SC2030
        pending_macos_brew_formulae=(gh nmap)
        # shellcheck disable=SC1091
        source ./lib/ansible.sh
        generate_ansible_vars "$tmp" linux brew >/dev/null 2>&1
        cat "$tmp"
    )
    rm -f "$tmp"
    case "$out" in
        *'package_manager: "brew"'*)
            case "$out" in
                *gh*nmap*) test_pass ;;
                *) test_fail "brew formulae missing from the vars file: $out" ;;
            esac ;;
        *) test_fail "package_manager was not brew: $(printf '%s' "$out" | head -3 | tr '\n' ' ')" ;;
    esac
}

# --- the real bootstrap, on Linux ----------------------------------------

# These drive the actual handle_package_bootstrap rather than just the manager
# decision, so they only mean anything on Linux. ensure_homebrew and the
# ansible run are stubbed out AFTER sourcing -- otherwise the opt-in test would
# install Homebrew onto the CI runner.
linux_bootstrap_pending() {
    local opt_in=$1
    (
        INTERACTIVE=1
        load_libs
        # shellcheck disable=SC2317,SC2329
        ensure_homebrew() { :; }
        # shellcheck disable=SC2317,SC2329
        run_ansible_bootstrap() { :; }
        # shellcheck disable=SC2317,SC2329
        mark_packages_installed() { :; }
        # Decline the final install prompt: this asserts on the filtering, not
        # on running ansible.
        # shellcheck disable=SC2317,SC2329
        prompt_yes_no() { return 1; }
        export MYPROMPTS_LINUX_BREW="$opt_in"
        handle_package_bootstrap linux >/dev/null 2>&1
        # Read inside the same subshell that ran handle_package_bootstrap, so
        # nothing needs to escape it.
        # shellcheck disable=SC2031
        printf 'brew=%s native=%s\n' \
            "${#pending_macos_brew_formulae[@]}" \
            "$(( ${#pending_linux_apt_packages[@]} + ${#pending_linux_dnf_packages[@]} + ${#pending_linux_pacman_packages[@]} ))"
    )
}

test_linux_brew_bootstrap_replaces_native() {
    if [ "$(uname -s)" != Linux ]; then
        test_skip "opting in fills the brew array and leaves the native ones empty" "Linux only"
        return
    fi
    test_start "opting in fills the brew array and leaves the native ones empty"
    local out; out=$(linux_bootstrap_pending 1)
    case "$out" in
        brew=0*) test_fail "no brew formulae were queued: $out" ;;
        *native=0) test_pass ;;
        *) test_fail "native package arrays were populated alongside brew: $out" ;;
    esac
}

test_linux_native_bootstrap_unchanged() {
    if [ "$(uname -s)" != Linux ]; then
        test_skip "without the opt-in the native arrays are used and brew is untouched" "Linux only"
        return
    fi
    test_start "without the opt-in the native arrays are used and brew is untouched"
    local out; out=$(linux_bootstrap_pending 0)
    case "$out" in
        brew=0*native=0) test_fail "nothing was queued at all; the test proves nothing: $out" ;;
        brew=0*) test_pass ;;
        *) test_fail "brew formulae were queued without the opt-in: $out" ;;
    esac
}

# --- the playbook gates --------------------------------------------------

playbook_task_block() {
    awk -v want="$1" '
        $0 ~ "^    - name: " want "$" {found=1}
        found && /^    - name: / && $0 !~ "^    - name: " want "$" {exit}
        found {print}
    ' ansible/playbook.yml
}

test_playbook_formulae_task_runs_for_brew_manager() {
    test_start "playbook's Homebrew formulae task fires when package_manager is brew"
    local block; block=$(playbook_task_block "Install Homebrew formulae")
    if [ -z "$block" ]; then
        test_fail "could not locate the 'Install Homebrew formulae' task"
        return
    fi
    assert_contains "$block" "package_manager == 'brew'" "brew manager condition on the formulae task"
}

test_playbook_casks_stay_macos_only() {
    test_start "playbook's cask task stays macOS-only"
    local block; block=$(playbook_task_block "Install Homebrew casks")
    if [ -z "$block" ]; then
        test_fail "could not locate the 'Install Homebrew casks' task"
        return
    fi
    case "$block" in
        *"package_manager == 'brew'"*)
            test_fail "cask task was broadened to brew-on-Linux; Linuxbrew has no cask support" ;;
        *"target_os == 'macos'"*) test_pass ;;
        *) test_fail "cask task lost its macOS gate" ;;
    esac
}

# Real evaluation of the gate, when ansible is available. A grep proves the
# text is present; this proves ansible agrees the condition is true.
#
# Two traps here, both hit while writing this:
#   - `awk '/Install Homebrew formulae/,/^TASK/'` ends its range on the very
#     line it starts, because the task header itself begins with "TASK". The
#     body is never examined and the test passes vacuously.
#   - In --check mode a `command` task reports "skipping" whether it was gated
#     out or merely check-mode-skipped. Only -v distinguishes them, via
#     "skip_reason": "Conditional result was False".
test_playbook_gates_evaluate_under_ansible() {
    if ! command -v ansible-playbook >/dev/null 2>&1; then
        test_skip "ansible evaluates the brew gate on Linux" "ansible-playbook not installed"
        return
    fi
    test_start "ansible evaluates the brew gate on Linux"
    local body
    body=$(ansible-playbook ansible/playbook.yml --check --connection=local -i localhost, -v \
            -e target_os=linux -e package_manager=brew \
            -e '{"brew_formulae":["gh"],"brew_casks":[],"appstore_apps":[],"apt_packages":[],"dnf_packages":[],"pacman_packages":[],"paru_packages":[]}' \
            2>&1 | awk '/^TASK \[Install Homebrew formulae\]/{f=1;next} /^TASK \[/{f=0} f')
    if [ -z "$body" ]; then
        test_fail "could not capture the formulae task output"
        return
    fi
    case "$body" in
        *"Conditional result was False"*)
            test_fail "ansible gated out the formulae task for package_manager=brew on Linux: $(printf '%s' "$body" | head -1)" ;;
        *) test_pass ;;
    esac
}

test_opt_in_selects_brew
test_default_selects_native
test_explicit_off_selects_native
test_brew_path_resolution_covers_linuxbrew
test_brew_path_resolution_still_prefers_macos_paths
test_vars_carry_brew_manager_on_linux
test_linux_brew_bootstrap_replaces_native
test_linux_native_bootstrap_unchanged
test_playbook_formulae_task_runs_for_brew_manager
test_playbook_casks_stay_macos_only
test_playbook_gates_evaluate_under_ansible

test_summary
