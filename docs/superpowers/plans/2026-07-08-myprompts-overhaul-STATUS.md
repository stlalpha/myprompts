# myprompts overhaul — status

**Status: COMPLETE.** Merged to `main` via PR #2 (merge commit `1f7f5c1`) on
2026-08-30. Tasks 1-12 all landed. Task 12b (Homebrew on Linux) landed
separately on 2026-08-30. No plan items remain outstanding.

**Branch:** `feat/overhaul` (merged and deleted).
**Plan:** `docs/superpowers/plans/2026-07-08-myprompts-overhaul.md`
**Spec:** `docs/superpowers/specs/2026-07-08-myprompts-overhaul-design.md`

Tasks 1-7 were complete and reviewed when this file was first written; tasks
8-12 landed afterwards. The per-task detail below was accurate at the time and
is kept as a record -- see the corrections at the bottom for what has since
been proven wrong.

## Current test state

| Suite | Result |
| --- | --- |
| `test_themes.sh` | 6/6, exit 0 |
| `test_prompts.sh` | 19/19, exit 0 |
| `test_zsh_prompt.sh` | 4/4, exit 0 |
| `test_appstore.sh` | exit 0 |
| `test_installer.sh` | **exit 1 — pre-existing, fails identically on `main`** |

`shellcheck` is clean on every script and on `vaporwave_bash_prompt`.

### The pre-existing `test_installer.sh` failure (since fixed)

Not caused by this branch. `filter_missing_packages` leaks `[info] brew formula
'gh' already installed; skipping.` lines into its return value, so the
`Expected empty result` assertion fails on any machine where those packages are
already present. It passes on a clean machine, which is why it was never caught.

**This blocks Task 11 (CI).** `run_tests.sh` aggregates every suite, so CI would
be red from the first run. Fix `filter_missing_packages` to send its `info`
output to stderr (or suppress it in the filtering path) before wiring up CI.

## Completed

1. **Repo hygiene.** `.gitignore` now hides `.beads/`, `.claude/`, `*.sqlite3`,
   `pyghidra_mcp_projects/`. `AGENTS.md` reduced to a pointer at `CLAUDE.md`.
   `proxmox-jobs.sqlite3` and `pyghidra_mcp_projects/` were left on disk,
   untouched, as agreed.
2. **`test_helpers.sh`.** Shared assertions. `assert_contains` refuses an empty
   needle; `test_fail` renders messages with `%s` so captured escape sequences
   print literally.
3. **Regression test for the Bash 3.2 bug**, written to fail first.
4. **The Bash 3.2 fix.**
5. **Theme layer.** `themes/signalmine.sh` (default) and `themes/vaporwave.sh`
   declare colour roles as `<256index>:<hex>`. `lib/prompt_common.sh` renders
   24-bit colour when `COLORTERM` advertises it, else the 256-colour cube.
6. **Bash prompt rewrite.** Exit status, duration, git dirty state, ssh/root,
   jobs. One subprocess per draw (the sanctioned `git status`).
7. **Zsh prompt rewrite.** Mirrors it, using `%F{}` and `%(1j.…)` — zero forks.

**Post-plan addition (commit `f7e42e9`):** `themes/ember.sh` — a third
selectable palette (ember-orange on steel, molten-red failure marker), modelled
after send.themcbros.com, palette extracted from the live site. Selected with
`MYPROMPTS_THEME=ember`. Covered by `test_themes.sh`; renders in truecolor and
256-color; both prompts pick it up.

## Corrections made to the plan and spec during implementation

Three of the plan's own prescriptions were wrong and were fixed in place. They
are recorded because they are the kind of thing that gets "fixed" back.

1. **Bash does not abort on `bad substitution`.** It warns and continues;
   `source` still returns 0. The original regression test asserted on the exit
   status and therefore passed vacuously. The real symptoms are stderr noise on
   every shell start, and broken case-insensitive style selection
   (`MYPROMPTS_PROMPT_STYLE=EXTENDED` silently fell through to compact). Tests
   now assert on those. Commit `7c1a38a`.

2. **`test_theme_defines_all_roles` passed when `themes/` did not exist.**
   `2>&1` folded stderr into the captured value, so `No such file or directory`
   satisfied the non-empty check. It now inspects the nested shell's exit
   status. Commit `b61bacd`.

3. **The DEBUG-trap chain corrupted the user's trap.** Parsing `trap -p` output
   by string-trimming meant `trap '' DEBUG` produced
   `trap -- '; myprompts_timer_start' DEBUG` — a bash syntax error printed
   before *every command in the shell* — and a trap body containing a single
   quote silently dropped the timer. It now recovers the body via bash's own
   parser. Commit `1deccda`.

Two facts asserted early on turned out to be false and were corrected in the
spec: `date +%N` **does** work on Darwin 25, and `neofetch`/`netcat` were then
still installable via Homebrew.

> **The neofetch half of that has since expired -- see the corrections below.**

## Open minor items for the final review

- `test_prompts.sh`: the static bash-4-syntax grep matches the literal token
  even inside **comments**. Do not write it in a comment in any prompt file.
- `test_prompts.sh`: `elapsed=$((…))` was rewritten to the arithmetic command
  `((elapsed = …))` purely because `$((` contains `$(` and inflated a
  grep-based fork-count guard. The guard should arguably have been fixed
  instead of the code.
- `test_prompts.sh`: `run_bounded()` falls back to **unbounded** execution when
  `timeout` is absent — which is stock macOS. That recursion guard does not
  guard on the primary dev platform.
- `lib/prompt_common.sh`: a branch literally named `(detached)` is
  indistinguishable from a detached HEAD. Inherent to `--porcelain=v2`.
- The static grep misses the pattern-restricted forms (`${var^^pattern}`).

## Corrections found after this file was written

Both of these were recorded here as settled facts and were relied on. They are
not. Read this section before trusting anything above it.

1. **"`neofetch` is still installable via Homebrew. Do not 'fix' it." -- no
   longer true.** neofetch was archived upstream in April 2024 and the Homebrew
   formula has since been delisted: `formulae.brew.sh/api/formula/neofetch.json`
   returns 404 while the formula index returns 200. The original check was
   almost certainly `brew list` against an already-installed copy, which
   succeeds forever regardless of what the tap ships. Migrated to `fastfetch`
   in PR #3. The "do not fix" instruction is what made this worth writing down:
   a correct-at-the-time fact, stated as a standing prohibition, outlived its
   own truth.

2. **"The DEBUG-trap chain was fixed in `1deccda`" -- it never worked.**
   `myprompts_capture_debug_trap` read the previous trap with
   `spec=$(trap -p DEBUG)`, but a sourced file cannot see a DEBUG trap set by
   its caller: `trap -p DEBUG` reports nothing from inside one, at function
   scope, at file scope, and through a plain redirect alike. `spec` was always
   empty, so the capture always returned early and the previous body was never
   recorded. With a pre-existing DEBUG trap the measured behaviour was: bash
   3.2 kept the user's trap and never installed our timer; bash 5.x destroyed
   the user's trap and installed ours. Two defects that cancelled on 3.2 into
   exactly the string the test grepped for, which is why the suite was green on
   macOS and went red the first time CI ran it on bash 5.2. Replaced with `PS0`
   on bash 4.4+ (which chains properly, since `PS0` is a readable variable) and
   a documented limitation on bash 3.2.

## Remaining tasks

All of the below are now DONE.

- **Task 8** (done) — delete `vaporwave_liquid_prompt`, strip `PROMPT_LIQUID` and
  `choose_prompt_variant` from `install.sh`, update `README.md` / `CLAUDE.md`.
  Also corrects a doc bug: both claim non-interactive mode still installs
  packages. It does not — `handle_package_bootstrap` returns early when
  `INTERACTIVE` is 0.
- **Task 9** (done) — back up an existing neofetch config before overwriting it.
  Prerequisite for uninstall.
- **Task 10** (done) — `uninstall.sh`. Must consume the blank line `append_block` emits
  before each marker, or the byte-identical assertion cannot pass.
- **Task 11** (done) — `run_tests.sh` + GitHub Actions on ubuntu + macos.
  **Blocked** on the `test_installer.sh` failure above.
- **Task 12** (done) — split `install.sh` into `lib/` modules behind a
  bootstrap-then-exec. No behaviour change. Its `curl | bash` verification
  needs a pushed branch and network; that step is a hard merge gate.
- **Task 12b** (done) — Homebrew on Linux, folded into the Task 12
  refactor. Opt-in, bootstrap-installs brew if missing, and when active fully
  replaces apt/dnf/pacman on Linux. Full spec is in the plan file after Task 12.

## To resume

```bash
git checkout feat/overhaul
cat .superpowers/sdd/progress.md    # per-task ledger (gitignored)
```

Then execute Task 8 onward from the plan.
