# myprompts

Vaporwave-themed shell prompts with automated system configuration.

## Features

- Shell prompt themes for Bash and Zsh
- Animated and static prompt variants
- Custom LS colors matching the vaporwave aesthetic
- Automated package installation via Ansible
- Cross-platform support (macOS, Linux)

## Installation

```bash
curl -fsSL https://raw.githubusercontent.com/[username]/myprompts/main/install.sh | bash
```

Or clone and run locally:

```bash
git clone https://github.com/[username]/myprompts.git
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

### Liquid Prompt
Animated Bash prompt with wave effects.

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
macos_brew_formulae=(gh nmap netcat)
linux_apt_packages=(nmap netcat)
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

Pre-select options:

```bash
PROMPT_VARIANT=liquid PROMPT_STYLE=extended bash install.sh
```

## Manual Installation

Individual components can be sourced directly:

```bash
# Bash prompt
source vaporwave_bash_prompt

# Liquid prompt
source vaporwave_liquid_prompt

# Zsh prompt
source vaporwave_zsh_prompt

# LS colors
cp vaporwave_lscolors ~/.vaporwave_lscolors
source vaporwave_ls_setup.sh
```

## File Structure

```
├── install.sh                  # Main installer
├── vaporwave_bash_prompt       # Bash static prompt
├── vaporwave_liquid_prompt     # Bash animated prompt
├── vaporwave_zsh_prompt        # Zsh prompt
├── vaporwave_lscolors          # LS_COLORS definitions
├── vaporwave_ls_setup.sh       # LS colors setup helper
├── config/
│   ├── packages.sh             # Package definitions
│   └── aliases.sh              # Alias definitions
└── ansible/
    └── playbook.yml            # Package installation playbook
```

## Requirements

- Bash 3.2+ or Zsh
- curl (for installation)
- git (for branch detection in prompts)
- 256-color terminal support (recommended)
- Unicode support (for liquid prompt)

## Environment Variables

- `MYPROMPTS_PROMPT_STYLE` - Set to `compact` or `extended`
- `MYPROMPTS_NONINTERACTIVE` - Set to `1` for non-interactive mode
- `PROMPT_VARIANT` - Pre-select variant: `bash`, `liquid`, or `zsh`
- `PROMPT_STYLE` - Pre-select style: `compact` or `extended`

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

## License

[License information to be added]

## Contributing

See AGENTS.md for development guidelines.