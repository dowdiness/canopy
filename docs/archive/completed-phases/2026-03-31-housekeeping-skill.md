# Housekeeping Skill Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a `/housekeeping` skill that dispatches mechanical repo maintenance to a single Haiku subagent with phased execution, absorbing the existing `/health-check` skill.

**Architecture:** One Haiku subagent executes 4 sequential phases (git → moon tools → git diff → build+test). Default mode is read-only (report). Fix mode allows `moon fmt`, `moon info`, `moon test --update`. Structured JSON output parsed by Opus for unified report.

**Tech Stack:** Claude Code skills, Agent tool with `model: haiku`, Bash/Grep/Glob tools

---

## File Structure

| Action | Path | Responsibility |
|--------|------|----------------|
| Create | `.claude/skills/housekeeping/SKILL.md` | Skill definition, subagent prompt templates, output schema |
| Delete | `.claude/skills/health-check/SKILL.md` | Superseded by housekeeping |
| Delete | `.claude/skills/health-check/` | Remove directory |

---

## Design Summary

### Execution Phases (single Haiku agent, sequential)

```
Phase 1 — git snapshot (read-only)
  git status, git log origin/main..HEAD, git branch --merged,
  git worktree list, gh pr list, git submodule status,
  git ls-files --others --exclude-standard (flag >1MB)

Phase 2 — moon tools (parallel within phase)
  moon fmt & moon check & moon info
  (these write to different outputs: .mbt files, _build/, .mbti files)

Phase 3 — git diff (captures phase 2 changes)
  git diff --stat (what did fmt/info change?)
  git diff *.mbti (interface changes specifically)

Phase 4 — build + test (parallel within phase)
  moon test (main + submodules) & moon build --target js
  Optional: cd examples/web && npm run build (if node_modules exists)
```

### Modes

- **Report mode** (default): phases 1-4, then revert phase 2 changes (`git checkout -- .`)
- **Fix mode** (`/housekeeping fix`): phases 1-4, keep phase 2 changes, report what was fixed
- **Category mode** (`/housekeeping [category]`): run only the relevant phases for that category

### Categories → Phase mapping

| Category | Phases used |
|----------|-------------|
| `git` | Phase 1 only |
| `lint` | Phase 2 (fmt+check) → Phase 3 |
| `sync` | Phase 1 (submodule status) + Phase 2 (moon info) → Phase 3 (mbti diff) |
| `build` | Phase 4 (build only) |
| `test` | Phase 4 (test only) |

### JSON Output Schema

```json
{
  "phases": {
    "git": {
      "status": "pass|warn|fail",
      "items": [
        {"severity": "error|warning|info", "file": "path|null", "message": "desc", "fixable": false}
      ]
    },
    "lint": { "status": "...", "items": [...] },
    "sync": { "status": "...", "items": [...] },
    "build": { "status": "...", "items": [...] },
    "test": { "status": "...", "items": [...] }
  },
  "truncated": false,
  "tool_calls_used": 20
}
```

### Unified Report Format

```
## Housekeeping Report

git:   PASS  (main, 1 ahead of origin, 0 stale branches)
lint:  WARN  (2 files needed formatting)
sync:  PASS  (all submodules clean, on expected branches)
build: PASS  (js: ok)
test:  PASS  (342 passed, 0 failed)

### Details
[per-category expandable sections]
```

---

## Task 1: Create the housekeeping skill file

**Files:**
- Create: `.claude/skills/housekeeping/SKILL.md`

- [ ] **Step 1: Create the skill directory and file**

Write `.claude/skills/housekeeping/SKILL.md` with the complete skill definition. The file contains:

1. Skill header (name, description, usage)
2. Mode definitions (report/fix/category)
3. Subagent prompt template with:
   - 4-phase execution sequence
   - Per-phase commands (dynamic submodule/target discovery)
   - JSON output schema
   - Tool-call budget (25 max)
   - Report-mode revert instructions
   - Fix-mode keep instructions
4. Output format (unified report template)
5. Guardrails (read-only default, fix whitelist, preflight checks)

The subagent prompt must instruct Haiku to:
- Discover submodules dynamically from `.gitmodules`
- Discover test targets by checking for `moon.mod.json` in submodule roots
- Run `moon update` before phase 2 to avoid stale `.mooncakes/`
- In report mode: revert all file changes after phase 3 (`git checkout -- .`)
- In fix mode: keep changes, list what was fixed
- Output structured JSON, not prose
- If tool-call limit approached, report what was gathered and stop

```markdown
# Housekeeping

Repo maintenance skill. Dispatches a single Haiku subagent that runs 4 sequential
phases of mechanical checks. Absorbs and replaces the old `/health-check` skill.

## Usage

- `/housekeeping` — full scan, report only (default)
- `/housekeeping fix` — full scan + auto-fix safe items (fmt, info, snapshots)
- `/housekeeping git` — git state only
- `/housekeeping lint` — formatting + lint only
- `/housekeeping sync` — submodule state + mbti drift
- `/housekeeping build` — build smoke test only
- `/housekeeping test` — test suite only

## When to Use

- **Start of session** — see repo state before working
- **Before committing** — catch formatting/lint issues
- **After pulling submodule changes** — verify nothing broke
- **Before creating a PR** — full check
- **After a long session** — `/housekeeping fix` to clean up drift

## When NOT to Use

- Mid-implementation (use incremental `moon check` per CLAUDE.md)
- For debugging (use `/systematic-debugging`)
- For code review (use `/parallel-review`)

## Execution

Dispatch ONE Haiku subagent using the Agent tool with `model: haiku`.
Compose the prompt based on the requested mode and category.

### Preflight (Opus, before dispatching)

Verify `moon` is on PATH: `which moon`. If not, report error and stop.

### Prompt Template

The subagent receives this prompt, with `{MODE}` and `{CATEGORIES}` substituted:

~~~
You are a housekeeping agent. Run mechanical repo checks and output structured JSON.

MODE: {MODE}  (report = read-only, fix = keep safe changes)
CATEGORIES: {CATEGORIES}  (all, git, lint, sync, build, test)

Working directory: {CWD}

RULES:
- Maximum 25 tool calls. If you approach the limit, report what you have and stop.
- Output ONLY a JSON object matching the schema below. No prose before or after.
- Discover submodules dynamically from .gitmodules, not hardcoded.
- Discover test targets by checking for moon.mod.json in submodule dirs.

PHASE 1 — git snapshot (if categories include: git, sync, all)
Run these commands and collect results:
  git status --short
  git log --oneline origin/main..HEAD  (commits ahead)
  git log --oneline HEAD..origin/main  (commits behind)
  git branch --merged main | grep -v main  (stale branches)
  git worktree list  (active worktrees)
  gh pr list --state open --json number,title,headRefName,statusCheckRollup  (open PRs)
  git submodule status  (dirty/detached/behind)
  git ls-files --others --exclude-standard  (untracked files, flag >1MB)

PHASE 2 — moon tools (if categories include: lint, sync, all)
Run in parallel (separate bash commands or backgrounded):
  moon update  (preflight — ensure .mooncakes/ is fresh)
  moon fmt
  moon check 2>&1
  moon info

PHASE 3 — git diff (if phase 2 ran)
  git diff --stat  (what did phase 2 change?)
  git diff -- '*.mbti'  (interface changes)

If MODE is "report": revert changes with `git checkout -- .`
If MODE is "fix": keep changes, report them as fixed.

PHASE 4 — build + test (if categories include: build, test, all)
For build:
  moon build --target js 2>&1
  If node_modules exists in examples/web: cd examples/web && npm run build 2>&1

For test (discover targets dynamically):
  moon test 2>&1  (main module)
  For each submodule with moon.mod.json: cd {submodule} && moon test 2>&1

OUTPUT SCHEMA:
{
  "phases": {
    "git": {
      "status": "pass|warn|fail",
      "items": [
        {"severity": "error|warning|info", "file": null, "message": "description", "fixable": false}
      ]
    },
    "lint": {"status": "...", "items": [...]},
    "sync": {"status": "...", "items": [...]},
    "build": {"status": "...", "items": [...]},
    "test": {"status": "...", "items": [...]}
  },
  "truncated": false,
  "tool_calls_used": N
}

STATUS RULES:
- "pass" = no issues
- "warn" = non-blocking issues found
- "fail" = blocking issues (test failures, build errors, lint errors)

SEVERITY RULES:
- "error" = must fix (test failure, build error, lint error)
- "warning" = should fix (dirty submodule, formatting needed, stale branch)
- "info" = informational (commits ahead/behind, PR status, untracked files)

Set "fixable": true only for items that /housekeeping fix can auto-resolve
(formatting, mbti regeneration, snapshot updates).
~~~

### Report Rendering (Opus, after subagent returns)

Parse the JSON output. Render a unified report:

```
## Housekeeping Report

git:   {STATUS}  ({summary})
lint:  {STATUS}  ({summary})
sync:  {STATUS}  ({summary})
build: {STATUS}  ({summary})
test:  {STATUS}  ({summary})
```

If any category has warnings or errors, show a Details section with the items.
If `truncated` is true, note that the scan was incomplete.

If MODE was "fix", list what was auto-fixed.
If MODE was "report" and fixable items exist, suggest: "Run `/housekeeping fix` to auto-fix N items."

## Fix Mode Whitelist

ONLY these operations are allowed in fix mode:
- `moon fmt` (reversible, deterministic)
- `moon info` to regenerate .mbti files (deterministic)
- `moon test --update` for snapshot updates (reviewable via git diff)

Everything else is report-only. Submodule commits, file moves, edits require user confirmation.

## Guardrails

- Default is READ-ONLY. The subagent must not modify files in report mode (revert after phase 3).
- Never `git pull`, `git push`, `git stash`, or `git checkout` branches.
- Never modify source code logic.
- Never delete files or branches.
- 25 tool-call hard limit per invocation.
~~~

- [ ] **Step 2: Verify the skill file is valid**

Run: `cat .claude/skills/housekeeping/SKILL.md | head -5`
Expected: Shows the skill header.

- [ ] **Step 3: Commit**

```bash
git add .claude/skills/housekeeping/SKILL.md
git commit -m "feat: add /housekeeping skill — phased repo maintenance with Haiku subagent"
```

---

## Task 2: Delete the health-check skill

**Files:**
- Delete: `.claude/skills/health-check/SKILL.md`
- Delete: `.claude/skills/health-check/` (directory)

- [ ] **Step 1: Remove the health-check skill**

```bash
git rm .claude/skills/health-check/SKILL.md
rmdir .claude/skills/health-check/  # or git will remove it
```

- [ ] **Step 2: Verify no remaining references**

```bash
grep -r "health-check" .claude/
```

Expected: No results (the skill registration in settings is automatic based on directory presence).

- [ ] **Step 3: Commit**

```bash
git add -A .claude/skills/health-check/
git commit -m "chore: remove /health-check skill — absorbed into /housekeeping"
```

---

## Task 3: Smoke test the skill

- [ ] **Step 1: Run `/housekeeping` in report mode**

Invoke the skill and verify:
- Haiku subagent is dispatched with correct prompt
- All 4 phases execute
- JSON output is valid and parseable
- Unified report renders correctly
- No files are modified (report mode reverts changes)

Run: `git status` after the skill completes
Expected: Clean working tree (no modifications from the housekeeping run)

- [ ] **Step 2: Run `/housekeeping fix` to test fix mode**

Invoke with fix mode and verify:
- Phase 2 changes are kept (if any formatting/info changes exist)
- Report lists what was fixed
- Only whitelisted operations were performed

- [ ] **Step 3: Run `/housekeeping git` to test category mode**

Invoke with single category and verify:
- Only Phase 1 executes
- Other phases are skipped
- Output only contains git category

- [ ] **Step 4: Iterate on prompt if needed**

If the Haiku subagent:
- Produces prose instead of JSON: tighten the "Output ONLY JSON" instruction
- Exceeds tool-call limit: reduce phase scope or split phases
- Misses submodules: check dynamic discovery logic
- Fails to revert in report mode: add explicit revert verification step

Fix the skill file and re-test. Commit when stable.

```bash
git add .claude/skills/housekeeping/SKILL.md
git commit -m "fix: refine /housekeeping subagent prompt after smoke testing"
```
