# RLE Phase 0: Replace Internal RLE Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Delete the unused internal RLE package (~2,600 lines) and add `dowdiness/rle` as a git submodule dependency, unblocking Phases 1-3.

**Architecture:** The internal `event-graph-walker/internal/rle/` package has zero consumers — no package in event-graph-walker imports it. We delete it entirely, add the external `dowdiness/rle` library as a git submodule (consistent with 5 existing submodules), and wire it as a path dependency in `event-graph-walker/moon.mod.json`.

**Tech Stack:** MoonBit, git submodules

**Spec:** `docs/plans/2026-03-15-rle-library-integration.md` (Phase 0 section)

**Important:** `event-graph-walker/` is itself a git submodule. Changes inside it (moon.mod.json edit, internal/rle deletion) must be committed inside the submodule first, then the parent repo stages the updated submodule pointer.

---

### Task 1: Add `dowdiness/rle` git submodule

**Files:**
- Modify: `.gitmodules`
- Create: `rle/` (submodule checkout)

- [ ] **Step 1: Add the submodule**

```bash
cd /home/antisatori/ghq/github.com/dowdiness/canopy
git submodule add https://github.com/dowdiness/rle.git rle
```

- [ ] **Step 2: Verify submodule was added correctly**

```bash
git submodule status rle
```

Expected: Shows a commit hash followed by `rle` path.

```bash
cat .gitmodules
```

Expected: New entry for `rle` with URL `https://github.com/dowdiness/rle.git`.

- [ ] **Step 3: Verify the external RLE library builds**

```bash
cd rle && moon test
```

Expected: All tests pass.

---

### Task 2: Wire path dependency in event-graph-walker

**Files:**
- Modify: `event-graph-walker/moon.mod.json`

- [ ] **Step 1: Add `dowdiness/rle` path dependency**

Edit `event-graph-walker/moon.mod.json` to add the dependency:

```json
{
  "name": "dowdiness/event-graph-walker",
  "version": "0.1.0",
  "deps": {
    "moonbitlang/quickcheck": "0.9.9",
    "dowdiness/rle": { "path": "../rle" }
  },
  "readme": "README.md",
  "repository": "https://github.com/dowdiness/event-graph-walker",
  "license": "Apache-2.0",
  "keywords": ["crdt", "collaborative-editing", "eg-walker", "fugue"],
  "description": "Implementation of the eg-walker CRDT algorithm with FugueMax sequence CRDT"
}
```

- [ ] **Step 2: Run `moon update` in event-graph-walker to refresh lockfile**

```bash
cd /home/antisatori/ghq/github.com/dowdiness/canopy/event-graph-walker && moon update
```

Note: If `moon update` creates or modifies `moon.lock.json`, it must be committed inside the submodule in Task 5.

- [ ] **Step 3: Verify event-graph-walker still builds with the new dependency**

```bash
cd /home/antisatori/ghq/github.com/dowdiness/canopy/event-graph-walker && moon check
```

Expected: Clean check with no errors.

---

### Task 3: Delete internal RLE package

**Files:**
- Delete: `event-graph-walker/internal/rle/` (entire directory, ~2,600 lines)

- [ ] **Step 1: Delete the internal RLE directory**

```bash
rm -rf /home/antisatori/ghq/github.com/dowdiness/canopy/event-graph-walker/internal/rle
```

Note: `internal/` contains 6 other packages (branch, causal_graph, core, document, fugue, oplog) — do NOT delete it.

- [ ] **Step 2: Verify event-graph-walker still builds and all tests pass**

```bash
cd /home/antisatori/ghq/github.com/dowdiness/canopy/event-graph-walker && moon check && moon test
```

Expected: All checks pass, all tests pass (the deleted code had zero importers).

- [ ] **Step 3: Run `moon update` in root crdt module, then verify it builds and tests pass**

```bash
cd /home/antisatori/ghq/github.com/dowdiness/canopy && moon update && moon check && moon test
```

Expected: All checks pass.

---

### Task 4: Update module dependency diagram

**Files:**
- Modify: `docs/architecture/modules.md`

- [ ] **Step 1: Add `rle` to the submodules table**

Add a new row to the "Git Submodules" table in `docs/architecture/modules.md`:

| `rle/` | [dowdiness/rle](https://github.com/dowdiness/rle) | `dowdiness/rle` |

- [ ] **Step 2: Update the dependency diagram**

Change the `event-graph-walker` line from:

```
event-graph-walker (independent, quickcheck only)
```

to:

```
rle (independent, quickcheck only)
   ↑
event-graph-walker (depends on rle + quickcheck)
```

- [ ] **Step 3: Verify the diagram is accurate**

Read `event-graph-walker/moon.mod.json` and confirm it lists `dowdiness/rle` as a dependency.

---

### Task 5: Commit (two-stage — submodule first, then parent)

Since `event-graph-walker/` is a git submodule, changes inside it must be committed there first, then the parent stages the updated submodule pointer.

- [ ] **Step 1: Commit inside event-graph-walker submodule**

```bash
cd /home/antisatori/ghq/github.com/dowdiness/canopy/event-graph-walker
git add moon.mod.json
git rm -r internal/rle
git status
```

If `moon update` created/modified `moon.lock.json`, stage that too:
```bash
git add moon.lock.json  # only if it exists/changed
```

```bash
git commit -m "chore: delete internal RLE, add dowdiness/rle dependency (Phase 0)

Delete internal/rle/ (~2,600 lines, zero importers) and add
dowdiness/rle as a path dependency for Phases 1-3.

The external library uses a tighter extend version-bump heuristic
(compares last-run span) vs the internal library's conservative approach."
```

- [ ] **Step 2: Stage and commit in parent repo**

```bash
cd /home/antisatori/ghq/github.com/dowdiness/canopy
git add .gitmodules rle event-graph-walker docs/architecture/modules.md
```

Verify staged changes:
```bash
git diff --cached --stat
```

Expected:
- `.gitmodules` modified (new rle entry)
- `rle` added (new submodule)
- `event-graph-walker` updated (submodule pointer)
- `docs/architecture/modules.md` modified

```bash
git commit -m "chore: add dowdiness/rle submodule, update event-graph-walker (Phase 0)

Add dowdiness/rle as a git submodule and update event-graph-walker
submodule pointer (internal RLE deleted, external rle dependency added).

This unblocks RLE Phases 1-3 (OpRun, VisibleRun, LvRange compression)."
```

- [ ] **Step 3: Verify final state**

```bash
git status
git submodule status
```

Expected: Clean working tree, all submodules showing commit hashes.
