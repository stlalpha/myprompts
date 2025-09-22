# Repository Guidelines

## Project Structure & Module Organization
- `vaporwave_bash_prompt`: primary Bash prompt theme with static neon palette; honours `MYPROMPTS_PROMPT_STYLE=compact|extended`.
- `vaporwave_liquid_prompt`: animated prompt variant; relies on Unicode wave frames and time-based color cycling.
- `vaporwave_zsh_prompt`: Zsh-native prompt that mirrors the classic Bash layout, including git branch detection.
- `vaporwave_lscolors`: exported `LS_COLORS` table that maps common extensions to the vaporwave colorway.
- `vaporwave_ls_setup.sh`: legacy helper that only wires LS colors; retained for users who prefer manual sourcing.
- `install.sh`: curl-friendly bootstrapper; detects existing installs, prompts before purging, and wires assets under `~/.local/share/myprompts`.

## Build, Test, and Development Commands
- There is no compilation step; source prompt files directly during development:
  ```bash
  source ./vaporwave_bash_prompt
  source ./vaporwave_liquid_prompt
  source ./vaporwave_zsh_prompt
  ```
- Exercise the installer with a local file URL before publishing updates:
  ```bash
  HOME=$(mktemp -d) BASE_URL="file://$PWD" INSTALL_ROOT="$HOME/.myprompts" \
  SHELL=/bin/bash bash ./install.sh
  ```
- Non-interactive runs can pre-select variants, e.g. `PROMPT_VARIANT=liquid PROMPT_STYLE=extended ./install.sh` (otherwise the script uses `/dev/tty` so `curl ... | bash` stays interactive).
- Apply the LS colors locally before shipping changes:
  ```bash
  cp vaporwave_lscolors ~/.vaporwave_lscolors
  source vaporwave_ls_setup.sh
  ```

## Coding Style & Naming Conventions
- Author Bash scripts with four-space indentation inside functions and align continuation lines for readability.
- Exported environment variables stay uppercase with underscores; helper functions use lower_snake_case.
- Prefer portable POSIX/Bash builtins; keep escape sequences inside single-quoted strings to avoid unintended expansion.
- Run `shellcheck` on every script to catch quoting and portability issues: `shellcheck vaporwave_*.sh vaporwave_*prompt`.

## Testing Guidelines
- Validate prompts by sourcing the script in a fresh shell and confirming user, host, path, and git branch render correctly.
- Exercise both `compact` and `extended` styles by toggling `MYPROMPTS_PROMPT_STYLE` prior to sourcing.
- Exercise animated prompts in terminals that support 256 colors and Unicode; fall back gracefully in minimal TTYs.
- For Zsh, ensure `setopt prompt_subst` is active and the prompt renders without layout drift on `%n`, `%m`, and `%~` substitutions.
- After running `install.sh` (or sourcing `vaporwave_lscolors` directly), open a new session and check `ls -la --color=auto` for expected palette; the installer injects an `alias ls='ls --color=auto'` block when no alias exists.

## Commit & Pull Request Guidelines
- Follow Conventional Commits (e.g., `feat: add liquid prompt throttle`) so tooling can parse change intent.
- Reference tracked issues when available and include before/after terminal screenshots for visual changes.
- PRs should describe manual verification steps, shell versions tested, and any dependencies on specific terminal capabilities.

## Setup Tips for New Agents
- Keep local copies of prompts under version control; do not edit the installed dotfiles directly.
- Document any terminal-specific tweaks (e.g., iTerm color profiles) in the PR to inform reviewers and downstream users.
