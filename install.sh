#!/usr/bin/env bash
set -euo pipefail

# Interactive installer for the myprompts collection.
# Downloads vaporwave prompt themes and configures the detected shell.

BASE_URL=${BASE_URL:-"https://raw.githubusercontent.com/stlalpha/myprompts/main"}
INSTALL_ROOT=${INSTALL_ROOT:-"$HOME/.local/share/myprompts"}
PROMPT_STATIC=vaporwave_bash_prompt
PROMPT_LIQUID=vaporwave_liquid_prompt
PROMPT_ZSH=vaporwave_zsh_prompt
LS_COLORS_FILE=vaporwave_lscolors

CONFIG_TMP_DIR=$(mktemp -d 2>/dev/null || mktemp -d -t myprompts)
PACKAGES_CONFIG_URL="$BASE_URL/config/packages.sh"
ALIASES_CONFIG_URL="$BASE_URL/config/aliases.sh"

VW_RESET=$'\033[0m'
VW_PINK=$'\033[38;5;198m'
VW_CYAN=$'\033[38;5;51m'
VW_PURPLE=$'\033[38;5;141m'
VW_BLUE=$'\033[38;5;39m'
VW_ORANGE=$'\033[38;5;209m'
VW_GREEN=$'\033[38;5;85m'
VW_MAGENTA=$'\033[38;5;201m'
VW_GRAY=$'\033[38;5;244m'
VW_SECTION_ICON='✦'
VW_ITEM_ICON='▹'
VW_INSTALLED_ICON='✧'
VW_TOP_BORDER='.0Oo............................................................oO0>'
VW_BOTTOM_BORDER='<0Oo............................................................oO0.'

pending_macos_brew_formulae=()
pending_macos_brew_casks=()
pending_linux_apt_packages=()
pending_linux_dnf_packages=()
pending_linux_pacman_packages=()
pending_linux_paru_packages=()
pending_linux_paru_blocked=()

INTERACTIVE=0
PROMPT_FD=0
TTY_FD_OPENED=0

if [[ -n ${MYPROMPTS_NONINTERACTIVE:-} ]]; then
  PROMPT_FD=0
  INTERACTIVE=0
else
  if [[ -r /dev/tty && -w /dev/tty ]]; then
    if exec 3<>/dev/tty; then
      PROMPT_FD=3
      INTERACTIVE=1
      TTY_FD_OPENED=1
    else
      echo "Unable to open /dev/tty for interactive prompts." >&2
      exit 1
    fi
  elif [[ -t 0 ]]; then
    PROMPT_FD=0
    INTERACTIVE=1
  else
    echo "No interactive terminal detected; run the installer from an interactive shell." >&2
    exit 1
  fi
fi

cleanup() {
  if [[ $TTY_FD_OPENED -eq 1 ]]; then
    exec 3>&-
  fi
  if [[ -d $CONFIG_TMP_DIR ]]; then
    rm -rf "$CONFIG_TMP_DIR"
  fi
}

trap cleanup EXIT

info()  { printf '\e[1;36m[info]\e[0m %s\n' "$*"; }
warn()  { printf '\e[1;33m[warn]\e[0m %s\n' "$*"; }
error() { printf '\e[1;31m[fail]\e[0m %s\n' "$*" >&2; }

print_header() {
  printf '%b%s%b\n' "$VW_PINK" "$VW_TOP_BORDER" "$VW_RESET"
  printf "  %bSpaceman's Auto-Personalizer%b %bv0.1b%b\n" "$VW_CYAN" "$VW_RESET" "$VW_PURPLE" "$VW_RESET"
  printf "  %bBootstrapping vaporwave shell and LS aesthetic...%b\n" "$VW_BLUE" "$VW_RESET"
  printf '%b%s%b\n' "$VW_PINK" "$VW_BOTTOM_BORDER" "$VW_RESET"
}

print_pkg_group() {
  local label=$1
  local array_name=$2
  local color=$3
  local packages=()
  eval "packages=(\"\${${array_name}[@]}\")"

  if [[ ${#packages[@]} -gt 0 ]]; then
    printf '    %b%s%b %b%s:%b %b%s%b\n' \
      "$VW_PINK" "$VW_ITEM_ICON" "$VW_RESET" "$color" "$label" "$VW_RESET" "$color" "${packages[*]}" "$VW_RESET"
  else
    printf '    %b%s%b %b%s:%b %b<none>%b\n' \
      "$VW_PINK" "$VW_ITEM_ICON" "$VW_RESET" "$color" "$label" "$VW_RESET" "$VW_GRAY" "$VW_RESET"
  fi
}

print_pkg_list() {
  local label=$1
  local color=$2
  shift 2
  local packages=("$@")
  if [[ ${#packages[@]} -gt 0 ]]; then
    printf '    %b%s%b %b%s:%b %b%s%b\n' \
      "$VW_PINK" "$VW_ITEM_ICON" "$VW_RESET" "$color" "$label" "$VW_RESET" "$color" "${packages[*]}" "$VW_RESET"
  fi
}

print_none_line() {
  printf '    %b%s%b %b<none>%b\n' "$VW_PINK" "$VW_ITEM_ICON" "$VW_RESET" "$VW_GRAY" "$VW_RESET"
}

print_installed_items() {
  local detected=$1
  if [[ -n $detected ]]; then
    while IFS= read -r line; do
      [[ -z $line ]] && continue
      printf '    %b%s%b %b%s%b\n' "$VW_PINK" "$VW_INSTALLED_ICON" "$VW_RESET" "$VW_GREEN" "$line" "$VW_RESET"
    done <<< "$detected"
  else
    printf '    %b%s%b %b<none detected>%b\n' "$VW_PINK" "$VW_INSTALLED_ICON" "$VW_RESET" "$VW_GRAY" "$VW_RESET"
  fi
}

ensure_array() {
  local name=$1
  if ! declare -p "$name" >/dev/null 2>&1; then
    eval "$name=()"
  fi
}

load_configuration() {
  local packages_file="$CONFIG_TMP_DIR/packages.sh"
  local aliases_file="$CONFIG_TMP_DIR/aliases.sh"

  if ! curl -fsSL "$PACKAGES_CONFIG_URL" -o "$packages_file"; then
    warn "Unable to download packages configuration; skipping package bootstrap."
  else
    # shellcheck source=/dev/null
    source "$packages_file"
  fi

  if ! curl -fsSL "$ALIASES_CONFIG_URL" -o "$aliases_file"; then
    warn "Unable to download aliases configuration; skipping alias updates."
  else
    # shellcheck source=/dev/null
    source "$aliases_file"
  fi

  ensure_array macos_brew_formulae
  ensure_array macos_brew_casks
  ensure_array linux_apt_packages
  ensure_array linux_dnf_packages
  ensure_array linux_pacman_packages
  ensure_array linux_paru_packages
  ensure_array zsh_aliases
  ensure_array bash_aliases
}

detect_os() {
  case "$(uname -s)" in
    Darwin) echo macos ;;
    Linux) echo linux ;;
    *) echo unknown ;;
  esac
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

detect_linux_package_manager() {
  if command -v apt-get >/dev/null 2>&1; then
    echo apt
  elif command -v dnf >/dev/null 2>&1; then
    echo dnf
  elif command -v pacman >/dev/null 2>&1; then
    echo pacman
  else
    echo unknown
  fi
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
        if brew list --cask "$pkg" >/dev/null 2>&1; then
          info "brew cask '$pkg' already installed; skipping." >&2
        else
          result+=("$pkg")
        fi
      done
      ;;
  esac

  for pkg in "${result[@]}"; do
    printf '%s\n' "$pkg"
  done
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
  # Always force fresh download of playbook (no caching)
  if ! curl -fsSL -H 'Cache-Control: no-cache' "$BASE_URL/ansible/playbook.yml" -o "$dest/playbook.yml"; then
    warn "Unable to download Ansible playbook; skipping package bootstrap."
    return 1
  fi
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

  local vars_file="$CONFIG_TMP_DIR/ansible_vars.yml"
  generate_ansible_vars "$vars_file" "$os" "$mgr"

  local playbook="$INSTALL_ROOT/ansible/playbook.yml"
  if [[ ! -f $playbook ]]; then
    warn "Ansible playbook missing at $playbook; skipping package bootstrap."
    return
  fi

  local become_args=(-b)
  if ! sudo -n true 2>/dev/null; then
    become_args+=(-K)
  fi

  ANSIBLE_NOCOWS=1 ANSIBLE_FORCE_COLOR=1 ansible-playbook -i localhost, -c local -e "@$vars_file" "$playbook" "${become_args[@]}"
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
        fi
      done
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
      else
        pending_macos_brew_formulae=("${macos_brew_formulae[@]}")
        pending_macos_brew_casks=("${macos_brew_casks[@]}")
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

  local pending_total=$(( ${#pending_macos_brew_formulae[@]} + ${#pending_macos_brew_casks[@]} + ${#pending_linux_apt_packages[@]} + ${#pending_linux_dnf_packages[@]} + ${#pending_linux_pacman_packages[@]} + ${#pending_linux_paru_packages[@]} ))

  local summary_parts=()
  [[ ${#pending_macos_brew_formulae[@]} -gt 0 ]] && summary_parts+=("brew:${pending_macos_brew_formulae[*]}")
  [[ ${#pending_macos_brew_casks[@]} -gt 0 ]] && summary_parts+=("casks:${pending_macos_brew_casks[*]}")
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

apply_aliases_for_shell() {
  local rc_file=$1
  local alias_array_name=$2

  if ! declare -p "$alias_array_name" >/dev/null 2>&1; then
    return
  fi

  local aliases
  eval "aliases=(\"\${${alias_array_name}[@]}\")"

  [[ ${#aliases[@]} -eq 0 ]] && return

  local content
  content=$(printf '%s\n' "${aliases[@]}")
  append_block "$rc_file" "# >>> myprompts aliases >>>" "$content"
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    error "Missing required command '$1'. Please install it and rerun." 
    exit 1
  fi
}

existing_install_present() {
  [[ -d $INSTALL_ROOT ]] && [[ -n $(ls -A "$INSTALL_ROOT" 2>/dev/null) ]]
}

describe_install_state() {
  local target=$1
  if [[ ! -d $target ]]; then
    printf 'fresh install'
    return
  fi

  if [[ -f $target/.install-meta ]]; then
    local meta
    meta=$(<"$target/.install-meta")
    printf 'update of existing install (%s)' "$meta"
  else
    printf 'existing directory detected'
  fi
}

handle_existing_install() {
  if ! existing_install_present; then
    return
  fi

  local summary
  summary=$(describe_install_state "$INSTALL_ROOT")

  if (( ! INTERACTIVE )); then
    # Capitalize first letter of summary
    local first_char first_upper rest
    first_char=${summary:0:1}
    rest=${summary:1}
    first_upper=$(echo "$first_char" | tr '[:lower:]' '[:upper:]')
    error "${first_upper}${rest}; run interactively to confirm reinstall."
    exit 1
  fi

  printf '\nDetected %s at %s.\n' "$summary" "${INSTALL_ROOT/#$HOME/~}" >&"$PROMPT_FD"
  printf 'Reinstall will remove and replace this directory.\n' >&"$PROMPT_FD"

if prompt_yes_no "Proceed with reinstall?" N; then
    info "Removing previous installation."
    rm -rf "$INSTALL_ROOT"
  else
    info "Installation cancelled; existing setup left untouched."
    exit 0
  fi
}

prompt_yes_no() {
  local message=$1
  local default=${2:-Y}
  local default_lower
  default_lower=$(echo "$default" | tr '[:upper:]' '[:lower:]')

  if (( ! INTERACTIVE )); then
    [[ $default_lower == y* ]]
    return
  fi

  local reply prompt
  if [[ $default_lower == y* ]]; then
    prompt="${message} [Y/n] "
  else
    prompt="${message} [y/N] "
  fi

  while true; do
    if ! read -r -u "$PROMPT_FD" -p "$prompt" reply; then
      error "Failed to read response; aborting installation."
      exit 1
    fi
    reply=${reply:-$default}
    reply=$(echo "$reply" | tr '[:upper:]' '[:lower:]')
    case "$reply" in
      y|yes) return 0 ;;
      n|no)  return 1 ;;
      *)     echo "Please answer yes or no." ;;
    esac
  done
}

choose_prompt_variant() {
  local __out_var=$1
  local preset=""
  local selection=""

  if (( ! INTERACTIVE )); then
    preset=${PROMPT_VARIANT:-}
    preset=$(echo "$preset" | tr '[:upper:]' '[:lower:]')
    case "$preset" in
      liquid|animated)
        selection="$PROMPT_LIQUID"
        ;;
      classic|static|vaporwave|"")
        selection="$PROMPT_STATIC"
        ;;
      *) error "Unknown PROMPT_VARIANT '$preset'; expected 'classic' or 'liquid'."; exit 1 ;;
    esac
    printf -v "$__out_var" '%s' "$selection"
    return
  fi

  local reset=$'\033[0m'
  local bold=$'\033[1m'
  local pink=$'\033[38;5;198m'
  local cyan=$'\033[38;5;51m'
  local purple=$'\033[38;5;141m'
  local dark_purple=$'\033[38;5;93m'
  local blue=$'\033[38;5;39m'
  local orange=$'\033[38;5;209m'
  local green=$'\033[38;5;85m'
  local magenta=$'\033[38;5;201m'
  local wave=$'\033[38;5;123m'
  local bg_dark=$'\033[48;5;234m'

  printf '\nPrompt variant options:\n' >&"$PROMPT_FD"
  printf '  [1] Classic – static vaporwave prompt\n' >&"$PROMPT_FD"
  printf '      %s%s◤%suser%s@%shost%s◢%s %s【%s~/project%s】%s %s『main』%s %s%s▸%s\n' \
    "$bg_dark" "$pink" "$cyan" "$dark_purple" "$purple" "$pink" "$reset" "$orange" "$green" "$orange" "$reset" "$magenta" "$reset" "$blue" "$bold" "$reset" >&"$PROMPT_FD"
  printf '  [2] Liquid – animated waveform prompt\n' >&"$PROMPT_FD"
  printf '      %s%s◤%suser%s@%shost%s◢%s %s≈≋≈%s %s~/project%s %s≈≋≈%s %s『main』%s %s%s∼▸%s%s\n' \
    "$bg_dark" "$pink" "$cyan" "$dark_purple" "$purple" "$pink" "$reset" "$wave" "$reset" "$green" "$reset" "$wave" "$reset" "$magenta" "$reset" "$wave" "$bold" "$reset" "$reset" >&"$PROMPT_FD"

  local choice
  while true; do
    if ! printf 'Select prompt variant [1-2] (default: 1): ' >&"$PROMPT_FD"; then
      error "Failed to display prompt variant question."
      exit 1
    fi
    if ! IFS= read -r -u "$PROMPT_FD" choice; then
      error "Failed to read response; aborting installation."
      exit 1
    fi
    choice=${choice:-1}
    case "$choice" in
      1) selection="$PROMPT_STATIC"; break ;;
      2) selection="$PROMPT_LIQUID"; break ;;
      *) printf 'Please enter 1 or 2.\n' >&"$PROMPT_FD" ;;
    esac
  done

  printf -v "$__out_var" '%s' "$selection"
}

choose_prompt_style() {
  local __out_var=$1
  local preset=""
  local selection=""
  if (( ! INTERACTIVE )); then
    preset=${PROMPT_STYLE:-}
    preset=$(echo "$preset" | tr '[:upper:]' '[:lower:]')
    case "$preset" in
      extended|multi-line)
        selection="extended"
        ;;
      compact|single-line|default|"")
        selection="compact"
        ;;
      *) error "Unknown PROMPT_STYLE '$preset'; expected 'compact' or 'extended'."; exit 1 ;;
    esac
    printf -v "$__out_var" '%s' "$selection"
    return
  fi

  local current=${MYPROMPTS_PROMPT_STYLE:-compact}
  current=$(echo "$current" | tr '[:upper:]' '[:lower:]')
  local default_choice_num=1
  local default_choice_label="Compact"
  if [[ $current == extended ]]; then
    default_choice_num=2
    default_choice_label="Extended"
  fi

  local reset=$'\033[0m'
  local bold=$'\033[1m'
  local pink=$'\033[38;5;198m'
  local cyan=$'\033[38;5;51m'
  local purple=$'\033[38;5;141m'
  local dark_purple=$'\033[38;5;93m'
  local blue=$'\033[38;5;39m'
  local orange=$'\033[38;5;209m'
  local green=$'\033[38;5;85m'
  local magenta=$'\033[38;5;201m'
  local bg_dark=$'\033[48;5;234m'

  printf '\nPrompt layout options (current: %s):\n' "$default_choice_label" >&"$PROMPT_FD"
  printf '  [1] Compact – single-line prompt\n' >&"$PROMPT_FD"
  printf '      %s%s◤%suser%s@%shost%s◢%s %s【%s~/project%s】%s %s『main』%s %s%s▸%s\n' \
    "$bg_dark" "$pink" "$cyan" "$dark_purple" "$purple" "$pink" "$reset" "$orange" "$green" "$orange" "$reset" "$magenta" "$reset" "$blue" "$bold" "$reset" >&"$PROMPT_FD"
  printf '  [2] Extended – multi-line prompt with decorative header\n' >&"$PROMPT_FD"
  printf '      %s◤%suser%s◢%s %s◆%s %s◤%shost%s◢%s %s➤ %s~/project%s %s『main』%s\n' \
    "$pink" "$cyan" "$pink" "$reset" "$cyan" "$reset" "$pink" "$purple" "$pink" "$reset" "$green" "$blue" "$reset" "$magenta" "$reset" >&"$PROMPT_FD"
  printf '      %s╰─%s%s▸%s\n' "$orange" "$blue" "$bold" "$reset" >&"$PROMPT_FD"

  local choice
  while true; do
    if ! printf 'Select prompt layout [1-2] (default: %s [%d]): ' "$default_choice_label" "$default_choice_num" >&"$PROMPT_FD"; then
      error "Failed to display prompt layout question."
      exit 1
    fi
    if ! IFS= read -r -u "$PROMPT_FD" choice; then
      error "Failed to read response; aborting installation."
      exit 1
    fi
    choice=${choice:-$default_choice_num}
    case "$choice" in
      1) selection="compact"; break ;;
      2) selection="extended"; break ;;
      *) printf 'Please enter 1 or 2.\n' >&"$PROMPT_FD" ;;
    esac
  done

  printf -v "$__out_var" '%s' "$selection"
}

append_block() {
  local file=$1
  local marker=$2
  local line=$3
  local end_marker=${marker/>>>/<<<}

  touch "$file"
  if grep -F "$marker" "$file" >/dev/null 2>&1; then
    info "Updating existing block in ${file/#$HOME/~}."
    local tmp
    tmp=$(mktemp)
    awk -v start="$marker" -v end="$end_marker" -v line="$line" '
      BEGIN {in_block=0}
      $0 == start {print start; print line; in_block=1; next}
      $0 == end {in_block=0; print end; next}
      !in_block {print}
    ' "$file" >"$tmp"
    mv "$tmp" "$file"
  else
    {
      printf '\n%s\n' "$marker"
      printf '%s\n' "$line"
      printf '%s\n' "$end_marker"
    } >>"$file"
    info "Added block to ${file/#$HOME/~}."
  fi
}

download_asset() {
  local name=$1
  local target="$INSTALL_ROOT/$name"
  info "Fetching $name"
  curl -fsSL "$BASE_URL/$name" -o "$target"
  chmod 644 "$target"
}

ensure_ls_alias() {
  local file=$1
  local marker="# >>> myprompts ls alias >>>"
  local alias_line="alias ls='ls --color=auto'"

  if [[ -f $file ]] && grep -qE '^[[:space:]]*alias[[:space:]]+ls=' "$file"; then
    info "Existing ls alias detected in ${file/#$HOME/~}; skipping alias install."
    return
  fi

  append_block "$file" "$marker" "$alias_line"
}

write_prompt_style() {
  local file=$1
  local style=$2
  local marker="# >>> myprompts prompt style >>>"
  local line="export MYPROMPTS_PROMPT_STYLE=$style"
  append_block "$file" "$marker" "$line"
}

main() {
  require_command curl

  print_header

  handle_existing_install

  load_configuration

  local os_type
  os_type=$(detect_os)
  local os_type_display
  case "$os_type" in
    macos) os_type_display="macOS" ;;
    linux) os_type_display="Linux" ;;
    *) os_type_display="Unknown" ;;
  esac
  info "Operating system detected: $os_type_display"
  handle_package_bootstrap "$os_type"

  info "Installing myprompts assets to ${INSTALL_ROOT/#$HOME/~}"
  mkdir -p "$INSTALL_ROOT"

  download_asset "$PROMPT_STATIC"
  download_asset "$PROMPT_LIQUID"
  download_asset "$PROMPT_ZSH"
  download_asset "$LS_COLORS_FILE"

  printf 'installed %s\n' "$(date -u +%FT%TZ)" >"$INSTALL_ROOT/.install-meta"

  local default_shell
  default_shell=$(basename "${SHELL:-bash}")
  info "Detected default shell: $default_shell"

  local configure_bash=0
  local configure_zsh=0
  local prompt_style=""

  local bash_default="N"
  [[ $default_shell == bash ]] && bash_default="Y"

  if prompt_yes_no "Configure Bash prompt?" "$bash_default"; then
    if [[ -z $prompt_style ]]; then
      choose_prompt_style prompt_style
      info "Using $prompt_style layout for prompts."
    fi
    local bash_prompt_file=""
    choose_prompt_variant bash_prompt_file
    write_prompt_style "$HOME/.bashrc" "$prompt_style"
    append_block "$HOME/.bashrc" "# >>> myprompts prompt >>>" "source \"$INSTALL_ROOT/$bash_prompt_file\""
    configure_bash=1
    apply_aliases_for_shell "$HOME/.bashrc" bash_aliases
  fi

  local zsh_default="N"
  [[ $default_shell == zsh ]] && zsh_default="Y"

  if prompt_yes_no "Configure Zsh prompt?" "$zsh_default"; then
    if [[ -z $prompt_style ]]; then
      choose_prompt_style prompt_style
      info "Using $prompt_style layout for prompts."
    fi
    write_prompt_style "$HOME/.zshrc" "$prompt_style"
    append_block "$HOME/.zshrc" "# >>> myprompts prompt >>>" "[[ -f \"$INSTALL_ROOT/$PROMPT_ZSH\" ]] && source \"$INSTALL_ROOT/$PROMPT_ZSH\""
    configure_zsh=1
    apply_aliases_for_shell "$HOME/.zshrc" zsh_aliases
  fi

  if prompt_yes_no "Install Vaporwave LS_COLORS theme?" Y; then
    local line="[ -f \"$INSTALL_ROOT/$LS_COLORS_FILE\" ] && source \"$INSTALL_ROOT/$LS_COLORS_FILE\""

    if (( configure_bash )); then
      append_block "$HOME/.bashrc" "# >>> myprompts lscolors >>>" "$line"
      ensure_ls_alias "$HOME/.bashrc"
    elif [[ -f $HOME/.bashrc ]]; then
      if prompt_yes_no "Add LS colors to Bash (.bashrc)?" N; then
        append_block "$HOME/.bashrc" "# >>> myprompts lscolors >>>" "$line"
        ensure_ls_alias "$HOME/.bashrc"
      fi
    fi

    if (( configure_zsh )); then
      append_block "$HOME/.zshrc" "# >>> myprompts lscolors >>>" "$line"
      ensure_ls_alias "$HOME/.zshrc"
    elif [[ -f $HOME/.zshrc ]]; then
      if prompt_yes_no "Add LS colors to Zsh (.zshrc)?" Y; then
        append_block "$HOME/.zshrc" "# >>> myprompts lscolors >>>" "$line"
        ensure_ls_alias "$HOME/.zshrc"
      fi
    fi
  fi

  cat <<'SUMMARY'

Installation complete!
- Restart your shell or run "source ~/.bashrc" / "source ~/.zshrc" to activate.
- Re-run this installer anytime to change variants; existing blocks are updated in place.
SUMMARY
}

main "$@"
