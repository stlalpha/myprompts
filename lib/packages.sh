#!/usr/bin/env bash
# Package configuration loading and installation across package managers.
# Expects: MYPROMPTS_SRC, INSTALL_ROOT, INTERACTIVE, PROMPT_FD, the VW_* color
# variables, and the pending_* arrays from install.sh; and the macos_*/linux_*
# package arrays load_configuration sources at runtime from config/packages.sh.
# shellcheck disable=SC2154  # MYPROMPTS_SRC, INSTALL_ROOT, INTERACTIVE, PROMPT_FD, VW_*, pending_*, macos_*/linux_* package arrays come from install.sh or its sourced config

ensure_array() {
  local name=$1
  if ! declare -p "$name" >/dev/null 2>&1; then
    eval "$name=()"
  fi
}

load_configuration() {
  local packages_file="$MYPROMPTS_SRC/config/packages.sh"
  local aliases_file="$MYPROMPTS_SRC/config/aliases.sh"

  if [[ ! -f $packages_file ]]; then
    warn "Packages configuration not found; skipping package bootstrap."
  else
    # shellcheck source=/dev/null
    source "$packages_file"
  fi

  if [[ ! -f $aliases_file ]]; then
    warn "Aliases configuration not found; skipping alias updates."
  else
    # shellcheck source=/dev/null
    source "$aliases_file"
  fi

  ensure_array macos_brew_formulae
  ensure_array macos_brew_casks
  ensure_array macos_appstore_apps
  ensure_array linux_apt_packages
  ensure_array linux_dnf_packages
  ensure_array linux_pacman_packages
  ensure_array linux_paru_packages
  ensure_array zsh_aliases
  ensure_array bash_aliases
}

ensure_homebrew_in_path() {
  if [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -x /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi
}

ensure_homebrew() {
  if command -v brew >/dev/null 2>&1; then
    ensure_homebrew_in_path
    return
  fi

  info "Installing Homebrew (may prompt for your password)."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  ensure_homebrew_in_path
}

install_brew_formulae() {
  local packages=("$@")
  [[ ${#packages[@]} -eq 0 ]] && return
  info "Installing Homebrew formulae: ${packages[*]}"
  for pkg in "${packages[@]}"; do
    if brew list --formula "$pkg" >/dev/null 2>&1; then
      info "brew formula '$pkg' already installed."
    else
      brew install "$pkg"
    fi
  done
}

install_brew_casks() {
  local packages=("$@")
  [[ ${#packages[@]} -eq 0 ]] && return
  info "Installing Homebrew casks: ${packages[*]}"
  for pkg in "${packages[@]}"; do
    if brew list --cask "$pkg" >/dev/null 2>&1; then
      info "brew cask '$pkg' already installed."
    else
      brew install --cask "$pkg"
    fi
  done
}

install_appstore_apps() {
  local packages=("$@")
  [[ ${#packages[@]} -eq 0 ]] && return

  # Check if mas is installed
  if ! command -v mas >/dev/null 2>&1; then
    warn "mas CLI not installed; skipping App Store apps. Install with: brew install mas"
    return
  fi

  # Check if user is signed into the App Store
  if ! mas account >/dev/null 2>&1; then
    warn "Not signed into Mac App Store; skipping App Store apps. Please sign in via App Store app."
    return
  fi

  info "Installing Mac App Store apps: ${packages[*]}"
  for app_id in "${packages[@]}"; do
    # Check if app is already installed
    if mas list | grep -q "^${app_id}[[:space:]]"; then
      info "App Store app ID '$app_id' already installed."
    else
      mas install "$app_id"
    fi
  done
}

filter_missing_packages() {
  local mgr=$1; shift
  local packages=("$@")
  local result=()

  case "$mgr" in
    apt)
      for pkg in "${packages[@]}"; do
        if dpkg -s "$pkg" >/dev/null 2>&1; then
          info "apt package '$pkg' already installed; skipping." >&2
        else
          result+=("$pkg")
        fi
      done
      ;;
    dnf)
      for pkg in "${packages[@]}"; do
        if rpm -q "$pkg" >/dev/null 2>&1; then
          info "dnf package '$pkg' already installed; skipping." >&2
        else
          result+=("$pkg")
        fi
      done
      ;;
    pacman)
      for pkg in "${packages[@]}"; do
        if pacman -Qi "$pkg" >/dev/null 2>&1; then
          info "pacman package '$pkg' already installed; skipping." >&2
        else
          result+=("$pkg")
        fi
      done
      ;;
    paru)
      if ! command -v paru >/dev/null 2>&1; then
        warn "paru not found; cannot install AUR packages (${packages[*]})." >&2
        echo ""
        return
      fi
      for pkg in "${packages[@]}"; do
        if paru -Qi "$pkg" >/dev/null 2>&1; then
          info "paru package '$pkg' already installed; skipping." >&2
        else
          result+=("$pkg")
        fi
      done
      ;;
    brew_formulae)
      if ! command -v brew >/dev/null 2>&1; then
        printf '%s\n' "${packages[@]}"
        return
      fi
      ensure_homebrew_in_path
      for pkg in "${packages[@]}"; do
        if brew list --formula "$pkg" >/dev/null 2>&1; then
          info "brew formula '$pkg' already installed; skipping." >&2
        else
          result+=("$pkg")
        fi
      done
      ;;
    brew_casks)
      if ! command -v brew >/dev/null 2>&1; then
        printf '%s\n' "${packages[@]}"
        return
      fi
      ensure_homebrew_in_path
      for pkg in "${packages[@]}"; do
        # Check if installed via brew cask
        if brew list --cask "$pkg" >/dev/null 2>&1; then
          info "brew cask '$pkg' already installed; skipping." >&2
        else
          # Check if app exists in /Applications (for apps installed outside brew)
          local app_exists=false
          case "$pkg" in
            iterm2)
              [[ -d "/Applications/iTerm.app" ]] && app_exists=true
              ;;
            bettertouchtool)
              [[ -d "/Applications/BetterTouchTool.app" ]] && app_exists=true
              ;;
            # Add more cask-to-app mappings as needed
          esac

          if [[ $app_exists == true ]]; then
            info "App for cask '$pkg' already exists in /Applications; skipping." >&2
          else
            result+=("$pkg")
          fi
        fi
      done
      ;;
    appstore)
      if ! command -v mas >/dev/null 2>&1; then
        printf '%s\n' "${packages[@]}"
        return
      fi
      for app_id in "${packages[@]}"; do
        if mas list | grep -q "^${app_id}[[:space:]]"; then
          info "App Store app ID '$app_id' already installed; skipping." >&2
        else
          result+=("$app_id")
        fi
      done
      ;;
  esac

  # Only iterate if result array has elements
  if [[ ${#result[@]} -gt 0 ]]; then
    for pkg in "${result[@]}"; do
      printf '%s\n' "$pkg"
    done
  fi
}

install_apt_packages() {
  local packages=("$@")
  [[ ${#packages[@]} -eq 0 ]] && return
  info "Installing apt packages: ${packages[*]}"
  sudo apt-get update -y
  sudo apt-get install -y "${packages[@]}"
}

install_dnf_packages() {
  local packages=("$@")
  [[ ${#packages[@]} -eq 0 ]] && return
  info "Installing dnf packages: ${packages[*]}"
  sudo dnf install -y "${packages[@]}"
}

install_pacman_packages() {
  local packages=("$@")
  [[ ${#packages[@]} -eq 0 ]] && return
  info "Installing pacman packages: ${packages[*]}"
  sudo pacman -Sy --noconfirm "${packages[@]}"
}

install_paru_packages() {
  local packages=("$@")
  [[ ${#packages[@]} -eq 0 ]] && return
  [[ ${#packages[@]} -eq 0 ]] && return
  info "Installing paru packages: ${packages[*]}"
  paru -S --noconfirm "${packages[@]}"
}

detect_installed_packages() {
  local os=$1
  local mgr=${2:-}
  case "$os" in
    macos)
      ensure_homebrew_in_path
      [[ -z $(command -v brew) ]] && return
      for pkg in "${macos_brew_formulae[@]}"; do
        if brew list --formula "$pkg" >/dev/null 2>&1; then
          printf '%s (formula)\n' "$pkg"
        fi
      done
      for pkg in "${macos_brew_casks[@]}"; do
        if brew list --cask "$pkg" >/dev/null 2>&1; then
          printf '%s (cask)\n' "$pkg"
        else
          # Check if app exists outside of brew
          case "$pkg" in
            iterm2)
              [[ -d "/Applications/iTerm.app" ]] && printf 'iTerm.app (external)\n'
              ;;
            bettertouchtool)
              [[ -d "/Applications/BetterTouchTool.app" ]] && printf 'BetterTouchTool.app (external)\n'
              ;;
          esac
        fi
      done
      if command -v mas >/dev/null 2>&1; then
        for app_id in "${macos_appstore_apps[@]}"; do
          if mas list | grep -q "^${app_id}[[:space:]]"; then
            local app_name
            app_name=$(mas list | grep "^${app_id}[[:space:]]" | cut -f2-)
            printf '%s (App Store: %s)\n' "$app_id" "$app_name"
          fi
        done
      fi
      ;;
    linux)
      case "$mgr" in
        apt)
          for pkg in "${linux_apt_packages[@]}"; do
            if dpkg -s "$pkg" >/dev/null 2>&1; then
              printf '%s\n' "$pkg"
            fi
          done
          ;;
        dnf)
          for pkg in "${linux_dnf_packages[@]}"; do
            if rpm -q "$pkg" >/dev/null 2>&1; then
              printf '%s\n' "$pkg"
            fi
          done
          ;;
        pacman)
          for pkg in "${linux_pacman_packages[@]}"; do
            if pacman -Qi "$pkg" >/dev/null 2>&1; then
              printf '%s\n' "$pkg"
            fi
          done
          if command -v paru >/dev/null 2>&1; then
            for pkg in "${linux_paru_packages[@]}"; do
              if paru -Qi "$pkg" >/dev/null 2>&1; then
                printf '%s (paru)\n' "$pkg"
              fi
            done
          else
            for pkg in "${linux_paru_packages[@]}"; do
              if pacman -Qi "$pkg" >/dev/null 2>&1; then
                printf '%s\n' "$pkg"
              fi
            done
          fi
          ;;
        *)
          ;;
      esac
      ;;
  esac
}

packages_already_configured() {
  local flag_file="$INSTALL_ROOT/.packages-installed"
  [[ -f $flag_file ]]
}

mark_packages_installed() {
  local flag_file="$INSTALL_ROOT/.packages-installed"
  printf 'installed %s\n' "$(date -u +%FT%TZ)" >"$flag_file"
}

handle_package_bootstrap() {
  local os=$1
  if [[ $os == unknown ]]; then
    warn "Could not determine operating system automatically; package installation skipped."
    return
  fi

  if (( ! INTERACTIVE )); then
    info "Non-interactive mode; skipping package installation."
    return
  fi

  pending_macos_brew_formulae=()
  pending_macos_brew_casks=()
  pending_macos_appstore_apps=()
  pending_linux_apt_packages=()
  pending_linux_dnf_packages=()
  pending_linux_pacman_packages=()
  pending_linux_paru_packages=()
  pending_linux_paru_blocked=()

  local mgr=""
  local mgr_label=""
  if [[ $os == linux ]]; then
    mgr=$(detect_linux_package_manager)
    case "$mgr" in
      apt) mgr_label="apt" ;;
      dnf) mgr_label="dnf" ;;
      pacman)
        if command -v paru >/dev/null 2>&1; then
          mgr_label="pacman + paru"
        else
          mgr_label="pacman"
        fi
        ;;
      *) mgr_label="unknown" ;;
    esac
  else
    mgr_label="Homebrew"
  fi

  case "$os" in
    macos)
      if command -v brew >/dev/null 2>&1; then
        ensure_homebrew_in_path
        IFS=$'\n' read -r -d '' -a pending_macos_brew_formulae < <(filter_missing_packages brew_formulae "${macos_brew_formulae[@]}" && printf '\0')
        IFS=$'\n' read -r -d '' -a pending_macos_brew_casks < <(filter_missing_packages brew_casks "${macos_brew_casks[@]}" && printf '\0')
        if command -v mas >/dev/null 2>&1; then
          IFS=$'\n' read -r -d '' -a pending_macos_appstore_apps < <(filter_missing_packages appstore "${macos_appstore_apps[@]}" && printf '\0')
        else
          pending_macos_appstore_apps=("${macos_appstore_apps[@]}")
        fi
      else
        pending_macos_brew_formulae=("${macos_brew_formulae[@]}")
        pending_macos_brew_casks=("${macos_brew_casks[@]}")
        pending_macos_appstore_apps=("${macos_appstore_apps[@]}")
        warn "Homebrew not detected; formulae and casks will require manual setup."
      fi
      ;;
    linux)
      case "$mgr" in
        apt)
          IFS=$'\n' read -r -d '' -a pending_linux_apt_packages < <(filter_missing_packages apt "${linux_apt_packages[@]}" && printf '\0')
          ;;
        dnf)
          IFS=$'\n' read -r -d '' -a pending_linux_dnf_packages < <(filter_missing_packages dnf "${linux_dnf_packages[@]}" && printf '\0')
          ;;
        pacman)
          IFS=$'\n' read -r -d '' -a pending_linux_pacman_packages < <(filter_missing_packages pacman "${linux_pacman_packages[@]}" && printf '\0')
          if command -v paru >/dev/null 2>&1; then
            IFS=$'\n' read -r -d '' -a pending_linux_paru_packages < <(filter_missing_packages paru "${linux_paru_packages[@]}" && printf '\0')
          else
            pending_linux_paru_blocked=("${linux_paru_packages[@]}")
          fi
          ;;
        *)
          ;;
      esac
      ;;
  esac

  local pending_total=$(( ${#pending_macos_brew_formulae[@]} + ${#pending_macos_brew_casks[@]} + ${#pending_macos_appstore_apps[@]} + ${#pending_linux_apt_packages[@]} + ${#pending_linux_dnf_packages[@]} + ${#pending_linux_pacman_packages[@]} + ${#pending_linux_paru_packages[@]} ))

  local summary_parts=()
  [[ ${#pending_macos_brew_formulae[@]} -gt 0 ]] && summary_parts+=("brew:${pending_macos_brew_formulae[*]}")
  [[ ${#pending_macos_brew_casks[@]} -gt 0 ]] && summary_parts+=("casks:${pending_macos_brew_casks[*]}")
  [[ ${#pending_macos_appstore_apps[@]} -gt 0 ]] && summary_parts+=("appstore:${pending_macos_appstore_apps[*]}")
  [[ ${#pending_linux_apt_packages[@]} -gt 0 ]] && summary_parts+=("apt:${pending_linux_apt_packages[*]}")
  [[ ${#pending_linux_dnf_packages[@]} -gt 0 ]] && summary_parts+=("dnf:${pending_linux_dnf_packages[*]}")
  [[ ${#pending_linux_pacman_packages[@]} -gt 0 ]] && summary_parts+=("pacman:${pending_linux_pacman_packages[*]}")
  [[ ${#pending_linux_paru_packages[@]} -gt 0 ]] && summary_parts+=("paru:${pending_linux_paru_packages[*]}")
  local pending_summary="<none>"
  if [[ ${#summary_parts[@]} -gt 0 ]]; then
    pending_summary=$(IFS=', '; echo "${summary_parts[*]}")
  fi

  local os_display
  case "$os" in
    macos) os_display="macOS" ;;
    linux) os_display="Linux" ;;
    *) os_display="Unknown" ;;
  esac
  printf '\n%b%s%b %bPackage Setup%b for %s (%s)%b\n' \
    "$VW_PINK" "$VW_SECTION_ICON" "$VW_RESET" "$VW_CYAN" "$VW_RESET" "$os_display" "$mgr_label" "$VW_RESET" >&"$PROMPT_FD"

  case "$os" in
    macos)
      print_pkg_group 'brew formulae' macos_brew_formulae "$VW_ORANGE" >&"$PROMPT_FD"
      print_pkg_group 'brew casks' macos_brew_casks "$VW_PURPLE" >&"$PROMPT_FD"
      print_pkg_group 'App Store apps' macos_appstore_apps "$VW_CYAN" >&"$PROMPT_FD"
      ;;
    linux)
      case "$mgr" in
        apt)
          print_pkg_group 'apt packages' linux_apt_packages "$VW_ORANGE" >&"$PROMPT_FD"
          ;;
        dnf)
          print_pkg_group 'dnf packages' linux_dnf_packages "$VW_ORANGE" >&"$PROMPT_FD"
          ;;
        pacman)
          print_pkg_group 'pacman packages' linux_pacman_packages "$VW_ORANGE" >&"$PROMPT_FD"
          print_pkg_group 'paru packages' linux_paru_packages "$VW_MAGENTA" >&"$PROMPT_FD"
          ;;
        *)
          printf '    %b%s%b %b<package manager not detected>%b\n' \
            "$VW_PINK" "$VW_ITEM_ICON" "$VW_RESET" "$VW_GRAY" "$VW_RESET" >&"$PROMPT_FD"
          ;;
      esac
      ;;
  esac

  printf '\n%b%s%b %bAlready installed%b\n' "$VW_PINK" "$VW_SECTION_ICON" "$VW_RESET" "$VW_CYAN" "$VW_RESET" >&"$PROMPT_FD"
  local detected
  detected=$(detect_installed_packages "$os" "$mgr") || detected=""
  print_installed_items "$detected" >&"$PROMPT_FD"

  printf '\n%b%s%b %bPending installs%b\n' "$VW_PINK" "$VW_SECTION_ICON" "$VW_RESET" "$VW_CYAN" "$VW_RESET" >&"$PROMPT_FD"
  local pending_shown=0
  if [[ $os == macos ]]; then
    if [[ ${#pending_macos_brew_formulae[@]} -gt 0 ]]; then
      print_pkg_list 'brew formulae' "$VW_ORANGE" "${pending_macos_brew_formulae[@]}" >&"$PROMPT_FD"
      pending_shown=1
    fi
    if [[ ${#pending_macos_brew_casks[@]} -gt 0 ]]; then
      print_pkg_list 'brew casks' "$VW_PURPLE" "${pending_macos_brew_casks[@]}" >&"$PROMPT_FD"
      pending_shown=1
    fi
    if [[ ${#pending_macos_appstore_apps[@]} -gt 0 ]]; then
      print_pkg_list 'App Store apps' "$VW_CYAN" "${pending_macos_appstore_apps[@]}" >&"$PROMPT_FD"
      pending_shown=1
    fi
  else
    case "$mgr" in
      apt)
        if [[ ${#pending_linux_apt_packages[@]} -gt 0 ]]; then
          print_pkg_list 'apt packages' "$VW_ORANGE" "${pending_linux_apt_packages[@]}" >&"$PROMPT_FD"
          pending_shown=1
        fi
        ;;
      dnf)
        if [[ ${#pending_linux_dnf_packages[@]} -gt 0 ]]; then
          print_pkg_list 'dnf packages' "$VW_ORANGE" "${pending_linux_dnf_packages[@]}" >&"$PROMPT_FD"
          pending_shown=1
        fi
        ;;
      pacman)
        if [[ ${#pending_linux_pacman_packages[@]} -gt 0 ]]; then
          print_pkg_list 'pacman packages' "$VW_ORANGE" "${pending_linux_pacman_packages[@]}" >&"$PROMPT_FD"
          pending_shown=1
        fi
        if [[ ${#pending_linux_paru_packages[@]} -gt 0 ]]; then
          print_pkg_list 'paru packages' "$VW_MAGENTA" "${pending_linux_paru_packages[@]}" >&"$PROMPT_FD"
          pending_shown=1
        fi
        ;;
    esac
  fi

  if (( ${#pending_linux_paru_blocked[@]} > 0 )); then
    local display_paru=()
    for pkg in "${pending_linux_paru_blocked[@]}"; do
      [[ -z $pkg ]] && continue
      display_paru+=("${pkg} (requires paru)")
    done
    print_pkg_list 'paru packages' "$VW_GRAY" "${display_paru[@]}" >&"$PROMPT_FD"
    pending_shown=1
  fi

  if (( pending_shown == 0 )); then
    print_none_line >&"$PROMPT_FD"
  fi

  if (( pending_total == 0 )) && (( ${#pending_linux_paru_blocked[@]} == 0 )); then
    info "All configured packages already installed; skipping package installation."
    return
  fi

  if (( pending_total == 0 )) && (( ${#pending_linux_paru_blocked[@]} > 0 )); then
    warn "Install paru to manage: ${pending_linux_paru_blocked[*]}"
    return
  fi

  local default_answer=N
  if packages_already_configured; then
    default_answer=Y
    printf '\nPrevious bootstrap detected at %s/.packages-installed\n' "${INSTALL_ROOT/#$HOME/~}" >&"$PROMPT_FD"
  fi

  local os_label
  case "$os" in
    macos) os_label="macOS" ;;
    linux) os_label="Linux" ;;
    *) os_label="Unknown" ;;
  esac
  local prompt_text="Install/Update ${os_label} packages? (pending: ${pending_summary})"
  if prompt_yes_no "$prompt_text" "$default_answer"; then
    run_ansible_bootstrap "$os" "$mgr"
    mark_packages_installed
  else
    info "Skipped package installation."
  fi
}
