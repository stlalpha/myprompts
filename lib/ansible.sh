#!/usr/bin/env bash
# Ansible-driven package bootstrap.
# Expects: MYPROMPTS_SRC, INSTALL_ROOT, and the pending_* arrays from install.sh.
# shellcheck disable=SC2154  # MYPROMPTS_SRC, INSTALL_ROOT, pending_* come from install.sh

generate_ansible_vars() {
  local file=$1
  local os=$2
  local mgr=${3:-}

  {
    printf "target_os: \"%s\"\n" "$os"
    printf "package_manager: \"%s\"\n" "$mgr"

    printf "brew_formulae:\n"
    if [[ ${#pending_macos_brew_formulae[@]} -gt 0 ]]; then
      for pkg in "${pending_macos_brew_formulae[@]}"; do
        [[ -z $pkg ]] && continue
        printf "  - %s\n" "$pkg"
      done
    else
      printf "  []\n"
    fi

    printf "brew_casks:\n"
    if [[ ${#pending_macos_brew_casks[@]} -gt 0 ]]; then
      for pkg in "${pending_macos_brew_casks[@]}"; do
        [[ -z $pkg ]] && continue
        printf "  - %s\n" "$pkg"
      done
    else
      printf "  []\n"
    fi

    printf "appstore_apps:\n"
    if [[ ${#pending_macos_appstore_apps[@]} -gt 0 ]]; then
      for app_id in "${pending_macos_appstore_apps[@]}"; do
        [[ -z $app_id ]] && continue
        printf "  - %s\n" "$app_id"
      done
    else
      printf "  []\n"
    fi

    printf "apt_packages:\n"
    if [[ ${#pending_linux_apt_packages[@]} -gt 0 ]]; then
      for pkg in "${pending_linux_apt_packages[@]}"; do
        [[ -z $pkg ]] && continue
        printf "  - %s\n" "$pkg"
      done
    else
      printf "  []\n"
    fi

    printf "dnf_packages:\n"
    if [[ ${#pending_linux_dnf_packages[@]} -gt 0 ]]; then
      for pkg in "${pending_linux_dnf_packages[@]}"; do
        [[ -z $pkg ]] && continue
        printf "  - %s\n" "$pkg"
      done
    else
      printf "  []\n"
    fi

    printf "pacman_packages:\n"
    if [[ ${#pending_linux_pacman_packages[@]} -gt 0 ]]; then
      for pkg in "${pending_linux_pacman_packages[@]}"; do
        [[ -z $pkg ]] && continue
        printf "  - %s\n" "$pkg"
      done
    else
      printf "  []\n"
    fi

    printf "paru_packages:\n"
    if [[ ${#pending_linux_paru_packages[@]} -gt 0 ]]; then
      for pkg in "${pending_linux_paru_packages[@]}"; do
        [[ -z $pkg ]] && continue
        printf "  - %s\n" "$pkg"
      done
    else
      printf "  []\n"
    fi
  } >"$file"
}

download_ansible_assets() {
  local dest="$INSTALL_ROOT/ansible"
  mkdir -p "$dest"
  if [[ ! -f "$MYPROMPTS_SRC/ansible/playbook.yml" ]]; then
    warn "Ansible playbook missing from source tree; skipping package bootstrap."
    return 1
  fi
  install -m 644 "$MYPROMPTS_SRC/ansible/playbook.yml" "$dest/playbook.yml"
  return 0
}

ensure_ansible() {
  local os=$1
  local mgr=${2:-}
  if command -v ansible-playbook >/dev/null 2>&1; then
    return 0
  fi

  case "$os" in
    macos)
      ensure_homebrew
      info "Installing Ansible via Homebrew."
      if ! brew list --formula ansible >/dev/null 2>&1; then
        brew install ansible
      fi
      ;;
    linux)
      case "$mgr" in
        apt)
          info "Installing Ansible via apt."
          sudo apt-get update -y
          sudo apt-get install -y ansible
          ;;
        dnf)
          info "Installing Ansible via dnf."
          sudo dnf install -y ansible
          ;;
        pacman)
          info "Installing Ansible via pacman."
          sudo pacman -Sy --noconfirm ansible
          ;;
        *)
          warn "Unknown package manager; install Ansible manually."
          return 1
          ;;
      esac
      ;;
    *)
      warn "Unsupported OS for automatic Ansible installation."
      return 1
      ;;
  esac

  if ! command -v ansible-playbook >/dev/null 2>&1; then
    warn "Ansible installation failed; skipping package bootstrap."
    return 1
  fi
  return 0
}

run_ansible_bootstrap() {
  local os=$1
  local mgr=${2:-}

  if ! download_ansible_assets; then
    return
  fi

  if ! ensure_ansible "$os" "$mgr"; then
    return
  fi

  # Install required Ansible collections if requirements file exists
  local requirements_file="$INSTALL_ROOT/ansible/requirements.yml"
  if [[ -f "$MYPROMPTS_SRC/ansible/requirements.yml" ]]; then
    install -m 644 "$MYPROMPTS_SRC/ansible/requirements.yml" "$requirements_file"
    info "Installing required Ansible collections..."
    ansible-galaxy collection install -r "$requirements_file" --force >/dev/null 2>&1 || true
  fi

  local vars_file="$INSTALL_ROOT/ansible/ansible_vars.yml"
  generate_ansible_vars "$vars_file" "$os" "$mgr"

  local playbook="$INSTALL_ROOT/ansible/playbook.yml"
  if [[ ! -f $playbook ]]; then
    warn "Ansible playbook missing at $playbook; skipping package bootstrap."
    return
  fi

  # Only request sudo for Linux systems that need it
  local ansible_args=()
  if [[ $os == linux ]]; then
    ansible_args+=(-b)
    if ! sudo -n true 2>/dev/null; then
      ansible_args+=(-K)
    fi
  fi

  # Use ${ansible_args[@]+"${ansible_args[@]}"} to handle empty array with set -u
  ANSIBLE_NOCOWS=1 ANSIBLE_FORCE_COLOR=1 ansible-playbook -i localhost, -c local -e "@$vars_file" "$playbook" ${ansible_args[@]+"${ansible_args[@]}"}
}
