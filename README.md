# myprompts

Themed shell prompts with automated system configuration. Ships three
palettes -- `signalmine` (default), `vaporwave` and `ember` -- for Bash and Zsh.

## Features

- Shell prompt themes for Bash and Zsh
- Static prompt variants for Bash and Zsh
- Custom LS colors matching the vaporwave aesthetic
- Automated package installation via Ansible
- fastfetch system-info layouts with a Signal Mine ASCII logo
- Mac App Store app installation support (macOS)
- Cross-platform support (macOS, Linux)

## Installation

```bash
curl -fsSL https://raw.githubusercontent.com/stlalpha/myprompts/main/install.sh | bash
```

Or clone and run locally:

```bash
git clone https://github.com/stlalpha/myprompts.git
cd myprompts
bash install.sh
```

## Supported Platforms

- macOS (Homebrew)
- Linux
  - Debian 13+ / Ubuntu 24.04+ (apt)
  - Fedora/RHEL (dnf)
  - Arch Linux (pacman/paru)

### Homebrew on Linux (opt-in)

Linux installs use the native package manager by default. Set
`MYPROMPTS_LINUX_BREW=1` (or answer the prompt) to use Homebrew instead — it
then **fully replaces** apt/dnf/pacman rather than supplementing them, and
Homebrew is bootstrapped if missing. Casks and Mac App Store apps remain
macOS-only; Linuxbrew has no cask support. Homebrew will not install as root.

`fastfetch` is not packaged for Debian 12 (bookworm) or older, so the apt
package step will fail there. Everything else installs normally; drop
`fastfetch` from `linux_apt_packages` if you are on bookworm.

## Prompt Variants

### Classic Bash Prompt
Static prompt with git branch detection.

### Zsh Prompt
Zsh-native implementation with hooks.

## Prompt Styles

Toggle between compact (single-line) and extended (multi-line) layouts:

```bash
export MYPROMPTS_PROMPT_STYLE=compact   # or extended
```

## Configuration

### Package Lists

Edit `config/packages.sh` to customize installed packages per platform:

```bash
macos_brew_formulae=(mas gh nmap netcat)
macos_brew_casks=(iterm2 bettertouchtool)
macos_appstore_apps=(441258766)  # Magnet window manager
linux_apt_packages=(nmap netcat)
```

### Mac App Store Apps (macOS)

**Important**: You must sign in to the Mac App Store app before the installer can install App Store apps.

The `mas account` command is broken on macOS 12+ due to Apple framework changes. The installer uses the community.general.mas Ansible module which attempts installation regardless and handles failures gracefully.

To find App Store app IDs:
```bash
mas search "app name"
```

### Shell Aliases

Edit `config/aliases.sh` to add custom aliases:

```bash
bash_aliases=("alias ll='ls -la'")
zsh_aliases=("alias ll='ls -la'")
```

## Non-Interactive Installation

For automated deployments:

```bash
MYPROMPTS_NONINTERACTIVE=1 bash install.sh
```

This skips all prompts and also skips package installation entirely — only the
prompt files, LS colors, and shell configuration are installed.

Pre-select options:

```bash
PROMPT_STYLE=extended bash install.sh
```

## Manual Installation

Individual components can be sourced directly:

```bash
# Bash prompt
source vaporwave_bash_prompt

# Zsh prompt
source vaporwave_zsh_prompt

# LS colors
cp vaporwave_lscolors ~/.vaporwave_lscolors
source vaporwave_ls_setup.sh
```

## File Structure

```
├── install.sh                  # Main installer
├── uninstall.sh                # Reverses install.sh
├── vaporwave_bash_prompt       # Bash static prompt
├── vaporwave_zsh_prompt        # Zsh prompt
├── vaporwave_lscolors          # LS_COLORS definitions
├── vaporwave_ls_setup.sh       # LS colors setup helper
├── themes/                     # Theme palettes (signalmine, vaporwave, ember)
├── lib/
│   └── prompt_common.sh        # Shared prompt helpers (theme, git, duration)
├── fastfetch/                  # fastfetch configs + Signal Mine ASCII logo
├── tools/
│   └── scale_ascii.py          # Rescales the ASCII logo, preserving colors
├── config/
│   ├── packages.sh             # Package definitions
│   └── aliases.sh              # Alias definitions
└── ansible/
    └── playbook.yml            # Package installation playbook
```

## Command Duration

The Bash prompt times each command and shows the elapsed seconds once it
crosses `MYPROMPTS_DURATION_MIN`. On Bash 4.4+ it arms the timer through
`PS0`, appending to any `PS0` you already set and leaving `DEBUG` traps
untouched.

Bash 3.2 (the macOS system Bash) has no `PS0`, so it falls back to a `DEBUG`
trap. If you already have a `DEBUG` trap of your own, Bash 3.2 will not let a
sourced file replace it, and a sourced file cannot read it either — so your
trap keeps working and no duration is shown. Upgrading to a current Bash
(`brew install bash`) removes the limitation.

## Requirements

- Bash 3.2+ or Zsh
- curl (for installation)
- git (for branch detection in prompts)
- 256-color terminal support (recommended)

## Environment Variables

- `MYPROMPTS_PROMPT_STYLE` - Set to `compact` or `extended`
- `MYPROMPTS_NONINTERACTIVE` - Set to `1` for non-interactive mode
- `MYPROMPTS_THEME` - Set to `signalmine` (default), `vaporwave`, or `ember`
- `MYPROMPTS_GIT` - Set to `0` to disable the git segment
- `MYPROMPTS_DURATION_MIN` - Seconds before a command duration is shown (default `5`)
- `PROMPT_STYLE` - Pre-select style: `compact` or `extended`
- `FASTFETCH_STYLE` - Pre-select fastfetch layout: `vaporwave` or `boxed`
- `MYPROMPTS_LINUX_BREW` - Set to `1` to install Linux packages with Homebrew instead of apt/dnf/pacman

## Testing

Run the whole suite (this is what CI runs):

```bash
./run_tests.sh
```

Lint. `install.sh` and `lib/*.sh` must be passed together, because `install.sh`
sources the modules through a path computed at runtime and shellcheck can only
resolve the cross-file globals when it sees both:

```bash
shellcheck install.sh uninstall.sh run_tests.sh vaporwave_ls_setup.sh \
           config/*.sh themes/*.sh lib/*.sh test_*.sh
shellcheck --shell=bash vaporwave_bash_prompt
```

`vaporwave_zsh_prompt` is intentionally not linted: shellcheck has no zsh
support and misparses zsh-only syntax.

Test the installer against a throwaway `HOME`:

```bash
T=$(mktemp -d)
HOME="$T" INSTALL_ROOT="$T/.myprompts" MYPROMPTS_NONINTERACTIVE=1 \
PROMPT_STYLE=extended SHELL=/bin/bash bash ./install.sh
```

## Contributing

See AGENTS.md for development guidelines.
## System Info (fastfetch)

The installer writes a `fastfetch` config to `~/.config/fastfetch/config.jsonc`
and the Signal Mine ASCII logo alongside it. Two layouts ship:

- `vaporwave` (default) - colored `◆` keys with `【HARDWARE】` / `【NETWORK】` section headers
- `boxed` - minimal cyan/teal layout inside a `.---.` border

Pick one non-interactively with `FASTFETCH_STYLE=boxed`. An existing config is
moved to `config.jsonc.myprompts-backup` before the first overwrite, and
`uninstall.sh` puts it back.

This replaces neofetch, which was archived upstream in 2024 and has since been
dropped by Homebrew, apt, dnf and pacman.
