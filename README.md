# myprompts

Vaporwave-themed shell prompts with automated system configuration.

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
  - Debian/Ubuntu (apt)
  - Fedora/RHEL (dnf)
  - Arch Linux (pacman/paru)

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

## Testing

Run shellcheck on scripts:

```bash
shellcheck vaporwave_*.sh vaporwave_*prompt install.sh
```

Test installer locally:

```bash
HOME=$(mktemp -d) BASE_URL="file://$PWD" INSTALL_ROOT="$HOME/.myprompts" \
SHELL=/bin/bash bash ./install.sh
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
