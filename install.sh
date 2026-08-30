#!/usr/bin/env bash
set -euo pipefail

# Interactive installer for the myprompts collection.
# Installs vaporwave prompt themes and configures the detected shell.

MYPROMPTS_REPO=${MYPROMPTS_REPO:-"https://github.com/stlalpha/myprompts"}
MYPROMPTS_REF=${MYPROMPTS_REF:-main}

INSTALL_ROOT=${INSTALL_ROOT:-"$HOME/.local/share/myprompts"}
PROMPT_STATIC=vaporwave_bash_prompt
PROMPT_ZSH=vaporwave_zsh_prompt
LS_COLORS_FILE=vaporwave_lscolors

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
pending_macos_appstore_apps=()
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

# The bootstrap writes a freshly generated token into this file inside the
# directory it creates, and passes the same token to its re-exec'd child.
# cleanup() removes a directory only when the token inside it matches, so
# neither an unrelated MYPROMPTS_TMP_SRC inherited from the caller's
# environment nor a stale directory left by an earlier bootstrap can be
# deleted. Shape alone is not proof of ownership: a killed bootstrap leaves a
# directory with the same basename pattern and the same sentinel file.
MYPROMPTS_TMP_SENTINEL=.myprompts-bootstrap

myprompts_new_tmp_token() {
  local token=""
  if [[ -r /dev/urandom ]]; then
    token=$(od -An -tx1 -N16 /dev/urandom 2>/dev/null | tr -d ' \n')
  fi
  # Fallback for a system without a readable /dev/urandom. Weaker, but this
  # only has to be unguessable enough that a stale directory never matches.
  [[ -n $token ]] || token="$$-${RANDOM}-${RANDOM}-$(date +%s 2>/dev/null)"
  printf '%s' "$token"
}

myprompts_tmp_is_ours() {
  local dir=${1:-}
  [[ -n $dir && -d $dir ]] || return 1
  [[ -n ${MYPROMPTS_TMP_TOKEN:-} ]] || return 1
  local sentinel="$dir/$MYPROMPTS_TMP_SENTINEL"
  [[ -f $sentinel ]] || return 1
  local recorded=""
  IFS= read -r recorded < "$sentinel" 2>/dev/null || return 1
  [[ $recorded == "$MYPROMPTS_TMP_TOKEN" ]] || return 1
  # Structural guard, kept as a second line of defence.
  case "${dir##*/}" in
    myprompts.??????) return 0 ;;
    *) return 1 ;;
  esac
}

cleanup() {
  if [[ $TTY_FD_OPENED -eq 1 ]]; then
    exec 3>&-
  fi
  # Set only when this process was re-exec'd out of a fetched tarball. By the
  # time the trap runs the install has copied everything it needs out of it.
  if myprompts_tmp_is_ours "${MYPROMPTS_TMP_SRC:-}"; then
    rm -rf "$MYPROMPTS_TMP_SRC"
  fi
}

trap cleanup EXIT

info()  { printf '\e[1;36m[info]\e[0m %s\n' "$*"; }
warn()  { printf '\e[1;33m[warn]\e[0m %s\n' "$*"; }

# Locate our source tree. When run from a clone, lib/ sits next to us. When
# piped from curl there is no $0 to resolve, so fetch the tree and re-exec.
myprompts_bootstrap() {
  local self_dir=""
  if [[ -n ${BASH_SOURCE[0]:-} && -f ${BASH_SOURCE[0]} ]]; then
    self_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
  fi

  if [[ -n $self_dir && -d "$self_dir/lib" && -f "$self_dir/lib/ui.sh" ]]; then
    MYPROMPTS_SRC=$self_dir
    # Nothing was fetched by THIS process. That covers two cases: a real clone,
    # where any MYPROMPTS_TMP_SRC came from the caller's environment and must
    # be dropped; and the re-exec'd child of a bootstrap, which also resolves
    # via the adjacent lib/ but whose inherited value is the tree it must
    # clean up. The sentinel tells them apart.
    if ! myprompts_tmp_is_ours "${MYPROMPTS_TMP_SRC:-}"; then
      unset MYPROMPTS_TMP_SRC MYPROMPTS_TMP_TOKEN
    fi
    return 0
  fi

  local tmp tmp_base
  # A bare `mktemp -d` ignores TMPDIR on macOS (it uses the Darwin per-user
  # temp dir), which makes the location unpredictable and the cleanup
  # untestable. Give it an explicit template so both platforms agree.
  tmp_base=${TMPDIR:-/tmp}
  tmp_base=${tmp_base%/}
  tmp=$(mktemp -d "$tmp_base/myprompts.XXXXXX")
  # Mark it as ours before anything else can fail: a token this process just
  # generated, recorded inside the directory and handed to the child. cleanup()
  # deletes only on an exact match, so neither an unrelated inherited path nor
  # a stale directory from a previous run can be removed.
  local token
  token=$(myprompts_new_tmp_token)
  printf '%s\n' "$token" > "$tmp/$MYPROMPTS_TMP_SENTINEL"
  # Export before the fetch, not after: if the curl | tar pipeline fails, the
  # EXIT trap still knows what to clean up.
  export MYPROMPTS_TMP_SRC=$tmp
  export MYPROMPTS_TMP_TOKEN=$token
  echo "Fetching myprompts..."
  # /archive/<ref>.tar.gz resolves a branch, a tag or a commit SHA. The
  # /archive/refs/heads/<ref>.tar.gz form this used to build only resolves
  # branches, so MYPROMPTS_REF=<tag|sha> 404'd.
  curl -fsSL "$MYPROMPTS_REPO/archive/$MYPROMPTS_REF.tar.gz" \
    | tar -xz -C "$tmp" --strip-components=1
  MYPROMPTS_SRC=$tmp
  # exec replaces this process, so its EXIT trap never runs; the child's
  # cleanup() removes the tree instead (MYPROMPTS_TMP_SRC was exported above).
  # The child is whichever version MYPROMPTS_REF names, so fetching a ref older
  # than this change still leaks -- nothing this side can do about that.
  exec bash "$tmp/install.sh" "$@"
}

myprompts_bootstrap "$@"

# shellcheck source=lib/ui.sh
. "$MYPROMPTS_SRC/lib/ui.sh"
# shellcheck source=lib/os.sh
. "$MYPROMPTS_SRC/lib/os.sh"
# shellcheck source=lib/packages.sh
. "$MYPROMPTS_SRC/lib/packages.sh"
# shellcheck source=lib/ansible.sh
. "$MYPROMPTS_SRC/lib/ansible.sh"
# shellcheck source=lib/shell.sh
. "$MYPROMPTS_SRC/lib/shell.sh"

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

  install -m 644 "$MYPROMPTS_SRC/$PROMPT_STATIC" "$INSTALL_ROOT/$PROMPT_STATIC"
  install -m 644 "$MYPROMPTS_SRC/$PROMPT_ZSH" "$INSTALL_ROOT/$PROMPT_ZSH"
  install -m 644 "$MYPROMPTS_SRC/$LS_COLORS_FILE" "$INSTALL_ROOT/$LS_COLORS_FILE"
  cp -R "$MYPROMPTS_SRC/themes" "$INSTALL_ROOT/themes"
  mkdir -p "$INSTALL_ROOT/lib"
  install -m 644 "$MYPROMPTS_SRC/lib/prompt_common.sh" "$INSTALL_ROOT/lib/prompt_common.sh"

  info "Installing fastfetch configuration"
  mkdir -p "$HOME/.config/fastfetch"
  mkdir -p "$INSTALL_ROOT/fastfetch"
  install -m 644 "$MYPROMPTS_SRC/fastfetch/config-vaporwave.jsonc" "$INSTALL_ROOT/fastfetch/config-vaporwave.jsonc"
  install -m 644 "$MYPROMPTS_SRC/fastfetch/config-boxed.jsonc" "$INSTALL_ROOT/fastfetch/config-boxed.jsonc"
  install -m 644 "$MYPROMPTS_SRC/fastfetch/signalmine.txt" "$HOME/.config/fastfetch/signalmine.txt"
  local fastfetch_style=""
  choose_fastfetch_style fastfetch_style
  info "Using $fastfetch_style for fastfetch"
  local fastfetch_target="$HOME/.config/fastfetch/config.jsonc"
  local fastfetch_backup="$fastfetch_target.myprompts-backup"
  if [[ -f $fastfetch_target && ! -f $fastfetch_backup ]]; then
    info "Backing up existing fastfetch config to ${fastfetch_backup/#$HOME/~}"
    mv "$fastfetch_target" "$fastfetch_backup"
  fi
  cp "$INSTALL_ROOT/fastfetch/$fastfetch_style" "$fastfetch_target"
  chmod 644 "$fastfetch_target"

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
    local bash_prompt_file="$PROMPT_STATIC"
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
