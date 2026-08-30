# myprompts Overhaul Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the Bash 3.2 prompt bug, migrate branding to Signal Mine via a theme layer, add useful prompt indicators, add an uninstall path and CI, then modularize the 1375-line installer.

**Architecture:** Prompts source a palette file from `themes/` that declares color *roles* as 256-color indices plus hex pairs; each prompt renders those roles into its own shell's escape syntax. Prompt content is assembled per-draw from small segment functions. `install.sh` keeps working under `curl | bash` by becoming a bootstrapper that uses an adjacent `lib/` when present and otherwise fetches the repo tarball and re-execs.

**Tech Stack:** Bash 3.2+ (the floor, because macOS ships 3.2.57), Zsh 5.x, Ansible, GitHub Actions, shellcheck.

## Global Constraints

- **Bash floor is 3.2.57.** No `${var,,}`, no `declare -A`, no `mapfile`, no `${var^^}`. Verified: `/bin/bash` on Darwin 25 is 3.2.57.
- **`curl | bash` must keep working.** No build step, no generated artifact committed to git.
- Every script must pass `shellcheck` and must source cleanly under `set -u`.
- Prompt segments must add **zero subprocesses** except the single `git status` call.
- Default theme is `signalmine`. `vaporwave` and `ember` remain available.
  (`themes/ember.sh` was added post-plan, commit `f7e42e9` — ember-orange on
  steel, modelled after send.themcbros.com.)
- No `LICENSE` file. The `## License` section is removed from `README.md`, not filled in.
- `proxmox-jobs.sqlite3` and `pyghidra_mcp_projects/` are **gitignored, never deleted.**
- Prompt filenames (`vaporwave_bash_prompt`, `vaporwave_zsh_prompt`) are **not renamed** — renaming would break the `source` lines already written into users' rc files.

## Verified Facts

These were tested on the target machine. Do not re-litigate them.

- `/bin/bash -c 'style=X; echo ${style,,}'` → `bad substitution`. This is the bug.
- `git status --porcelain=v2 --branch --untracked-files=no` emits `# branch.head main` or `# branch.head (detached)`, `# branch.oid <sha>`, and one non-`#` line per dirty path.
- `jobs %%` is a **builtin** returning 0 iff a job exists. No fork. Use it to gate `\j`.
- `trap -p DEBUG` prints `trap -- '<cmd>' DEBUG`, enabling trap chaining.
- `SECONDS` is a Bash/Zsh builtin. Never shell out to `date` for timing.
- `date +%N` and `ls --color=auto` both work on Darwin 25. Not bugs. Do not "fix" them.

## File Structure

| Path | Responsibility |
| --- | --- |
| `themes/signalmine.sh` | Signal Mine palette. Declares color roles only. |
| `themes/vaporwave.sh` | Vaporwave palette. Same role names. |
| `lib/prompt_common.sh` | `mp_fg`, `mp_load_theme`, `mp_git_segment`. Shell-agnostic. |
| `vaporwave_bash_prompt` | Bash prompt. `PROMPT_COMMAND` + `DEBUG` trap. |
| `vaporwave_zsh_prompt` | Zsh prompt. `precmd` + `preexec`. |
| `uninstall.sh` | Reverses `install.sh`. |
| `test_helpers.sh` | Shared `test_start`/`test_pass`/`test_fail`/`assert_*`. |
| `test_prompts.sh` | Prompt behavior, incl. the Bash 3.2 regression test. |
| `test_uninstall.sh` | Byte-identical rc-file restoration. |
| `.github/workflows/ci.yml` | shellcheck + suite on ubuntu + macos. |
| `lib/{ui,os,packages,ansible,shell}.sh` | Task 11 only. Split of `install.sh`. |
| `vaporwave_liquid_prompt` | **Deleted** in Task 7. |

## Theme Role Contract

A theme file sets exactly these variables and nothing else. It must not touch
`PS1`, `PROMPT`, or install hooks.

| Role | Meaning | signalmine | vaporwave |
| --- | --- | --- | --- |
| `MP_ACCENT1` | user / primary | `208:FF7705` | `209:FF875F` |
| `MP_ACCENT2` | host / secondary | `203:FF3C4B` | `141:AF87FF` |
| `MP_ACCENT3` | git branch | `198:FF0090` | `198:FF0087` |
| `MP_OK` | success, path | `190:D2FC00` | `85:5FFFD7` |
| `MP_INFO` | punctuation | `43:00D9B5` | `51:00FFFF` |
| `MP_ERR` | failure | `203:FF3C4B` | `196:FF0000` |
| `MP_MUTED` | duration, jobs | `244:808080` | `244:808080` |

Format is `<256index>:<hex>`. `mp_fg` picks the hex when `COLORTERM` is
`truecolor` or `24bit`, else the index.

---

## Task 1: Repo hygiene and doc consolidation

**Files:**
- Modify: `.gitignore`
- Modify: `CLAUDE.md`
- Modify: `AGENTS.md`

**Interfaces:**
- Consumes: nothing
- Produces: nothing consumed by later tasks

No tests: this task changes no executable behavior. The verification is that
`git status` stops showing unrelated files.

- [ ] **Step 1: Verify the stray files are present and untracked**

Run: `git status --short`
Expected: `?? proxmox-jobs.sqlite3` and `?? pyghidra_mcp_projects/` appear.

Do not delete them. They are not ours.

- [ ] **Step 2: Rewrite `.gitignore`**

```gitignore
.code-graph/
.beads/
.claude/
*.sqlite3
pyghidra_mcp_projects/
ansible_vars.yml
```

- [ ] **Step 3: Verify the stray files are now ignored**

Run: `git status --short`
Expected: neither `proxmox-jobs.sqlite3` nor `pyghidra_mcp_projects/` is listed.
Expected: both still exist on disk — confirm with `ls proxmox-jobs.sqlite3`.

- [ ] **Step 4: Replace `AGENTS.md` with a pointer**

`CLAUDE.md` already contains everything in `AGENTS.md` and more. Replace the
entire contents of `AGENTS.md` with:

```markdown
# Repository Guidelines

See [CLAUDE.md](CLAUDE.md). This file is retained as a pointer for tools that
look for `AGENTS.md` by convention.
```

- [ ] **Step 5: Commit**

```bash
git add .gitignore AGENTS.md
git commit -m "chore: ignore unrelated local artifacts, fold AGENTS.md into CLAUDE.md"
```

---

## Task 2: Shared test helpers

**Files:**
- Create: `test_helpers.sh`

**Interfaces:**
- Produces: `test_start(name)`, `test_pass()`, `test_fail(msg)`,
  `assert_eq(expected, actual, msg)`, `assert_contains(haystack, needle, msg)`,
  `test_summary()` (exits 1 if any test failed).
  Every later test file sources this.

This mirrors the existing conventions in `test_installer.sh` so the suite stays
consistent.

- [ ] **Step 1: Create `test_helpers.sh`**

```bash
#!/usr/bin/env bash
# Shared assertions for the myprompts test suite.

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

test_start() {
    TESTS_RUN=$((TESTS_RUN + 1))
    printf 'Testing %s... ' "$1"
}

test_pass() {
    TESTS_PASSED=$((TESTS_PASSED + 1))
    printf '%b\n' "${GREEN}✓${NC}"
}

test_fail() {
    TESTS_FAILED=$((TESTS_FAILED + 1))
    printf '%b\n' "${RED}✗${NC}"
    printf '%b\n' "  ${RED}Failed: $1${NC}"
}

assert_eq() {
    if [ "$1" = "$2" ]; then
        test_pass
    else
        test_fail "$3 (expected '$1', got '$2')"
    fi
}

assert_contains() {
    case "$1" in
        *"$2"*) test_pass ;;
        *) test_fail "$3 (expected '$1' to contain '$2')" ;;
    esac
}

test_summary() {
    printf '\n%s run, %s passed, %s failed\n' "$TESTS_RUN" "$TESTS_PASSED" "$TESTS_FAILED"
    [ "$TESTS_FAILED" -eq 0 ]
}
```

- [ ] **Step 2: Verify it sources cleanly under `set -u` in Bash 3.2**

Run: `/bin/bash -c 'set -u; source ./test_helpers.sh; test_start x; test_pass; test_summary'`
Expected: prints `Testing x... ✓` then `1 run, 1 passed, 0 failed`, exit 0.

- [ ] **Step 3: Commit**

```bash
git add test_helpers.sh
git commit -m "test: add shared assertion helpers"
```

---

## Task 3: Failing regression test for the Bash 3.2 bug

**Files:**
- Create: `test_prompts.sh`

**Interfaces:**
- Consumes: `test_helpers.sh`
- Produces: `test_prompts.sh`, extended by Tasks 5 and 6.

This is TDD. The test must fail *before* Task 4 fixes the bug. Do not fix the
prompt in this task.

- [ ] **Step 1: Write the failing test**

```bash
#!/usr/bin/env bash
# Prompt behavior tests. Must pass under Bash 3.2 (the macOS system bash).
set -uo pipefail

cd "$(dirname "$0")"
source ./test_helpers.sh

# Bash 3.2 is the floor: macOS ships 3.2.57 as /bin/bash.
BASH32=/bin/bash

# Returns the layout a given style string actually produces. The extended
# layout is the only one containing a newline, so that is the discriminator.
prompt_layout_for_style() {
    local ps1
    ps1=$("$BASH32" -c "MYPROMPTS_PROMPT_STYLE=$1 source ./vaporwave_bash_prompt 2>/dev/null; printf '%s' \"\$PS1\"")
    case "$ps1" in
        *$'\n'*) printf 'extended' ;;
        *) printf 'compact' ;;
    esac
}

# NOTE: bash does NOT abort on `bad substitution` inside a sourced file — it
# prints to stderr and keeps going, so `source` still returns 0. Asserting on
# the exit status would silently pass. Assert on stderr instead.
test_bash_prompt_sources_silently_under_bash32() {
    test_start "vaporwave_bash_prompt sources without stderr output under bash 3.2"
    local err
    err=$("$BASH32" -c 'MYPROMPTS_PROMPT_STYLE=compact source ./vaporwave_bash_prompt' 2>&1 >/dev/null)
    if [ -z "$err" ]; then
        test_pass
    else
        test_fail "sourcing wrote to stderr: $err"
    fi
}

test_bash_prompt_sets_ps1() {
    test_start "vaporwave_bash_prompt sets a non-empty PS1"
    local out
    out=$("$BASH32" -c 'MYPROMPTS_PROMPT_STYLE=compact source ./vaporwave_bash_prompt >/dev/null 2>&1; printf %s "${PS1:-}"' 2>&1)
    if [ -n "$out" ]; then test_pass; else test_fail "PS1 was empty"; fi
}

# The failed `${style,,}` assignment leaves $style uppercased, so an uppercase
# style silently falls through to the compact branch.
test_bash_prompt_style_is_case_insensitive() {
    local s
    for s in extended EXTENDED Extended; do
        test_start "MYPROMPTS_PROMPT_STYLE=$s selects the extended layout"
        assert_eq "extended" "$(prompt_layout_for_style "$s")" "layout for style '$s'"
    done
    test_start "MYPROMPTS_PROMPT_STYLE=compact selects the compact layout"
    assert_eq "compact" "$(prompt_layout_for_style compact)" "layout for style 'compact'"
}

test_bash_prompt_sources_silently_under_bash32
test_bash_prompt_sets_ps1
test_bash_prompt_style_is_case_insensitive
test_summary
```

- [ ] **Step 2: Run it and confirm it FAILS**

Run: `chmod +x test_prompts.sh && ./test_prompts.sh`
Expected: FAIL, exactly two of the five tests:

1. `sources without stderr output` fails with
   `sourcing wrote to stderr: ./vaporwave_bash_prompt: line 30: ${style,,}: bad substitution`
2. `MYPROMPTS_PROMPT_STYLE=EXTENDED selects the extended layout` fails with
   `expected 'extended', got 'compact'` — and likewise for `Extended`.

`sets a non-empty PS1`, the lowercase `extended` case, and the `compact` case
all PASS today. That is expected: bash continues past the bad substitution, so
`PS1` is still assigned and lowercase input never needed lowercasing.

If all five pass, the bug is already fixed and something is wrong — stop and
investigate rather than proceeding.

- [ ] **Step 3: Commit the failing test**

```bash
git add test_prompts.sh
git commit -m "test: add failing regression test for bash 3.2 prompt sourcing"
```

---

## Task 4: Fix the Bash 3.2 bug

**Files:**
- Modify: `vaporwave_bash_prompt:29-30`
- Modify: `vaporwave_liquid_prompt:89-90`

**Interfaces:**
- Consumes: `test_prompts.sh` from Task 3
- Produces: nothing new

`vaporwave_liquid_prompt` is deleted in Task 7, but it is fixed here anyway so
that `git bisect` never lands on a commit where it is broken.

- [ ] **Step 1: Fix `vaporwave_bash_prompt`**

Replace lines 29-30:

```bash
style="${MYPROMPTS_PROMPT_STYLE:-compact}"
style=${style,,}
```

with:

```bash
# Lowercase without ${var,,}, which requires bash 4. macOS ships bash 3.2.
style="${MYPROMPTS_PROMPT_STYLE:-compact}"
style=$(printf '%s' "$style" | tr '[:upper:]' '[:lower:]')
```

- [ ] **Step 2: Apply the identical fix to `vaporwave_liquid_prompt` lines 89-90**

Same two lines, same replacement.

- [ ] **Step 3: Run the test and confirm it PASSES**

Run: `./test_prompts.sh`
Expected: `5 run, 5 passed, 0 failed`, exit 0.

- [ ] **Step 4: Verify the two symptoms are gone, directly**

Sourcing must now be silent. `source` returns 0 either way, so check stderr:

```bash
err=$(/bin/bash -c 'source ./vaporwave_bash_prompt' 2>&1 >/dev/null)
[ -z "$err" ] && echo "silent: ok" || echo "STILL NOISY: $err"
```
Expected: `silent: ok`.

And uppercase styles must now select the extended layout (it contains a newline):

```bash
for s in extended EXTENDED Extended compact; do
  ps1=$(/bin/bash -c "MYPROMPTS_PROMPT_STYLE=$s source ./vaporwave_bash_prompt 2>/dev/null; printf '%s' \"\$PS1\"")
  case "$ps1" in *$'\n'*) l=extended ;; *) l=compact ;; esac
  printf '  %-10s -> %s\n' "$s" "$l"
done
```
Expected: `extended`, `EXTENDED`, `Extended` all map to `extended`; `compact`
maps to `compact`.

- [ ] **Step 5: Commit**

```bash
git add vaporwave_bash_prompt vaporwave_liquid_prompt test_prompts.sh
git commit -m "fix: replace bash 4 \${var,,} expansion, restoring bash 3.2 support

macOS ships bash 3.2.57 as /bin/bash, where \${style,,} is a syntax error.
Both bash prompts failed to source at all on a stock Mac shell."
```

---

## Task 5: Theme layer

**Files:**
- Create: `themes/signalmine.sh`
- Create: `themes/vaporwave.sh`
- Create: `lib/prompt_common.sh`
- Create: `test_themes.sh`

**Interfaces:**
- Produces:
  - Theme files set `MP_ACCENT1 MP_ACCENT2 MP_ACCENT3 MP_OK MP_INFO MP_ERR MP_MUTED`,
    each a string `"<256index>:<hex>"`.
  - `mp_fg <role_value>` → prints a raw SGR foreground sequence (no `\[ \]` wrapping).
  - `mp_reset` → prints `\033[0m`.
  - `mp_load_theme [name]` → sources `themes/<name>.sh`, defaulting to
    `${MYPROMPTS_THEME:-signalmine}`; falls back to `signalmine` if the named
    theme file does not exist.
  - `MP_LIB_DIR` → directory containing `prompt_common.sh`.

- [ ] **Step 1: Write the failing test**

```bash
#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")"
source ./test_helpers.sh

BASH32=/bin/bash
ROLES="MP_ACCENT1 MP_ACCENT2 MP_ACCENT3 MP_OK MP_INFO MP_ERR MP_MUTED"

test_theme_defines_all_roles() {
    local theme=$1
    test_start "themes/$theme.sh defines every role"
    local missing=""
    for role in $ROLES; do
        local val
        val=$("$BASH32" -c "set -u; source ./themes/$theme.sh; printf '%s' \"\${$role:-}\"" 2>&1)
        [ -n "$val" ] || missing="$missing $role"
    done
    if [ -z "$missing" ]; then test_pass; else test_fail "missing:$missing"; fi
}

test_role_format() {
    test_start "roles use <256index>:<hex> format"
    local val
    val=$("$BASH32" -c 'set -u; source ./themes/signalmine.sh; printf "%s" "$MP_ACCENT3"')
    assert_eq "198:FF0090" "$val" "signalmine MP_ACCENT3"
}

test_mp_fg_256() {
    test_start "mp_fg emits a 256-color code when COLORTERM is unset"
    local out
    out=$(COLORTERM= "$BASH32" -c 'set -u; source ./lib/prompt_common.sh; mp_fg 198:FF0090' | cat -v)
    assert_eq '^[[38;5;198m' "$out" "256-color output"
}

test_mp_fg_truecolor() {
    test_start "mp_fg emits a 24-bit code when COLORTERM=truecolor"
    local out
    out=$(COLORTERM=truecolor "$BASH32" -c 'set -u; source ./lib/prompt_common.sh; mp_fg 198:FF0090' | cat -v)
    assert_eq '^[[38;2;255;0;144m' "$out" "truecolor output"
}

test_theme_fallback() {
    test_start "mp_load_theme falls back to signalmine for an unknown theme"
    local val
    val=$(MYPROMPTS_THEME=nonesuch "$BASH32" -c 'set -u; source ./lib/prompt_common.sh; mp_load_theme; printf "%s" "$MP_ACCENT3"')
    assert_eq "198:FF0090" "$val" "fallback palette"
}

test_theme_defines_all_roles signalmine
test_theme_defines_all_roles vaporwave
test_role_format
test_mp_fg_256
test_mp_fg_truecolor
test_theme_fallback
test_summary
```

- [ ] **Step 2: Run it and confirm it FAILS**

Run: `chmod +x test_themes.sh && ./test_themes.sh`
Expected: FAIL, every test, because `themes/` and `lib/prompt_common.sh` do not exist.

- [ ] **Step 3: Create `themes/signalmine.sh`**

```bash
#!/usr/bin/env bash
# Signal Mine palette. Format: <256-color index>:<hex>
# Sets color roles only. Must not touch PS1/PROMPT or install hooks.

MP_ACCENT1=208:FF7705   # Signal Orange
MP_ACCENT2=203:FF3C4B   # Signal Coral
MP_ACCENT3=198:FF0090   # Signal Magenta
MP_OK=190:D2FC00        # Electric Lime
MP_INFO=43:00D9B5       # Cyan
MP_ERR=203:FF3C4B       # Signal Coral
MP_MUTED=244:808080     # Gray
```

- [ ] **Step 4: Create `themes/vaporwave.sh`**

```bash
#!/usr/bin/env bash
# Vaporwave palette. Format: <256-color index>:<hex>
# Sets color roles only. Must not touch PS1/PROMPT or install hooks.

MP_ACCENT1=209:FF875F   # Sunset orange
MP_ACCENT2=141:AF87FF   # Light purple
MP_ACCENT3=198:FF0087   # Hot pink
MP_OK=85:5FFFD7         # Mint
MP_INFO=51:00FFFF       # Bright cyan
MP_ERR=196:FF0000       # Red
MP_MUTED=244:808080     # Gray
```

- [ ] **Step 5: Create `lib/prompt_common.sh`**

Note `${role%%:*}` and `${role#*:}` split the pair, and `0x${hex:0:2}` converts
hex to decimal via arithmetic expansion — all Bash 3.2 safe.

```bash
#!/usr/bin/env bash
# Shell-agnostic prompt helpers. Sourced by both the bash and zsh prompts.
# Emits RAW escape sequences; callers wrap them for their own shell.

# Resolve our own directory so we can find themes/ regardless of cwd.
# Must not use zsh-only expansions here: this file is sourced by bash too, and
# ${(%):-%x} is a bad substitution under bash.
if [ -z "${MP_ROOT_DIR:-}" ]; then
    if [ -n "${BASH_SOURCE:-}" ]; then
        _mp_self=${BASH_SOURCE[0]}
    else
        _mp_self=$0          # zsh sets $0 to the sourced file
    fi
    MP_LIB_DIR=$(cd "$(dirname "$_mp_self")" && pwd)
    MP_ROOT_DIR=$(dirname "$MP_LIB_DIR")
    unset _mp_self
fi

mp_truecolor() {
    case "${COLORTERM:-}" in
        truecolor|24bit) return 0 ;;
        *) return 1 ;;
    esac
}

# mp_fg <256index>:<hex>  -> raw SGR foreground sequence
mp_fg() {
    local pair=$1
    local idx=${pair%%:*}
    local hex=${pair#*:}
    if mp_truecolor; then
        printf '\033[38;2;%d;%d;%dm' \
            "$((0x${hex:0:2}))" "$((0x${hex:2:2}))" "$((0x${hex:4:2}))"
    else
        printf '\033[38;5;%sm' "$idx"
    fi
}

mp_reset() { printf '\033[0m'; }
mp_bold()  { printf '\033[1m'; }

# mp_load_theme [name]
mp_load_theme() {
    local name=${1:-${MYPROMPTS_THEME:-signalmine}}
    local file="$MP_ROOT_DIR/themes/$name.sh"
    if [ ! -f "$file" ]; then
        file="$MP_ROOT_DIR/themes/signalmine.sh"
    fi
    # shellcheck source=/dev/null
    . "$file"
}

# mp_git_segment -> "[branch]" or "[branch*]" or "[@abc1234]" or nothing.
# Exactly one subprocess. --untracked-files=no keeps it fast in large trees.
mp_git_segment() {
    if [ "${MYPROMPTS_GIT:-1}" = "0" ]; then
        return 0
    fi
    local out head oid line dirty=0
    out=$(git status --porcelain=v2 --branch --untracked-files=no 2>/dev/null) || return 0
    head=""
    oid=""
    while IFS= read -r line; do
        case "$line" in
            '# branch.head '*) head=${line#\# branch.head } ;;
            '# branch.oid '*)  oid=${line#\# branch.oid } ;;
            '#'*) ;;
            ?*) dirty=1 ;;
        esac
    done <<EOF
$out
EOF
    [ -n "$head" ] || return 0
    if [ "$head" = "(detached)" ]; then
        head="@${oid:0:7}"
    fi
    if [ "$dirty" -eq 1 ]; then
        printf '[%s*]' "$head"
    else
        printf '[%s]' "$head"
    fi
}
```

- [ ] **Step 6: Run the test and confirm it PASSES**

Run: `./test_themes.sh`
Expected: `6 run, 6 passed, 0 failed`, exit 0.

- [ ] **Step 7: Verify the git segment against real repo states**

```bash
T=$(mktemp -d); (cd "$T" && git init -q && git config user.email t@t && git config user.name t \
  && echo a > a && git add a && git commit -qm one \
  && /bin/bash -c "set -u; source $PWD/lib/prompt_common.sh; mp_git_segment; echo")
rm -rf "$T"
```
Expected: `[main]` (or `[master]` depending on your `init.defaultBranch`).

- [ ] **Step 8: Commit**

```bash
git add themes lib/prompt_common.sh test_themes.sh
git commit -m "feat: add theme layer with signalmine and vaporwave palettes

Themes declare color roles as <256index>:<hex>. mp_fg renders 24-bit color
when COLORTERM advertises it and falls back to the 256-color cube otherwise."
```

---

## Task 6: Bash prompt segments

**Files:**
- Modify: `vaporwave_bash_prompt` (full rewrite)
- Modify: `test_prompts.sh` (append tests)

**Interfaces:**
- Consumes: `mp_fg`, `mp_reset`, `mp_bold`, `mp_load_theme`, `mp_git_segment`,
  and the `MP_*` roles from Task 5.
- Produces: `myprompts_build_ps1()` (assigned to `PROMPT_COMMAND`),
  `myprompts_timer_start()` (installed on the `DEBUG` trap).

Critical ordering constraint: `local exit_code=$?` **must** be the first
statement of `myprompts_build_ps1`, before any other command runs, or `$?` is
clobbered and the exit-status segment reports garbage.

- [ ] **Step 1: Write the failing tests — append to `test_prompts.sh` before the final `test_summary`**

```bash
export MYPROMPTS_THEME=signalmine
export MYPROMPTS_PROMPT_STYLE=compact

# Strip SGR sequences so assertions match on visible text only.
strip_ansi() { sed 's/\x1b\[[0-9;]*m//g'; }

test_exit_status_segment() {
    test_start "prompt shows the exit code of a failing command"
    local out
    out=$("$BASH32" -c '
        source ./vaporwave_bash_prompt >/dev/null 2>&1
        (exit 42); myprompts_build_ps1
        printf %s "$PS1"' 2>&1 | strip_ansi)
    assert_contains "$out" "42" "exit code 42 in PS1"
}

test_no_exit_status_on_success() {
    test_start "prompt omits the exit code after a successful command"
    local out
    out=$("$BASH32" -c '
        source ./vaporwave_bash_prompt >/dev/null 2>&1
        true; myprompts_build_ps1
        printf %s "$PS1"' 2>&1 | strip_ansi)
    case "$out" in
        *✗*) test_fail "failure marker present after success: $out" ;;
        *) test_pass ;;
    esac
}

test_duration_segment_above_threshold() {
    test_start "prompt shows duration above MYPROMPTS_DURATION_MIN"
    local out
    out=$(MYPROMPTS_DURATION_MIN=5 "$BASH32" -c '
        source ./vaporwave_bash_prompt >/dev/null 2>&1
        myprompts_timer=$((SECONDS - 9)); myprompts_build_ps1
        printf %s "$PS1"' 2>&1 | strip_ansi)
    assert_contains "$out" "9s" "9s duration in PS1"
}

test_duration_segment_below_threshold() {
    test_start "prompt omits duration below MYPROMPTS_DURATION_MIN"
    local out
    out=$(MYPROMPTS_DURATION_MIN=5 "$BASH32" -c '
        source ./vaporwave_bash_prompt >/dev/null 2>&1
        myprompts_timer=$((SECONDS - 1)); myprompts_build_ps1
        printf %s "$PS1"' 2>&1 | strip_ansi)
    case "$out" in
        *1s*) test_fail "duration shown below threshold: $out" ;;
        *) test_pass ;;
    esac
}

test_root_marker() {
    test_start "prompt shows a root marker when EUID is 0"
    local out
    out=$("$BASH32" -c '
        source ./vaporwave_bash_prompt >/dev/null 2>&1
        myprompts_root_segment 0' 2>&1 | strip_ansi)
    assert_contains "$out" "#" "root marker"
}

test_ssh_marker() {
    test_start "prompt shows an ssh marker when SSH_CONNECTION is set"
    local out
    out=$(SSH_CONNECTION="1.2.3.4 5 6.7.8.9 22" "$BASH32" -c '
        source ./vaporwave_bash_prompt >/dev/null 2>&1
        myprompts_ssh_segment' 2>&1 | strip_ansi)
    assert_contains "$out" "ssh" "ssh marker"
}

test_debug_trap_chains() {
    test_start "DEBUG trap chains rather than clobbering a pre-existing trap"
    local out
    out=$("$BASH32" -c '
        trap "MARKER=touched" DEBUG
        source ./vaporwave_bash_prompt >/dev/null 2>&1
        trap -p DEBUG' 2>&1)
    assert_contains "$out" "MARKER=touched" "original DEBUG trap preserved"
}

test_exit_status_segment
test_no_exit_status_on_success
test_duration_segment_above_threshold
test_duration_segment_below_threshold
test_root_marker
test_ssh_marker
test_debug_trap_chains
```

- [ ] **Step 2: Run and confirm the new tests FAIL**

Run: `./test_prompts.sh`
Expected: the two original tests pass; the seven new ones fail with
`command not found: myprompts_build_ps1` and similar.

- [ ] **Step 3: Rewrite `vaporwave_bash_prompt`**

```bash
#!/usr/bin/env bash
# Signal Mine / vaporwave Bash prompt.
# Requires bash 3.2+ (the macOS system bash). No bash-4-only syntax.
#
#   MYPROMPTS_THEME         signalmine (default) | vaporwave
#   MYPROMPTS_PROMPT_STYLE  compact (default) | extended
#   MYPROMPTS_GIT           set to 0 to disable the git segment
#   MYPROMPTS_DURATION_MIN  seconds; commands at least this long show a duration (default 5)

[ -n "${BASH_VERSION:-}" ] || return 0

myprompts_self=${BASH_SOURCE[0]}
myprompts_root=$(cd "$(dirname "$myprompts_self")" && pwd)
if [ -f "$myprompts_root/lib/prompt_common.sh" ]; then
    . "$myprompts_root/lib/prompt_common.sh"
else
    return 0
fi
mp_load_theme

# Wrap raw escapes in \[ \] so readline does not count them toward line width.
mp_c() { printf '\[%s\]' "$(mp_fg "$1")"; }
mp_r() { printf '\[%s\]' "$(mp_reset)"; }
mp_b() { printf '\[%s\]' "$(mp_bold)"; }

# Colors are fixed at source time; only content varies per draw.
MP_C_ACCENT1=$(mp_c "$MP_ACCENT1")
MP_C_ACCENT2=$(mp_c "$MP_ACCENT2")
MP_C_ACCENT3=$(mp_c "$MP_ACCENT3")
MP_C_OK=$(mp_c "$MP_OK")
MP_C_INFO=$(mp_c "$MP_INFO")
MP_C_ERR=$(mp_c "$MP_ERR")
MP_C_MUTED=$(mp_c "$MP_MUTED")
MP_C_RESET=$(mp_r)
MP_C_BOLD=$(mp_b)

# Lowercase without ${var,,}, which requires bash 4. macOS ships bash 3.2.
myprompts_style="${MYPROMPTS_PROMPT_STYLE:-compact}"
myprompts_style=$(printf '%s' "$myprompts_style" | tr '[:upper:]' '[:lower:]')

myprompts_ssh_segment() {
    if [ -n "${SSH_CONNECTION:-}" ] || [ -n "${SSH_TTY:-}" ]; then
        printf '%sssh%s ' "$MP_C_INFO" "$MP_C_RESET"
    fi
}

# Takes an optional euid argument so it is testable without being root.
myprompts_root_segment() {
    local euid=${1:-$EUID}
    if [ "$euid" -eq 0 ]; then
        printf '%s%s#%s ' "$MP_C_ERR" "$MP_C_BOLD" "$MP_C_RESET"
    fi
}

# `jobs %%` is a builtin returning 0 iff a job exists. No subprocess.
# \j is passed as an argument, not in the format string: printf's handling of
# unknown backslash escapes in a format is undefined. PS1 expands it later.
myprompts_jobs_segment() {
    if jobs %% >/dev/null 2>&1; then
        printf '%s⚙%s%s ' "$MP_C_MUTED" '\j' "$MP_C_RESET"
    fi
}

myprompts_timer_start() {
    if [ -z "${myprompts_timer:-}" ]; then
        myprompts_timer=$SECONDS
    fi
}

myprompts_build_ps1() {
    local exit_code=$?     # MUST be the first statement. Do not move.

    local elapsed=0
    if [ -n "${myprompts_timer:-}" ]; then
        elapsed=$((SECONDS - myprompts_timer))
    fi
    unset myprompts_timer

    local status_seg=""
    if [ "$exit_code" -ne 0 ]; then
        status_seg="${MP_C_ERR}✗${exit_code}${MP_C_RESET} "
    fi

    local dur_seg=""
    if [ "$elapsed" -ge "${MYPROMPTS_DURATION_MIN:-5}" ]; then
        dur_seg="${MP_C_MUTED}${elapsed}s${MP_C_RESET} "
    fi

    local git_seg
    git_seg=$(mp_git_segment)
    if [ -n "$git_seg" ]; then
        git_seg="${MP_C_ACCENT3}${git_seg}${MP_C_RESET} "
    fi

    local pre="$(myprompts_root_segment)$(myprompts_ssh_segment)${status_seg}${dur_seg}$(myprompts_jobs_segment)"

    if [ "$myprompts_style" = "extended" ]; then
        PS1="${pre}${MP_C_ACCENT1}\u${MP_C_INFO}@${MP_C_ACCENT2}\h${MP_C_RESET} "
        PS1="${PS1}${MP_C_OK}\w${MP_C_RESET} ${git_seg}"
        PS1="${PS1}"$'\n'"${MP_C_ACCENT1}╰─${MP_C_INFO}▸${MP_C_RESET} "
    else
        PS1="${pre}${MP_C_ACCENT1}◤${MP_C_ACCENT2}\u${MP_C_INFO}@${MP_C_ACCENT2}\h${MP_C_ACCENT1}◢${MP_C_RESET} "
        PS1="${PS1}${MP_C_ACCENT1}【${MP_C_OK}\w${MP_C_ACCENT1}】${MP_C_RESET} "
        PS1="${PS1}${git_seg}${MP_C_INFO}${MP_C_BOLD}▸${MP_C_RESET} "
    fi
}

# Chain onto any pre-existing DEBUG trap instead of clobbering it.
myprompts_existing_debug=$(trap -p DEBUG)
if [ -n "$myprompts_existing_debug" ]; then
    myprompts_existing_debug=${myprompts_existing_debug#trap -- \'}
    myprompts_existing_debug=${myprompts_existing_debug%\' DEBUG}
    trap "${myprompts_existing_debug}; myprompts_timer_start" DEBUG
else
    trap 'myprompts_timer_start' DEBUG
fi
unset myprompts_existing_debug

case ";${PROMPT_COMMAND:-};" in
    *";myprompts_build_ps1;"*) ;;
    *) PROMPT_COMMAND="myprompts_build_ps1${PROMPT_COMMAND:+;$PROMPT_COMMAND}" ;;
esac

myprompts_build_ps1
export PS1
```

- [ ] **Step 4: Run the tests and confirm they PASS**

Run: `./test_prompts.sh`
Expected: `9 run, 9 passed, 0 failed`, exit 0.

- [ ] **Step 5: Eyeball it in a real shell**

Run: `/bin/bash --norc -i -c 'source ./vaporwave_bash_prompt; false; myprompts_build_ps1; echo "$PS1" | cat -v'`
Expected: the escape sequences include `\[` / `\]` around every color, and `✗1` appears.

Then verify column alignment is not broken by unescaped codes — start an
interactive shell, type a long line, and confirm it wraps correctly:
`/bin/bash --rcfile <(echo 'source '"$PWD"'/vaporwave_bash_prompt') -i`

- [ ] **Step 6: Commit**

```bash
git add vaporwave_bash_prompt test_prompts.sh
git commit -m "feat: rebuild bash prompt around segments

Adds exit status, command duration, git dirty state, ssh/root markers, and a
jobs indicator. Exit code is captured as the first statement of PROMPT_COMMAND;
the DEBUG trap chains onto any existing trap rather than replacing it."
```

---

## Task 7: Zsh prompt segments

**Files:**
- Modify: `vaporwave_zsh_prompt` (full rewrite)
- Create: `test_zsh_prompt.sh`

**Interfaces:**
- Consumes: `mp_load_theme`, `mp_fg`, `mp_git_segment` from Task 5.
- Produces: `prompt_myprompts_precmd()`, `prompt_myprompts_preexec()`.

Zsh gets `%(1j.…​.)` for conditional jobs and `%F{…}` for color, so it needs no
`\[ \]` wrapping and no `jobs %%` trick.

- [ ] **Step 1: Write the failing test**

```bash
#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")"
source ./test_helpers.sh

if ! command -v zsh >/dev/null 2>&1; then
    printf 'zsh not installed; skipping zsh prompt tests\n'
    exit 0
fi

test_zsh_prompt_sources() {
    test_start "vaporwave_zsh_prompt sources cleanly"
    local err
    if err=$(zsh -f -c 'source ./vaporwave_zsh_prompt' 2>&1); then
        test_pass
    else
        test_fail "sourcing failed: $err"
    fi
}

test_zsh_prompt_sets_prompt() {
    test_start "vaporwave_zsh_prompt sets a non-empty PROMPT"
    local out
    out=$(zsh -f -c 'source ./vaporwave_zsh_prompt >/dev/null 2>&1; print -rn -- "$PROMPT"')
    if [ -n "$out" ]; then test_pass; else test_fail "PROMPT was empty"; fi
}

test_zsh_exit_status() {
    test_start "zsh prompt shows the exit code of a failing command"
    local out
    out=$(zsh -f -c '
        source ./vaporwave_zsh_prompt >/dev/null 2>&1
        (exit 42); prompt_myprompts_precmd
        print -rn -- "$PROMPT"' | sed 's/\x1b\[[0-9;]*m//g')
    assert_contains "$out" "42" "exit code 42 in PROMPT"
}

test_zsh_duration() {
    test_start "zsh prompt shows duration above the threshold"
    local out
    out=$(MYPROMPTS_DURATION_MIN=5 zsh -f -c '
        source ./vaporwave_zsh_prompt >/dev/null 2>&1
        myprompts_timer=$((SECONDS - 9)); prompt_myprompts_precmd
        print -rn -- "$PROMPT"' | sed 's/\x1b\[[0-9;]*m//g')
    assert_contains "$out" "9s" "9s duration in PROMPT"
}

test_zsh_prompt_sources
test_zsh_prompt_sets_prompt
test_zsh_exit_status
test_zsh_duration
test_summary
```

- [ ] **Step 2: Run and confirm it FAILS**

Run: `chmod +x test_zsh_prompt.sh && ./test_zsh_prompt.sh`
Expected: `test_zsh_exit_status` and `test_zsh_duration` fail —
`prompt_myprompts_precmd: command not found`.

- [ ] **Step 3: Rewrite `vaporwave_zsh_prompt`**

```zsh
#!/usr/bin/env zsh
# Signal Mine / vaporwave Zsh prompt.
#
#   MYPROMPTS_THEME         signalmine (default) | vaporwave
#   MYPROMPTS_PROMPT_STYLE  compact (default) | extended
#   MYPROMPTS_GIT           set to 0 to disable the git segment
#   MYPROMPTS_DURATION_MIN  seconds; commands at least this long show a duration (default 5)

[[ -n ${ZSH_VERSION-} ]] || return 0

setopt prompt_subst
autoload -Uz add-zsh-hook

myprompts_root=${0:A:h}
if [[ -f $myprompts_root/lib/prompt_common.sh ]]; then
    source "$myprompts_root/lib/prompt_common.sh"
else
    return 0
fi
mp_load_theme

# Zsh renders colors with %F{...}; zsh already treats these as zero-width.
mp_zc() {
    local pair=$1
    if mp_truecolor; then
        printf '%%F{#%s}' "${pair#*:}"
    else
        printf '%%F{%s}' "${pair%%:*}"
    fi
}

MP_Z_ACCENT1=$(mp_zc "$MP_ACCENT1")
MP_Z_ACCENT2=$(mp_zc "$MP_ACCENT2")
MP_Z_ACCENT3=$(mp_zc "$MP_ACCENT3")
MP_Z_OK=$(mp_zc "$MP_OK")
MP_Z_INFO=$(mp_zc "$MP_INFO")
MP_Z_ERR=$(mp_zc "$MP_ERR")
MP_Z_MUTED=$(mp_zc "$MP_MUTED")
MP_Z_RESET='%f%k%b'

myprompts_style=${${MYPROMPTS_PROMPT_STYLE:-compact}:l}

prompt_myprompts_preexec() {
    myprompts_timer=$SECONDS
}

prompt_myprompts_precmd() {
    local exit_code=$?     # MUST be the first statement. Do not move.

    local elapsed=0
    if [[ -n ${myprompts_timer:-} ]]; then
        elapsed=$(( SECONDS - myprompts_timer ))
    fi
    unset myprompts_timer

    local status_seg=""
    (( exit_code != 0 )) && status_seg="${MP_Z_ERR}✗${exit_code}${MP_Z_RESET} "

    local dur_seg=""
    (( elapsed >= ${MYPROMPTS_DURATION_MIN:-5} )) && dur_seg="${MP_Z_MUTED}${elapsed}s${MP_Z_RESET} "

    local ssh_seg=""
    [[ -n ${SSH_CONNECTION:-} || -n ${SSH_TTY:-} ]] && ssh_seg="${MP_Z_INFO}ssh${MP_Z_RESET} "

    local root_seg=""
    (( EUID == 0 )) && root_seg="${MP_Z_ERR}%B#%b${MP_Z_RESET} "

    # %(1j.X.Y) renders X when at least one job exists. No subprocess.
    local jobs_seg="%(1j.${MP_Z_MUTED}⚙%j${MP_Z_RESET} .)"

    local git_seg
    git_seg=$(mp_git_segment)
    [[ -n $git_seg ]] && git_seg="${MP_Z_ACCENT3}${git_seg}${MP_Z_RESET} "

    local pre="${root_seg}${ssh_seg}${status_seg}${dur_seg}${jobs_seg}"

    if [[ $myprompts_style == extended ]]; then
        PROMPT="${pre}${MP_Z_ACCENT1}%n${MP_Z_INFO}@${MP_Z_ACCENT2}%m${MP_Z_RESET} "
        PROMPT+="${MP_Z_OK}%~${MP_Z_RESET} ${git_seg}"
        PROMPT+=$'\n'"${MP_Z_ACCENT1}╰─${MP_Z_INFO}▸${MP_Z_RESET} "
    else
        PROMPT="${pre}${MP_Z_ACCENT1}◤${MP_Z_ACCENT2}%n${MP_Z_INFO}@${MP_Z_ACCENT2}%m${MP_Z_ACCENT1}◢${MP_Z_RESET} "
        PROMPT+="${MP_Z_ACCENT1}【${MP_Z_OK}%~${MP_Z_ACCENT1}】${MP_Z_RESET} "
        PROMPT+="${git_seg}${MP_Z_INFO}%B▸%b${MP_Z_RESET} "
    fi

    RPROMPT=""
}

add-zsh-hook -d precmd  prompt_myprompts_precmd  2>/dev/null || true
add-zsh-hook -d preexec prompt_myprompts_preexec 2>/dev/null || true
add-zsh-hook precmd  prompt_myprompts_precmd
add-zsh-hook preexec prompt_myprompts_preexec

prompt_myprompts_precmd
```

- [ ] **Step 4: Run the tests and confirm they PASS**

Run: `./test_zsh_prompt.sh`
Expected: `4 run, 4 passed, 0 failed`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add vaporwave_zsh_prompt test_zsh_prompt.sh
git commit -m "feat: rebuild zsh prompt around segments

Mirrors the bash prompt. Uses %(1j.…) and %F{...} so the jobs and color
segments cost no subprocesses."
```

---

## Task 8: Delete the liquid prompt

**Files:**
- Delete: `vaporwave_liquid_prompt`
- Modify: `install.sh` — remove `PROMPT_LIQUID` (line 11), `choose_prompt_variant` (lines 1010-1072), the `download_asset "$PROMPT_LIQUID"` call in `main`, and the `choose_prompt_variant` call site in `main`
- Modify: `README.md`
- Modify: `CLAUDE.md`

**Interfaces:**
- Consumes: nothing
- Produces: `main` now hardcodes `$PROMPT_STATIC` where it previously called `choose_prompt_variant`.

The variant menu existed solely to choose between the static and liquid Bash
prompts. With liquid gone there is only one Bash prompt, so the menu is dead
code and the `PROMPT_VARIANT` environment variable is meaningless.

- [ ] **Step 1: Delete the file**

```bash
git rm vaporwave_liquid_prompt
```

- [ ] **Step 2: Remove `PROMPT_LIQUID` from `install.sh`**

Delete line 11: `PROMPT_LIQUID=vaporwave_liquid_prompt`

- [ ] **Step 3: Delete the whole `choose_prompt_variant` function**

Remove `install.sh` lines 1010-1072 (the function from `choose_prompt_variant() {`
through its closing `}`).

- [ ] **Step 4: Fix the two call sites in `main`**

Remove this line from `main`:

```bash
  download_asset "$PROMPT_LIQUID"
```

Replace these two lines:

```bash
    local bash_prompt_file=""
    choose_prompt_variant bash_prompt_file
```

with:

```bash
    local bash_prompt_file="$PROMPT_STATIC"
```

- [ ] **Step 5: Verify no references remain**

Run: `grep -rn 'PROMPT_LIQUID\|choose_prompt_variant\|liquid' install.sh README.md CLAUDE.md AGENTS.md || echo "clean"`
Expected: only `README.md` and `CLAUDE.md` hits remain at this point.

- [ ] **Step 6: Update `README.md`**

- Delete the `### Liquid Prompt` subsection under "Prompt Variants".
- Delete the `# Liquid prompt` block under "Manual Installation".
- Delete `vaporwave_liquid_prompt` from the "File Structure" tree, and add
  `themes/`, `lib/prompt_common.sh`, and `uninstall.sh`.
- Delete `PROMPT_VARIANT` from the "Environment Variables" list; add:
  - `MYPROMPTS_THEME` — `signalmine` (default), `vaporwave`, or `ember`
  - `MYPROMPTS_GIT` — set to `0` to disable the git segment
  - `MYPROMPTS_DURATION_MIN` — seconds before a command duration is shown (default `5`)
- **Delete the entire `## License` section.** Do not replace it.
- Delete "Unicode support (for liquid prompt)" from Requirements.

- [ ] **Step 7: Update `CLAUDE.md`**

Remove every `vaporwave_liquid_prompt` reference from the "Key Files" and
"Testing Prompts" sections, and drop the "Animated prompts use Unicode wave
frames" line from the Architecture section.

- [ ] **Step 8: Fix an inaccuracy in the docs about non-interactive mode**

`CLAUDE.md` says *"Non-interactive mode (`MYPROMPTS_NONINTERACTIVE=1`) skips
prompts but still installs packages automatically."* `AGENTS.md` said the same
before Task 1. This is false. `handle_package_bootstrap` (`install.sh:685-688`)
returns early when `INTERACTIVE` is 0:

```bash
  if (( ! INTERACTIVE )); then
    info "Non-interactive mode; skipping package installation."
    return
  fi
```

Correct the sentence in `CLAUDE.md` to: *"Non-interactive mode
(`MYPROMPTS_NONINTERACTIVE=1`) skips prompts and skips package installation."*

Also correct `README.md`'s "Non-Interactive Installation" section, which implies
packages are installed.

Verify with: `grep -rn 'still install' README.md CLAUDE.md AGENTS.md || echo clean`
Expected: `clean`.

- [ ] **Step 9: Verify the whole suite still passes**

Run: `./test_prompts.sh && ./test_themes.sh && ./test_zsh_prompt.sh && ./test_installer.sh`
Expected: all pass, exit 0.

- [ ] **Step 10: Commit**

```bash
git add -A
git commit -m "feat!: remove the liquid prompt

Its wave frame was derived from the current nanosecond, but a prompt only
redraws when drawn, so the frame was random per command rather than animated.
With it gone the PROMPT_VARIANT menu has one option and is removed too."
```

---

## Task 9: Back up the neofetch config on install

**Files:**
- Modify: `install.sh` `main()` — the neofetch block
- Modify: `test_installer.sh` (append one test)

**Interfaces:**
- Produces: `~/.config/neofetch/config.conf.myprompts-backup` when a
  pre-existing config was displaced. Task 10's `uninstall.sh` consumes it.

This is a prerequisite for uninstall. `install.sh` currently overwrites
`~/.config/neofetch/config.conf` unconditionally and keeps no backup, so there
is nothing for an uninstall to restore.

- [ ] **Step 1: Write the failing test — append to `test_installer.sh` before its summary**

```bash
test_neofetch_config_backed_up() {
    test_start "install backs up a pre-existing neofetch config"
    setup_test_env
    mkdir -p "$HOME/.config/neofetch"
    printf 'ORIGINAL\n' > "$HOME/.config/neofetch/config.conf"

    # setup_test_env exports MYPROMPTS_NONINTERACTIVE=1, and
    # handle_package_bootstrap returns early when INTERACTIVE is 0. So this
    # installs no packages. Do not add a skip flag; one is not needed.
    PROMPT_STYLE=compact bash ./install.sh >/dev/null 2>&1 || true

    local backup="$HOME/.config/neofetch/config.conf.myprompts-backup"
    if [ -f "$backup" ] && [ "$(cat "$backup")" = "ORIGINAL" ]; then
        test_pass
    else
        test_fail "backup missing or wrong contents"
    fi
    cleanup_test_env
}

test_neofetch_config_backed_up
```

- [ ] **Step 2: Run and confirm it FAILS**

Run: `./test_installer.sh`
Expected: the new test fails — no backup file is created.

- [ ] **Step 3: Add the backup logic to `install.sh`**

In `main()`, immediately before the line
`cp "$INSTALL_ROOT/neofetch/$neofetch_style" "$HOME/.config/neofetch/config.conf"`,
insert:

```bash
  local neofetch_target="$HOME/.config/neofetch/config.conf"
  local neofetch_backup="$neofetch_target.myprompts-backup"
  if [[ -f $neofetch_target && ! -f $neofetch_backup ]]; then
    info "Backing up existing neofetch config to ${neofetch_backup/#$HOME/~}"
    mv "$neofetch_target" "$neofetch_backup"
  fi
```

The `! -f $neofetch_backup` guard means re-running the installer never
overwrites the user's original backup with our own generated config.

- [ ] **Step 4: Run the test and confirm it PASSES**

Run: `./test_installer.sh`
Expected: all tests pass, exit 0.

- [ ] **Step 5: Verify idempotency — a second install must not clobber the backup**

```bash
T=$(mktemp -d); export HOME=$T INSTALL_ROOT=$T/ir BASE_URL="file://$PWD" MYPROMPTS_NONINTERACTIVE=1
mkdir -p "$T/.config/neofetch"; echo ORIGINAL > "$T/.config/neofetch/config.conf"
bash ./install.sh >/dev/null 2>&1; bash ./install.sh >/dev/null 2>&1
cat "$T/.config/neofetch/config.conf.myprompts-backup"
```
Expected: `ORIGINAL`, not the generated config.

- [ ] **Step 6: Commit**

```bash
git add install.sh test_installer.sh
git commit -m "fix: back up an existing neofetch config before overwriting it"
```

---

## Task 10: uninstall.sh

**Files:**
- Create: `uninstall.sh`
- Create: `test_uninstall.sh`

**Interfaces:**
- Consumes: the sentinel markers `install.sh` writes via `append_block`, and the
  neofetch backup from Task 9.
- Produces: nothing consumed by later tasks.

`append_block` emits a **blank line before each opening marker**. The removal
must span from that blank line through the closing marker inclusive, or the
byte-identical assertion can never pass.

Markers in use (from `install.sh`): `# >>> myprompts prompt >>>`,
`# >>> myprompts prompt style >>>`, `# >>> myprompts lscolors >>>`,
`# >>> myprompts ls alias >>>`, `# >>> myprompts aliases >>>`. Closing markers
substitute `<<<` for `>>>`.

- [ ] **Step 1: Write the failing test**

```bash
#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")"
source ./test_helpers.sh

test_uninstall_restores_rc_files_byte_identical() {
    test_start "uninstall restores rc files byte-identically"
    local T; T=$(mktemp -d)
    local repo="$PWD"

    printf '# my bashrc\nexport FOO=1\n' > "$T/.bashrc"
    printf '# my zshrc\nexport BAR=2\n'  > "$T/.zshrc"
    local bash_before zsh_before
    bash_before=$(cksum < "$T/.bashrc")
    zsh_before=$(cksum < "$T/.zshrc")

    ( cd "$repo" && HOME="$T" INSTALL_ROOT="$T/ir" BASE_URL="file://$repo" \
        MYPROMPTS_NONINTERACTIVE=1 PROMPT_STYLE=compact \
        bash ./install.sh >/dev/null 2>&1 ) || true

    # Sanity: install must actually have modified .bashrc, else the test is vacuous.
    if [ "$(cksum < "$T/.bashrc")" = "$bash_before" ]; then
        test_fail "install did not modify .bashrc; test would be vacuous"
        rm -rf "$T"; return
    fi

    ( cd "$repo" && HOME="$T" INSTALL_ROOT="$T/ir" MYPROMPTS_NONINTERACTIVE=1 \
        bash ./uninstall.sh >/dev/null 2>&1 ) || true

    local bash_after zsh_after
    bash_after=$(cksum < "$T/.bashrc")
    zsh_after=$(cksum < "$T/.zshrc")

    if [ "$bash_before" = "$bash_after" ] && [ "$zsh_before" = "$zsh_after" ]; then
        test_pass
    else
        test_fail "rc files differ after uninstall"
        diff <(printf '# my bashrc\nexport FOO=1\n') "$T/.bashrc" || true
    fi
    rm -rf "$T"
}

test_uninstall_removes_install_root() {
    test_start "uninstall removes INSTALL_ROOT"
    local T; T=$(mktemp -d)
    local repo="$PWD"
    ( cd "$repo" && HOME="$T" INSTALL_ROOT="$T/ir" BASE_URL="file://$repo" \
        MYPROMPTS_NONINTERACTIVE=1 PROMPT_STYLE=compact \
        bash ./install.sh >/dev/null 2>&1 ) || true
    ( cd "$repo" && HOME="$T" INSTALL_ROOT="$T/ir" MYPROMPTS_NONINTERACTIVE=1 \
        bash ./uninstall.sh >/dev/null 2>&1 ) || true
    if [ ! -d "$T/ir" ]; then test_pass; else test_fail "$T/ir still exists"; fi
    rm -rf "$T"
}

test_uninstall_restores_neofetch_backup() {
    test_start "uninstall restores the neofetch config from backup"
    local T; T=$(mktemp -d)
    local repo="$PWD"
    mkdir -p "$T/.config/neofetch"
    printf 'ORIGINAL\n' > "$T/.config/neofetch/config.conf"
    ( cd "$repo" && HOME="$T" INSTALL_ROOT="$T/ir" BASE_URL="file://$repo" \
        MYPROMPTS_NONINTERACTIVE=1 PROMPT_STYLE=compact \
        bash ./install.sh >/dev/null 2>&1 ) || true
    ( cd "$repo" && HOME="$T" INSTALL_ROOT="$T/ir" MYPROMPTS_NONINTERACTIVE=1 \
        bash ./uninstall.sh >/dev/null 2>&1 ) || true
    assert_eq "ORIGINAL" "$(cat "$T/.config/neofetch/config.conf" 2>/dev/null)" "restored config"
    rm -rf "$T"
}

test_uninstall_restores_rc_files_byte_identical
test_uninstall_removes_install_root
test_uninstall_restores_neofetch_backup
test_summary
```

- [ ] **Step 2: Run and confirm it FAILS**

Run: `chmod +x test_uninstall.sh && ./test_uninstall.sh`
Expected: FAIL — `uninstall.sh` does not exist.

- [ ] **Step 3: Create `uninstall.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail

# Reverses install.sh. Removes the sentinel-marked blocks it wrote, deletes the
# install root, and restores any neofetch config it displaced.

INSTALL_ROOT=${INSTALL_ROOT:-"$HOME/.local/share/myprompts"}

MARKERS=(
  "myprompts prompt"
  "myprompts prompt style"
  "myprompts lscolors"
  "myprompts ls alias"
  "myprompts aliases"
)

info()  { printf '\033[1;36m[info]\033[0m %s\n' "$*"; }
error() { printf '\033[1;31m[fail]\033[0m %s\n' "$*" >&2; }

# Remove the blank line + opening marker .. closing marker span, inclusive.
# append_block writes "\n# >>> NAME >>>\n<line>\n# <<< NAME <<<\n", so the
# leading blank line must go too or the file will not match byte-for-byte.
strip_block() {
  local file=$1 name=$2
  [[ -f $file ]] || return 0

  local start="# >>> $name >>>"
  local end="# <<< $name <<<"
  grep -Fq "$start" "$file" || return 0

  local tmp
  tmp=$(mktemp)
  awk -v start="$start" -v end="$end" '
    # Buffer blank lines; they are only emitted if not followed by a marker.
    /^$/ && !in_block { blanks = blanks "\n"; next }
    $0 == start { blanks = ""; in_block = 1; next }
    $0 == end   { in_block = 0; next }
    in_block { next }
    { printf "%s", blanks; blanks = ""; print }
    END { printf "%s", blanks }
  ' "$file" > "$tmp"
  mv "$tmp" "$file"
  info "Removed '$name' block from ${file/#$HOME/~}"
}

restore_neofetch() {
  local target="$HOME/.config/neofetch/config.conf"
  local backup="$target.myprompts-backup"
  if [[ -f $backup ]]; then
    mv "$backup" "$target"
    info "Restored neofetch config from backup"
  elif [[ -f $target ]]; then
    rm -f "$target"
    info "Removed the neofetch config written by myprompts"
  fi
  rm -f "$HOME/.config/neofetch/signalmine.txt"
}

main() {
  local rc
  for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
    local name
    for name in "${MARKERS[@]}"; do
      strip_block "$rc" "$name"
    done
  done

  restore_neofetch

  if [[ -d $INSTALL_ROOT ]]; then
    rm -rf "$INSTALL_ROOT"
    info "Removed ${INSTALL_ROOT/#$HOME/~}"
  fi

  printf '\nUninstalled. Restart your shell.\n'
}

main "$@"
```

- [ ] **Step 4: Run the test and confirm it PASSES**

Run: `./test_uninstall.sh`
Expected: `3 run, 3 passed, 0 failed`, exit 0.

If the byte-identical test fails on a trailing-newline difference, inspect with
`diff <(printf '# my bashrc\nexport FOO=1\n') "$T/.bashrc" | cat -A` and adjust
the awk blank-line buffering — do not weaken the assertion to `diff -B`.

- [ ] **Step 5: Commit**

```bash
chmod +x uninstall.sh
git add uninstall.sh test_uninstall.sh
git commit -m "feat: add uninstall.sh

Strips the sentinel-marked blocks install.sh wrote, restores the neofetch
config from backup, and removes the install root. Verified by asserting rc
files return byte-identical to their pre-install contents."
```

---

## Task 11: CI

**Files:**
- Create: `.github/workflows/ci.yml`
- Create: `run_tests.sh`

**Interfaces:**
- Consumes: every `test_*.sh` from prior tasks.
- Produces: `run_tests.sh`, a single entry point.

The `macos-latest` runner is what gives us Bash 3.2 coverage. That is the whole
point of the matrix — the bug this project just fixed only reproduces there.

- [ ] **Step 1: Create `run_tests.sh`**

```bash
#!/usr/bin/env bash
# Runs the whole suite. Exits nonzero if any file fails.
set -uo pipefail
cd "$(dirname "$0")"

failed=0
for t in test_themes.sh test_prompts.sh test_zsh_prompt.sh test_uninstall.sh test_installer.sh test_appstore.sh; do
    [ -f "$t" ] || continue
    printf '\n=== %s ===\n' "$t"
    if ! bash "$t"; then
        failed=1
    fi
done

if [ "$failed" -ne 0 ]; then
    printf '\nSuite FAILED\n'
    exit 1
fi
printf '\nSuite passed\n'
```

- [ ] **Step 2: Verify it runs green locally**

Run: `chmod +x run_tests.sh && ./run_tests.sh`
Expected: every section passes, final line `Suite passed`, exit 0.

- [ ] **Step 3: Create `.github/workflows/ci.yml`**

```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:

jobs:
  shellcheck:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Install shellcheck
        run: sudo apt-get update && sudo apt-get install -y shellcheck
      - name: Lint
        run: |
          shellcheck install.sh uninstall.sh run_tests.sh \
                     vaporwave_ls_setup.sh \
                     config/*.sh themes/*.sh lib/*.sh test_*.sh
          # Prompts are sourced, not executed; tell shellcheck which shell.
          shellcheck --shell=bash vaporwave_bash_prompt

  test:
    strategy:
      fail-fast: false
      matrix:
        os: [ubuntu-latest, macos-latest]
    runs-on: ${{ matrix.os }}
    steps:
      - uses: actions/checkout@v4
      - name: Record bash version
        run: /bin/bash --version | head -1
      - name: Run suite
        run: ./run_tests.sh
```

- [ ] **Step 4: Fix whatever shellcheck reports**

Run: `shellcheck install.sh uninstall.sh run_tests.sh config/*.sh themes/*.sh lib/*.sh test_*.sh`

If shellcheck is not installed locally: `brew install shellcheck`.

Expected: clean. Common findings to fix rather than suppress: SC2086 (unquoted
expansion), SC1090 (non-constant source — annotate with
`# shellcheck source=/dev/null`). Only add a `# shellcheck disable=` with a
comment explaining why the rule is wrong here.

- [ ] **Step 5: Commit**

```bash
git add run_tests.sh .github/workflows/ci.yml
git commit -m "ci: run shellcheck and the test suite on ubuntu and macos

The macos runner provides bash 3.2 coverage, which is where the prompt
sourcing bug reproduced."
```

---

## Task 12: Modularize install.sh

**Files:**
- Create: `lib/ui.sh`, `lib/os.sh`, `lib/packages.sh`, `lib/ansible.sh`, `lib/shell.sh`
- Modify: `install.sh` (becomes a bootstrapper)

**Interfaces:**
- Consumes: `run_tests.sh` from Task 11. The suite is the safety net for this
  refactor, which is why it lands last.
- Produces: no behavior change. This task must not alter a single observable
  behavior.

Function-to-module map, by current line number in `install.sh`:

| Module | Functions (current lines) |
| --- | --- |
| `lib/ui.sh` | `error` (81), `print_header` (83), `print_pkg_group` (90), `print_pkg_list` (106), `print_none_line` (117), `print_installed_items` (121), `prompt_yes_no` (977), `choose_neofetch_style` (1073), `choose_prompt_style` (1132) |
| `lib/os.sh` | `detect_os` (169), `detect_linux_package_manager` (249), `require_command` (920) |
| `lib/packages.sh` | `ensure_array` (133), `load_configuration` (140), `ensure_homebrew_in_path` (177), `ensure_homebrew` (185), `install_brew_formulae` (196), `install_brew_casks` (209), `install_appstore_apps` (222), `filter_missing_packages` (261), `install_apt_packages` (376), `install_dnf_packages` (384), `install_pacman_packages` (391), `install_paru_packages` (398), `detect_installed_packages` (589), `packages_already_configured` (669), `mark_packages_installed` (674), `handle_package_bootstrap` (679) |
| `lib/ansible.sh` | `generate_ansible_vars` (406), `ensure_ansible` (498), `run_ansible_bootstrap` (547) |
| `lib/shell.sh` | `apply_aliases_for_shell` (902), `existing_install_present` (927), `describe_install_state` (931), `handle_existing_install` (947), `append_block` (1203), `ensure_ls_alias` (1239), `write_prompt_style` (1252) |

`download_asset` (1231) is **deleted**, not moved. Fetching the tree once
subsumes it.

- [ ] **Step 1: Record the current behavior as a baseline**

```bash
./run_tests.sh 2>&1 | tee /tmp/baseline.txt
tail -1 /tmp/baseline.txt
```
Expected: `Suite passed`. If it does not pass, stop — do not refactor on top of
a red suite.

- [ ] **Step 2: Extract `lib/ui.sh`**

Move the listed functions verbatim. Prepend:

```bash
#!/usr/bin/env bash
# Terminal output and interactive prompts.
# Expects: PROMPT_FD, INTERACTIVE, and the VW_* color variables from install.sh.
```

Do not change function bodies. This is a move, not a rewrite.

- [ ] **Step 3: Run the suite after the single extraction**

Run: `./run_tests.sh`
Expected: `Suite passed`.

Extract one module at a time and run the suite after each. Do not batch.

- [ ] **Step 4: Extract `lib/os.sh`, then run the suite**
- [ ] **Step 5: Extract `lib/packages.sh`, then run the suite**
- [ ] **Step 6: Extract `lib/ansible.sh`, then run the suite**
- [ ] **Step 7: Extract `lib/shell.sh`, then run the suite**

- [ ] **Step 8: Turn `install.sh` into a bootstrapper**

Replace the function bodies with this sourcing preamble, keeping the existing
variable declarations, `/dev/tty` handling, `cleanup`, and `main` in place.

```bash
#!/usr/bin/env bash
set -euo pipefail

MYPROMPTS_REPO=${MYPROMPTS_REPO:-"https://github.com/stlalpha/myprompts"}
MYPROMPTS_REF=${MYPROMPTS_REF:-main}

# Locate our source tree. When run from a clone, lib/ sits next to us. When
# piped from curl there is no $0 to resolve, so fetch the tree and re-exec.
myprompts_bootstrap() {
  local self_dir=""
  if [[ -n ${BASH_SOURCE[0]:-} && -f ${BASH_SOURCE[0]} ]]; then
    self_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
  fi

  if [[ -n $self_dir && -d "$self_dir/lib" && -f "$self_dir/lib/ui.sh" ]]; then
    MYPROMPTS_SRC=$self_dir
    return 0
  fi

  local tmp
  tmp=$(mktemp -d)
  echo "Fetching myprompts..."
  curl -fsSL "$MYPROMPTS_REPO/archive/refs/heads/$MYPROMPTS_REF.tar.gz" \
    | tar -xz -C "$tmp" --strip-components=1
  MYPROMPTS_SRC=$tmp
  exec bash "$tmp/install.sh" "$@"
}

myprompts_bootstrap "$@"

for _mod in ui os packages ansible shell; do
  # shellcheck source=/dev/null
  . "$MYPROMPTS_SRC/lib/$_mod.sh"
done
unset _mod
```

Then, in `main`, replace every `download_asset "$X"` with a copy from the source
tree:

```bash
  install -m 644 "$MYPROMPTS_SRC/$PROMPT_STATIC" "$INSTALL_ROOT/$PROMPT_STATIC"
  install -m 644 "$MYPROMPTS_SRC/$PROMPT_ZSH"    "$INSTALL_ROOT/$PROMPT_ZSH"
  install -m 644 "$MYPROMPTS_SRC/$LS_COLORS_FILE" "$INSTALL_ROOT/$LS_COLORS_FILE"
  cp -R "$MYPROMPTS_SRC/themes" "$INSTALL_ROOT/themes"
  mkdir -p "$INSTALL_ROOT/lib"
  install -m 644 "$MYPROMPTS_SRC/lib/prompt_common.sh" "$INSTALL_ROOT/lib/prompt_common.sh"
```

Note the prompts resolve `lib/prompt_common.sh` and `themes/` relative to their
own location, so `INSTALL_ROOT` must contain both — that is why they are copied.

Likewise replace the neofetch `curl` calls with `install -m 644` from
`$MYPROMPTS_SRC/neofetch/...`, and replace `load_configuration`'s remote fetch of
`config/packages.sh` and `config/aliases.sh` with sourcing
`$MYPROMPTS_SRC/config/*.sh` directly. Delete `BASE_URL`, `PACKAGES_CONFIG_URL`,
`ALIASES_CONFIG_URL`, `CONFIG_TMP_DIR`, and `download_asset`.

- [ ] **Step 9: Update the tests that referenced `BASE_URL`**

`test_installer.sh` and `test_uninstall.sh` set `BASE_URL="file://$PWD"`. That
variable no longer exists. Replace those with nothing — running `bash
./install.sh` from the repo root now finds `lib/` adjacent to itself and uses the
local tree automatically. Delete the `export BASE_URL=` and `export
CONFIG_TMP_DIR=` lines from `setup_test_env`.

- [ ] **Step 10: Run the full suite and re-run shellcheck**

Run: `./run_tests.sh`
Expected: `Suite passed`, matching `/tmp/baseline.txt`.

Run: `shellcheck install.sh uninstall.sh run_tests.sh config/*.sh themes/*.sh lib/*.sh test_*.sh`

The five new `lib/` modules reference variables defined in `install.sh`
(`PROMPT_FD`, `INTERACTIVE`, the `VW_*` colors, the `pending_*` arrays). Bare
shellcheck reports these as SC2154 "referenced but not assigned", and the CI job
from Task 11 will fail on them. Fix by declaring the contract at the top of each
module, e.g. in `lib/ui.sh`:

```bash
# These are defined by install.sh before this module is sourced.
# shellcheck disable=SC2154  # PROMPT_FD, INTERACTIVE, VW_* come from install.sh
```

Prefer that narrow, commented disable over loosening the CI invocation.

- [ ] **Step 11: Verify the curl path still works end to end**

This exercises the tarball branch. No automated test covers it, because it
requires the network and a pushed ref. It must be done manually, **after**
pushing the branch, or the tarball URL will 404.

```bash
git push -u origin HEAD
BRANCH=$(git rev-parse --abbrev-ref HEAD)
T=$(mktemp -d)
HOME=$T MYPROMPTS_NONINTERACTIVE=1 PROMPT_STYLE=compact MYPROMPTS_REF="$BRANCH" \
  bash -c "$(cat install.sh)" 2>&1 | tail -5
ls "$T/.local/share/myprompts"
```

Expected: `Fetching myprompts...`, then the install completes, and the listing
shows `vaporwave_bash_prompt`, `vaporwave_zsh_prompt`, `themes/`, and `lib/`.

Piping the script through `bash -c "$(cat install.sh)"` is what makes
`BASH_SOURCE[0]` empty, which is precisely the condition that forces the tarball
branch. That is the same condition `curl | bash` produces.

If this step fails, the `curl | bash` contract is broken and the refactor must
not be merged.

- [ ] **Step 12: Verify a real install still produces a working prompt**

```bash
T=$(mktemp -d)
HOME=$T INSTALL_ROOT=$T/ir MYPROMPTS_NONINTERACTIVE=1 PROMPT_STYLE=compact \
  bash ./install.sh >/dev/null 2>&1
/bin/bash -c "source $T/ir/vaporwave_bash_prompt && echo OK"
```
Expected: `OK`. This proves the copied `themes/` and `lib/` resolve correctly
from `INSTALL_ROOT`.

- [ ] **Step 13: Commit**

```bash
git add -A
git commit -m "refactor: split install.sh into lib/ modules

install.sh becomes a bootstrapper: it uses an adjacent lib/ when run from a
clone, and otherwise fetches the repo tarball and re-execs. This subsumes the
per-file BASE_URL download machinery, which is deleted. No behavior change."
```

---

## Task 12b: Homebrew on Linux (fold into the Task 12 refactor)

Added post-plan. Do this while `lib/packages.sh` and `lib/os.sh` are being
carved out in Task 12, so the logic lands in the module rather than the monolith.

**Decision (from the user):** brew on Linux is **opt-in**, is **bootstrap-installed
if the user opts in and it is missing**, and when active **fully replaces** the
native package manager on Linux — apt/dnf/pacman are skipped entirely and every
package is installed through brew.

**ARCHITECTURE CORRECTION (discovered after Task 12 landed — the original 12b
spec below was wrong).** Packages are NOT installed by the `install_*` bash
functions. `install_brew_formulae`, `install_apt_packages`, etc. in
`lib/packages.sh` are **dead code** — nothing calls them. The real install path
is **Ansible**: `handle_package_bootstrap` only *filters* packages into the
`pending_*` arrays, `generate_ansible_vars` (lib/ansible.sh) writes them to a
vars file, and `ansible/playbook.yml` does the installing. The playbook gates
every Homebrew task on `when: target_os == 'macos'`. So brew-on-Linux is a
**two-layer** change, not the bash-only change the requirements below imply.

**Files (corrected):**
- Modify: `lib/os.sh` — brew PATH resolution / package-manager selection
- Modify: `lib/packages.sh` — `ensure_homebrew_in_path`, `handle_package_bootstrap`
- Modify: `lib/ansible.sh` — `generate_ansible_vars` must emit a "use brew" signal
- Modify: `ansible/playbook.yml` — Homebrew formulae task must run on Linux when
  that signal is set (the design decision: introduce a `package_manager` value
  like `brew`, and gate the formulae task on
  `package_manager == 'brew' or target_os == 'macos'`; casks + App Store stay
  `target_os == 'macos'` only)
- Modify: `config/packages.sh` — shared brew formulae list usable on both OSes
- Test: extend `test_installer.sh`

**Behavioral requirements:**

1. **Opt-in.** A Linux user selects brew via a prompt (interactive) or
   `MYPROMPTS_LINUX_BREW=1` (non-interactive). Absent the opt-in, Linux behaves
   exactly as today (native package manager). Default is native.

2. **Bootstrap if missing.** When the user opts in and `brew` is not found, run
   the same official installer the macOS path already uses (`ensure_homebrew`) —
   it installs to `/home/linuxbrew/.linuxbrew` on Linux. Do **not** run it as
   root. Mirror the macOS consent/prompt flow.

3. **PATH resolution.** `ensure_homebrew_in_path` (in `lib/packages.sh`, not
   `lib/os.sh`) currently checks only `/opt/homebrew/bin/brew` and
   `/usr/local/bin/brew`. Add `/home/linuxbrew/.linuxbrew/bin/brew` and
   `"$HOME/.linuxbrew/bin/brew"`, `eval "$(<path> shellenv)"` for whichever exists.

4. **Replace native — via the pending arrays + Ansible, not a direct call.**
   When brew is active on Linux, `handle_package_bootstrap` must filter the
   shared brew formulae list into `pending_macos_brew_formulae` (the existing
   brew pending array the playbook already reads), set the manager signal to
   `brew`, and NOT populate the apt/dnf/pacman pending arrays. Then
   `generate_ansible_vars` passes `package_manager=brew`, and the playbook's
   formulae task fires on Linux. Do NOT wire `install_brew_formulae` directly —
   it is dead code; either delete it separately or leave it, but do not build on
   it.

5. **Shared list.** The brew formulae are the same `macos_brew_formulae` list.
   Do not install the *native* lists via brew — names differ (`netcat` vs
   `gnu-netcat`).

**Verification:**
- On a Linux box with `MYPROMPTS_LINUX_BREW=1` and brew absent: bootstraps brew,
  adds it to PATH, generates ansible vars with `package_manager=brew` and the
  brew formulae; the apt/dnf/pacman pending arrays are empty. Assert the vars
  file, and (if Ansible is stubbable) that the native tasks are skipped.
- With the opt-in unset: the native pending arrays are populated as today, no
  brew — a regression guard proving the default is unchanged.
- macOS behavior completely unaffected (the playbook's macOS gates unchanged;
  only the formulae task's `when` broadens to include `package_manager == 'brew'`).

**Out of scope for 12b:** migrating native package lists to brew names; brew
casks on Linux (Linuxbrew has no cask support); deleting the dead `install_*`
functions (separate cleanup).

---

## Out of Scope

- Ahead/behind git indicators — needs a second git call and goes stale without a fetch.
- A truly animated prompt via background redraw — fights readline.
- `neofetch` → `fastfetch` migration — recommended, but a separate change.
- Migrating the native Linux package lists to brew formula names — out of scope
  for Task 12b, which only adds the brew-replaces-native path, not a list rewrite.
- Renaming `vaporwave_*_prompt` files — would break `source` lines already in users' rc files.
