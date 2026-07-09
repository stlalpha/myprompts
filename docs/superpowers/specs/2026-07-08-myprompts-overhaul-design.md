# myprompts overhaul — design

Date: 2026-07-08
Status: approved, pending implementation plan

## Context

`myprompts` installs vaporwave-themed shell prompts plus a package bootstrap via
Ansible. It works, but it has one hard bug, a prompt that is less useful than it
could be, no license or CI, no uninstall, and a 1375-line monolithic installer.

Audience is the author's own machines. `curl | bash` must keep working.

## Verified findings

Claims below were checked against the machine, not asserted from memory.

- **Confirmed bug.** `vaporwave_bash_prompt:30` and `vaporwave_liquid_prompt:90`
  use `${style,,}`, which is Bash 4+ syntax. Under `/bin/bash` (3.2.57 on
  Darwin 25) this is `${style,,}: bad substitution`.

  Corrected during implementation: bash does **not** abort on this. It prints to
  stderr and continues, and `source` still returns 0. So the prompt does load.
  The two real symptoms are:

  1. Every new shell prints `bad substitution` to stderr.
  2. Case-insensitive style selection is broken. The failed assignment leaves
     `$style` uppercased, so `MYPROMPTS_PROMPT_STYLE=EXTENDED` silently falls
     through to the compact branch. Lowercase `extended` works by accident.

  A regression test must therefore assert on **stderr and on the selected
  layout**, never on the exit status of `source` — that would pass vacuously.
- **Not a bug.** `date +%N` was assumed unsupported on macOS. It works
  (`/bin/date +%N` → nanoseconds). Recent Darwin supports it.
- **Not a bug.** `neofetch` (7.1.0) and `netcat` (0.7.1) are both still
  installable via Homebrew. neofetch's *upstream* was archived in 2024, so
  migrating to `fastfetch` is a maintenance recommendation, not a fix. The
  apt/dnf/pacman side was not verified and no claim is made about it.
- **Not a bug.** `/bin/ls --color=auto` is supported on Darwin 25, so
  `ensure_ls_alias` is correct as written.
- **Design flaw, not a portability bug.** The liquid prompt derives its wave
  frame from the current nanosecond. A prompt only redraws when it is drawn, so
  the frame is effectively random per command rather than animated.

## Decisions

| Decision | Choice |
| --- | --- |
| Distribution | `curl \| bash` stays supported |
| Branding | Migrate to Signal Mine; vaporwave becomes one theme among several |
| Liquid prompt | Deleted, not fixed |
| Indicators | Exit status, git dirty, SSH, root, jobs, command duration |
| License | None. Remove the placeholder section from the README |
| Installer refactor | Do it, but last — after tests exist to catch regressions |

## Architecture

### Theme layer

New `themes/` directory. One file per palette, each defining an identical set of
named color variables:

```
themes/signalmine.sh   # default
themes/vaporwave.sh
```

Prompts source a palette instead of hardcoding escape sequences. Selection via
`MYPROMPTS_THEME`, defaulting to `signalmine`.

Palettes emit 24-bit color when `COLORTERM` is `truecolor` or `24bit`, and fall
back to the 256-color cube otherwise. Brand colors and their 256-color
approximations:

| Name | Hex | 256 |
| --- | --- | --- |
| Signal Orange | `#FF7705` | 208 |
| Signal Coral | `#FF3C4B` | 203 |
| Signal Magenta | `#FF0090` | 198 |
| Lime | `#D2FC00` | 190 |
| Cyan | `#00D9B5` | 43 |
| Charcoal | `#343434` | 236 |
| Black | `#1B1B1B` | 234 |

Interface contract: a theme file sets the color variables and nothing else. It
must not touch `PS1`, `PROMPT`, or install hooks. A prompt must render correctly
against any theme file without knowing which one it sourced.

### Prompt rewrite

`vaporwave_liquid_prompt` is deleted, along with its references in `install.sh`
(`PROMPT_LIQUID`, `download_asset`, `choose_prompt_variant`) and the README.

Remaining prompts are rebuilt around segments. Each segment is a function
returning a rendered string or the empty string when it has nothing to say.

| Segment | Source | Cost |
| --- | --- | --- |
| Exit status | `$?` | none |
| Jobs | `\j` (bash), `%j` (zsh) | none |
| SSH | `$SSH_CONNECTION` / `$SSH_TTY` | none |
| Root | `$EUID` | none |
| Git | one `git status` call | one subprocess |
| Duration | `SECONDS` builtin | none |

**Exit status** must be captured as the literal first statement of the prompt
function, before any other command runs, or `$?` is clobbered.

**Git** uses a single call:

```
git status --porcelain=v2 --branch --untracked-files=no
```

This yields branch name and dirty state together, replacing the current
two-concern `git branch | sed` (which also mangles detached HEAD). Ahead/behind
is deliberately excluded: it needs a second call and goes stale without a fetch,
so it misinforms. Disable the whole segment with `MYPROMPTS_GIT=0`.

**Duration** uses the shell's `SECONDS` builtin rather than `date`, eliminating
the portability question entirely. Bash stamps the start via a `DEBUG` trap;
that trap is installed defensively, chaining to any pre-existing `DEBUG` trap
rather than overwriting it. Zsh uses `preexec`. Nothing renders below
`MYPROMPTS_DURATION_MIN` (default `5`).

**Bash** moves from a static `PS1` to a `PROMPT_COMMAND` that rebuilds `PS1` each
draw, because exit status and duration cannot be computed at source time. The
`\[…\]` non-printing markers continue to work because Bash re-expands `PS1` on
every draw. `PROMPT_COMMAND` is appended to, not overwritten.

**Bash 3.2 fix.** `${style,,}` becomes a `case` over a `tr`-lowercased value,
evaluated once at source time rather than per prompt.

### Uninstall

`install.sh` already writes every modification behind sentinel markers of the
form `# >>> myprompts … >>>` / `# <<< myprompts … <<<`. A new `uninstall.sh`:

1. strips marked blocks from `~/.bashrc` and `~/.zshrc`
2. removes `INSTALL_ROOT`
3. restores the neofetch config it displaced

Note a prerequisite: `install.sh` currently overwrites
`~/.config/neofetch/config.conf` unconditionally and keeps no backup, so there is
nothing for an uninstall to restore. Install must first be changed to move any
pre-existing config aside to `config.conf.myprompts-backup` before writing. If no
backup exists at uninstall time, the config written by this tool is removed and
nothing is restored.

### Installer refactor

`install.sh` becomes a bootstrapper. If a `lib/` directory sits adjacent to it,
source from there. Otherwise fetch the repo tarball to a temp dir and re-exec.
This is the `rustup` / `oh-my-zsh` pattern and needs no build step and no
generated artifact in git.

Body splits into:

```
lib/ui.sh         # print_header, info, error, prompt_yes_no, menus
lib/os.sh         # detect_os, detect_linux_package_manager
lib/packages.sh   # load_configuration, filter_missing_packages, install_*
lib/ansible.sh    # ensure_ansible, generate_ansible_vars, run_ansible_bootstrap
lib/shell.sh      # append_block, write_prompt_style, ensure_ls_alias
```

Each module is independently sourceable and testable. The existing
`download_asset` / `BASE_URL` per-file fetch machinery is deleted — fetching the
tree once subsumes it.

## Testing

New `test_prompts.sh`:

- sources each prompt under `/bin/bash` (3.2) and asserts success — this is the
  regression test for the confirmed bug
- asserts `PS1` / `PROMPT` is non-empty after sourcing
- asserts clean sourcing under `set -u`
- drives the git segment through a temp repo in clean, dirty, and detached-HEAD
  states
- asserts the exit-status segment renders the correct code after a failing
  command

New `test_uninstall.sh`: install into a temp `HOME`, uninstall, assert the rc
files are **byte-identical** to their pre-install contents.

This is achievable only if uninstall also consumes the blank line that
`append_block` emits before each opening marker. Stripping only the marker-to-
marker span leaves a stray newline and the assertion can never pass. The removal
must span from the blank line preceding the opening marker through the closing
marker inclusive.

Existing `test_installer.sh` and `test_appstore.sh` are retained.

CI via GitHub Actions on a `ubuntu-latest` + `macos-latest` matrix, running
shellcheck and the full suite. The macOS runner is what provides Bash 3.2
coverage.

## Repo hygiene

- No `LICENSE`. Remove the `## License` placeholder section from `README.md`.
- `.gitignore` gains `.beads/`, `.code-graph/`, `*.sqlite3`, and
  `pyghidra_mcp_projects/`.
- `proxmox-jobs.sqlite3` and `pyghidra_mcp_projects/` are untracked, unrelated to
  this project, and were not created by this work. They will be gitignored and
  **left on disk**, not deleted.
- `AGENTS.md` content merges into `CLAUDE.md`; `AGENTS.md` becomes a pointer.
- `README.md` is corrected: drop the liquid prompt, document the new environment
  variables (`MYPROMPTS_THEME`, `MYPROMPTS_GIT`, `MYPROMPTS_DURATION_MIN`), and
  fix the file-structure tree.

## Sequence

Ordered so that behavior-changing work lands before the no-behavior-change
refactor, and so the refactor lands on top of tests that can catch a regression.

1. Repo hygiene — `.gitignore`, README, `AGENTS.md`/`CLAUDE.md` merge
2. Theme layer — `themes/signalmine.sh`, `themes/vaporwave.sh`
3. Prompt rewrite — Bash 3.2 fix, segments, indicators; delete liquid prompt
4. `uninstall.sh`
5. `test_prompts.sh`, `test_uninstall.sh`, GitHub Actions CI
6. Installer refactor into `lib/` with bootstrap-then-exec

## Out of scope

- Ahead/behind git indicators (stale without a fetch)
- A true background-redraw animated prompt (fights readline)
- `neofetch` → `fastfetch` migration (recommended, not required; separate change)
- Any Linux package-list changes, which could not be verified from this machine
