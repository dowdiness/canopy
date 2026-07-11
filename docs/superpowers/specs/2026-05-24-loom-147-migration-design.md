# Loom #147 — Cross-repo migration design

**Date:** 2026-05-24
**Issue:** [dowdiness/loom#147](https://github.com/dowdiness/loom/issues/147)
**Status:** Design approved; awaiting plan
**Direction chosen:** Architectural alignment — text_change + moji move into the loom monorepo
**Codex review:** PASS with 3 revisions (incorporated below)

## Problem

`dowdiness/loom` cannot be built in isolation today. Three path-deps escape the loom repo into canopy:

- `loom/loom/moon.mod.json:9` — `"dowdiness/text_change": { "path": "../../lib/text-change" }` (resolves into canopy/lib/text-change)
- canopy/`lib/text-change/moon.mod.json` — `"dowdiness/moji": { "path": "../moji" }` (canopy/lib/moji)
- `loom/examples/lambda/moon.mod.json:10` — `"dowdiness/event-graph-walker": { "path": "../../../event-graph-walker" }` (canopy submodule; `json` and `markdown` do NOT depend on EGW per Codex Finding 1)

PR #145 ships loom CI for `seam` + `incr` + `egglog` + `pretty` only. Loom itself and the example/egraph modules have zero CI coverage on the loom repo.

## Direction

Move `text_change` and `moji` into the loom monorepo as new top-level modules, peer to `loom/`, `seam/`, `incr/`, `egglog/`, `pretty/`. This matches loom's existing "monorepo of independent modules" pattern (loom/CLAUDE.md "Package Map") and fixes the dep direction: loom now owns the libs whose API shape it constrains.

EGW is **deferred** — it is already its own repo (`dowdiness/event-graph-walker`); how loom/examples/lambda + egraph reference it is a separate follow-up.

## Non-goals

- EGW reference for `loom/examples/lambda` + `egraph` — deferred to a follow-up issue.
- Publishing text_change/moji to mooncakes — not needed; path-deps stay path-deps, the path now resolves inside loom.
- Issue #148 (`impl ... with fn` syntax migration) — independent.
- Re-adding the moved modules to canopy's `moon.work` — explicit non-goal; submodules stay out of canopy workspace (existing rule).

## Three-PR sequence

PRs must merge in this order. Canopy is broken until PR C lands.

### PR A — `dowdiness/loom`

**Files added:**
- `loom/text-change/` (full module tree, via `git subtree split` from canopy — see History method)
- `loom/moji/` (same)

**Files edited:**
- `loom/loom/moon.mod.json` — text_change path `../../lib/text-change` → `../text-change`. Verify the moji transitive dep auto-resolves through text_change to `../moji`.
- `loom/.github/workflows/ci.yml` — expand the CI matrix from 4 → 9 modules: `loom`, `text-change`, `moji`, `seam`, `incr`, `egglog`, `pretty`, `examples/json`, `examples/markdown`. Codex Finding 1: `examples/lambda` and `egraph` stay deferred because only lambda hits EGW; json + markdown only consume in-repo loom/seam/pretty.
- `loom/CLAUDE.md` Package Map — add `dowdiness/text_change` and `dowdiness/moji` rows.
- `loom/README.md` + `loom/ROADMAP.md` + `loom/docs/README.md` — mention the two new modules in module lists.
- Run `bash check-docs.sh` from loom root before push.

**Verification:** standalone-buildable on a fresh checkout — `git clone https://github.com/dowdiness/loom && cd loom && (cd text-change && moon check && moon test) && (cd moji && moon check && moon test) && (cd loom && moon check && moon test)` all succeed without canopy on the filesystem.

### PR B — `dowdiness/valtio`

One-line edit: `valtio/moon.mod.json:5` — text_change path `../lib/text-change` → `../loom/text-change`.

Verify valtio's CI (if any) passes. After merge, valtio becomes more-standalone-buildable in the same way (still requires canopy parent for path resolution, but the path now matches post-migration layout).

### PR C — `dowdiness/canopy`

**Files deleted:**
- `lib/text-change/` (entire directory)
- `lib/moji/` (entire directory)

**Files edited:**

*Path-dep rewrites (2 files — Codex Finding 3 confirmed only these directly consume text_change/moji):*
- `moon.mod.json:12` (root) — text_change + moji paths → `loom/text-change`, `loom/moji`
- `examples/ideal/moon.mod.json:21` — text_change path → `loom/text-change`

*Workspace + metadata edits:*
- `moon.work` — remove `./lib/text-change` from members; do NOT re-add `./loom/text-change` (matches existing submodules-stay-out-of-workspace rule per `moonbit_workspace_behavior` memory)
- `.gitmodules` — no changes (loom and valtio submodules already declared)

**Submodule pointer bumps in the same commit:**
- `loom` → merged-PR-A SHA
- `valtio` → merged-PR-B SHA

**Explicit non-rewrites (Codex Finding 3):**
- `examples/block-editor/moon.mod.json` — does NOT directly depend on text_change/moji; only canopy + EGW. Block-editor is a transitive integration check via canopy root, no direct rewrite needed.

**Verification:** full canopy CI fan-out per `.github/workflows/ci.yml` green locally before push. Includes the loom submodule fan-out steps that now exercise the relocated modules.

## History method (Codex Finding 2 — accepted)

Use `git subtree split` for **both** modules (text_change + moji). Rationale: loom's own prior monorepo migration used subtree (`loom/docs/archive/completed-phases/2026-03-02-rabbita-style-monorepo.md:101,103`); moji carries UAX #29 conformance data + generators where blame archeology matters.

Procedure for each module (in a scratch directory):

```
# 1. In a clone of canopy, split the subtree
cd /tmp/canopy-clone
git subtree split --prefix=lib/text-change -b text-change-history

# 2. In a clone of loom, add the split as a subtree
cd /tmp/loom-clone
git remote add canopy-tmp /tmp/canopy-clone
git fetch canopy-tmp
git subtree add --prefix=text-change canopy-tmp text-change-history

# 3. Same for moji

# 4. Cleanup the scratch remote after both subtree adds
git remote remove canopy-tmp
```

History inside loom thus preserves the canopy-side blame chain for these modules.

## Open question I'm explicitly punting on

Codex did not flag `moon`'s resolver behavior when both old and new paths transiently exist in the working tree mid-commit (decision (c)). Treating as safe based on Codex non-flag; if a PR C trial run surfaces resolver confusion, fall back to staged commits (delete `lib/*` first commit, bump submodules + rewrite paths second commit) on the same PR branch.

## Follow-ups (new issues to file)

- **loom#FOLLOWUP-EGW**: EGW reference for `loom/examples/lambda` + `egraph`. Two viable directions (submodule loom→EGW vs registry republish of EGW 0.3.0+). Republishing EGW currently has only 0.1.0 on mooncakes.
- **canopy: workspace re-membership review** — after a few weeks, if developers actively edit text_change/moji from canopy's tree, reconsider adding `./loom/text-change` and `./loom/moji` to canopy's `moon.work`.

## Acceptance criteria

1. PR A merges with all 9 CI matrix jobs green on a fresh-checkout loom.
2. PR B merges with valtio's path-dep pointing into loom.
3. PR C merges with canopy's full CI fan-out green.
4. After all three: `cd loom && rm -rf ../canopy/lib/text-change ../canopy/lib/moji 2>/dev/null; (cd loom && moon check)` succeeds — i.e., loom does not depend on canopy presence.
5. Loom #147 is closed with a back-link to this spec.

## Citations

- Codex review thread: 019e592f-7f09-7953-90d5-6bb3368c2f2c (2026-05-24)
- Verified file/line refs from Codex: `loom/examples/json/moon.mod.json:6`, `loom/examples/markdown/moon.mod.json:6`, `loom/examples/lambda/moon.mod.json:10`, `examples/block-editor/moon.mod.json:5,9`, `examples/ideal/moon.mod.json:21`, `valtio/moon.mod.json:5`, `moon.mod.json:12`, `loom/docs/archive/completed-phases/2026-03-02-rabbita-style-monorepo.md:101,103`
- Memory citations: `moonbit_workspace_behavior.md` (workspace rule), `project_loom_framework_improvements.md` (module list).
