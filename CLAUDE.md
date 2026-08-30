# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Themed shell prompt system with automated configuration and package installation. Two prompt variants (Bash, Zsh) sharing a theme layer (`signalmine` default, `vaporwave`, `ember`) and matching LS colors, distributed via a curl-friendly install script that bootstraps prompts and packages via Ansible.

## Architecture

### Prompt System
- Prompts are standalone shell scripts that can be sourced directly
- All prompts honor `MYPROMPTS_PROMPT_STYLE=compact|extended` for layout control
- Color palettes use 256-color ANSI codes (e.g., `\033[38;5;198m`)
- Git branch detection is embedded directly in each prompt variant using `git branch 2>/dev/null`

### Installation Flow
1. `install.sh` detects existing installations and prompts for purge if needed
2. Resolves its source tree: uses an adjacent `lib/` when run from a clone, otherwise fetches the repo tarball and re-execs (this is what makes `curl | bash` work). Installs prompt files, themes, LS colors and the fastfetch config to `~/.local/share/myprompts`
3. Sources `config/packages.sh` (Bash-sourced, not parsed) to build OS-specific package lists
4. Generates `ansible_vars.yml` with platform-filtered packages
5. Executes `ansible/playbook.yml` locally with `hosts: localhost` to install packages
6. Injects shell initialization code into `.bashrc` or `.zshrc`

### Interactive Mode Handling
- Installer uses `/dev/tty` (file descriptor 3) for interactive prompts to support `curl | bash` installation
- This allows script to read from stdin for downloading while prompting user on terminal
- Non-interactive mode (`MYPROMPTS_NONINTERACTIVE=1`) skips prompts and skips package installation

### Configuration System
- `config/packages.sh`: Platform-specific package arrays (e.g., `macos_brew_formulae`, `linux_paru_packages`)
- `config/aliases.sh`: Shell-specific alias definitions grouped by shell
- Installer filters packages by detected platform and package manager availability
- Config files are sourced by Bash during installation (not parsed as data)

### System Info Tool
- `fastfetch` replaced `neofetch` (archived upstream 2024, delisted from every
  targeted package manager). Configs are JSONC, not neofetch's Bash-sourced
  `config.conf`.
- ASCII logo color placeholders are fastfetch's `$1`/`$2`, not neofetch's
  `${c1}`/`${c2}`. `tools/scale_ascii.py` reads that same syntax.
- Installed to `~/.config/fastfetch/config.jsonc`; layout chosen by
  `choose_fastfetch_style` (`FASTFETCH_STYLE=vaporwave|boxed`).
- The ASCII logo ships as the 60% reduction (`signalmine_60.txt`);
  `signalmine.txt` is the full-size master the scaler reads from. Regenerate
  the variants with `tools/scale_ascii.py <src> <scale> <dst>` -- it box-filters
  the glyph density ramp rather than subsampling, which is what keeps
  one-glyph-wide strokes alive at 50%.
- The boxed layout's frame is drawn by `fastfetch/boxfetch.sh`, not by the
  config. fastfetch cannot close a right-hand border: values are variable
  length and it has no line-padding or right-align facility (`--key-width`
  aligns keys only; format strings take no width specifier, and defaults are
  compiled in so they cannot be re-emitted with a trailing rail). boxfetch.sh
  runs fastfetch with `--logo none --pipe false`, measures the rendered width,
  draws all four edges to fit, then pastes the logo alongside. Exposed as the
  `sysinfo` alias; plain `fastfetch` still works and just shows the left rail.

### Homebrew on Linux
- Opt-in via `MYPROMPTS_LINUX_BREW=1` or an interactive prompt; default is the
  native package manager, so existing Linux installs are unaffected.
- When active it **replaces** apt/dnf/pacman rather than supplementing them.
  `select_linux_manager` returns `brew`, and `handle_package_bootstrap` fills
  `pending_macos_brew_formulae` while leaving the native pending arrays empty.
- Packages are installed by Ansible, not by the `install_*` functions in
  `lib/packages.sh` (those are dead code). The signal reaches the playbook as
  `package_manager: "brew"` in the generated vars file, and the formulae task
  is gated on `target_os == 'macos' or package_manager == 'brew'`.
- Casks and App Store apps stay macOS-only — Linuxbrew has no cask support.
- `MYPROMPTS_BREW_CANDIDATES` lists the brew locations probed by
  `ensure_homebrew_in_path`; it exists so tests can inject a stub.

### Mac App Store Integration
- Uses `mas` CLI tool via Ansible's `community.general.mas` module
- `mas account` is broken on macOS 12+ due to Apple framework changes
- Users must sign in through Mac App Store GUI before running installer
- Playbook uses `failed_when: false` to handle sign-in detection failures gracefully
- Magnet.app is automatically added to login items if installed at `/Applications/Magnet.app`

## Development Commands

### Testing Prompts
Source directly during development:
```bash
source ./vaporwave_bash_prompt
source ./vaporwave_zsh_prompt
```

Test both styles:
```bash
MYPROMPTS_PROMPT_STYLE=compact source ./vaporwave_bash_prompt
MYPROMPTS_PROMPT_STYLE=extended source ./vaporwave_bash_prompt
```

### Testing Installer
Local test with temporary HOME:
```bash
T=$(mktemp -d)
HOME="$T" INSTALL_ROOT="$T/.myprompts" SHELL=/bin/bash bash ./install.sh
```

Non-interactive with pre-selected options:
```bash
PROMPT_STYLE=extended MYPROMPTS_NONINTERACTIVE=1 bash ./install.sh
```

### Testing LS Colors
```bash
cp vaporwave_lscolors ~/.vaporwave_lscolors
source vaporwave_ls_setup.sh
ls -la --color=auto
```

### Linting
`install.sh` and `lib/*.sh` must be linted in one invocation: `install.sh`
sources the modules via a runtime-computed path, so shellcheck resolves the
cross-file globals only when it sees both. `vaporwave_zsh_prompt` is
deliberately excluded -- shellcheck has no zsh support.
```bash
shellcheck install.sh uninstall.sh run_tests.sh vaporwave_ls_setup.sh \
           config/*.sh themes/*.sh lib/*.sh test_*.sh
shellcheck --shell=bash vaporwave_bash_prompt
```

### Test Suite
`run_tests.sh` aggregates every suite and is what CI runs. Prefer it; the
individual suites are for iterating on one area.
```bash
./run_tests.sh            # everything (this is what CI runs)

bash test_prompts.sh      # Bash prompt behaviour, incl. bash 3.2 regressions
bash test_zsh_prompt.sh   # Zsh prompt
bash test_themes.sh       # theme palettes and colour rendering
bash test_installer.sh    # installer, incl. set -u compliance
bash test_uninstall.sh    # uninstall round trips and rc-block safety
bash test_appstore.sh     # Mac App Store integration
```
`test_prompts.sh` honours `BASH32=/path/to/bash` so the suite can be pointed at
a bash 5.x build locally to reproduce what CI sees on Linux.

## Coding Standards

### Shell Scripting
- Use four-space indentation inside functions
- Prefer POSIX/Bash builtins over external commands
- Keep escape sequences in single quotes to avoid expansion
- Run `shellcheck` on all scripts before committing
- Use `set -euo pipefail` for robust error handling

### Naming Conventions
- Environment variables: `UPPERCASE_WITH_UNDERSCORES`
- Functions: `lower_snake_case`
- Global variables in prompts: Match shell conventions (e.g., `PS1`, `PROMPT`)

### Portability Requirements
- Test on both macOS and Linux
- Verify 256-color support gracefully degrades
- Prompts require a UTF-8 locale for their box-drawing and arrow glyphs
- Zsh prompts require `setopt prompt_subst`

## Package Configuration

### Adding Packages
Edit `config/packages.sh` and add to appropriate array:
```bash
macos_brew_formulae=(mas gh nmap netcat YOUR_PACKAGE)
macos_brew_casks=(iterm2 bettertouchtool YOUR_CASK)
macos_appstore_apps=(441258766)  # Find IDs with: mas search "app name"
linux_apt_packages=(nmap netcat YOUR_PACKAGE)
linux_dnf_packages=(nmap nmap-ncat YOUR_PACKAGE)
linux_pacman_packages=(nmap YOUR_PACKAGE)
linux_paru_packages=(gnu-netcat YOUR_AUR_PACKAGE)
```

### Ansible Playbook Structure
- `ansible/playbook.yml` runs locally with `hosts: localhost`
- Variables injected via `ansible_vars.yml` generated by installer
- Conditional task blocks based on `target_os` and `package_manager`
- Homebrew cask failures handled for apps at unexpected paths (`failed_when` checks stderr)
- App Store installation failures ignored (`failed_when: false`, `ignore_errors: true`)

## Key Files

- `install.sh`: Bootstrapper -- resolves the source tree (adjacent `lib/`, else repo tarball + re-exec), then drives the modules below
- `lib/ui.sh`, `lib/os.sh`, `lib/packages.sh`, `lib/ansible.sh`, `lib/shell.sh`: installer modules (prompts/output, OS detection, package filtering, vars generation + playbook run, rc-file injection)
- `lib/prompt_common.sh`: shared prompt runtime -- theme loading, color rendering, git and duration segments
- `themes/{signalmine,vaporwave,ember}.sh`: color-role palettes as `<256index>:<hex>`
- `uninstall.sh`: reverses `install.sh`, restoring displaced files byte-identically
- `run_tests.sh`: aggregates every suite; this is what CI runs
- `test_helpers.sh`: shared assertions and counters, including the accounting invariant
- `vaporwave_bash_prompt`: Bash prompt, segment-based, bash 3.2 compatible
- `vaporwave_zsh_prompt`: Zsh native prompt mirroring Bash layout with Zsh-specific hooks
- `vaporwave_lscolors`: Exported `LS_COLORS` table for file extension colorization
- `vaporwave_ls_setup.sh`: Helper to wire LS colors (for manual sourcing, legacy)
- `fastfetch/boxfetch.sh`: draws the closed box around fastfetch output (fastfetch cannot pad lines, so the frame must be measured after the fact)
- `tools/scale_ascii.py`: density-preserving downscaler for the ASCII logo
- `ansible/playbook.yml`: Local package installation with conditional blocks per package manager
- `config/packages.sh`: Platform-specific package definitions (Bash arrays)
- `config/aliases.sh`: Shell-specific alias definitions (Bash arrays)
- `test_installer.sh`: Test suite for installer with set -u compliance tests
- `test_appstore.sh`: Mac App Store integration validation tests

## Git Workflow

- Follow Conventional Commits (e.g., `feat: add prompt duration threshold`, `fix: handle missing git binary`)
- Include terminal screenshots for visual changes
- Document manual testing steps in PR descriptions
- Note shell versions and terminal emulators tested

<!-- code-graph-mcp:begin v2 -->
## Code Graph (repo-wide AST index)

AST + FTS + vector index of the whole repo — prefer over multi-round Grep/Read for
structural queries (LSP only sees open files; this sees everything). Fastest path = Bash CLI:

| Intent | Command |
|--------|---------|
| Who calls X / what X calls | `code-graph-mcp callgraph X` |
| Impact before editing a fn | `code-graph-mcp impact X` |
| Unfamiliar dir / module | `code-graph-mcp overview <dir>` |
| Symbol source / signature | `code-graph-mcp show X` |
| Concept search (no exact name) | `code-graph-mcp search "…"` (vector: MCP `semantic_code_search`) |
| grep + AST context | `code-graph-mcp grep "pat" [paths] [-t lang] [-g glob] [-c]` |

Still use Grep for literal strings/regex in non-code files; still Read files you'll edit.
Full command + MCP-tool table: `.claude/plugin_code_graph_mcp.md`
<!-- code-graph-mcp:end -->
