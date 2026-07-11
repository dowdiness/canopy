# Structure-mode PM block editor — completion state

**Date:** 2026-07-11
**Status:** Accepted
**Closes:** `docs/decisions-needed.md` "structure-mode: PM block editor completion state" (added 2026-03-31)
**Related:** [Architecture redesign proposal](../plans/2026-06-11-architecture-redesign-proposal.md) note (4) — S6 prerequisite

## Why this record exists

S6 of the architecture redesign proposal ("Continuous app-layer
modularization") was gated on resolving this item first. The 2026-03-31
entry judged the evidence insufficient ("bridge_ffi.mbt and model.mbt
exist... but insufficient evidence to judge done vs in-progress"). Four
months of subsequent work (issue #428 fix, PR #433, #509, #670, and two
Playwright regression suites) were never folded back into that judgment.

## Decision

**Structure mode is a complete, actively maintained feature — not a stub.**
The 2026-03-31 "unclear" judgment is stale. Evidence, as of this commit:

- `examples/ideal/main/model.mbt`: `EditorMode::Structure` is a first-class
  mode alongside `Text`, carried on `Model.mode`.
- `examples/ideal/main/msg.mbt`: dedicated `Msg` variants
  (`StructureNodeSelected`, `StructureStructuralEdit`) route Web Component
  events back into the TEA loop.
- `examples/ideal/main/update_handlers.mbt`: `handle_structure_mode` (lines
  366-419) is one of seven already-split per-feature update handlers.
- `examples/ideal/main/bridge_ffi.mbt`: `js_set_editor_mode` /
  `js_set_editor_selected_node` wire mode switches and node selection to the
  mounted `<canopy-editor>` Web Component; comment at bridge_ffi.mbt:191
  ("Structure mode focuses the ProseMirror view after selecting the node")
  documents intended behavior, matched by test behavior below.
- **Lazy-loading, verified:** `examples/ideal/web/src/canopy-editor.ts:154`
  dynamically imports the ProseMirror runtime — `import('./structure-runtime')`
  — so Text-mode users never pay the ProseMirror bundle cost. This directly
  satisfies the TODO.md §9 checkbox's "verify lazy-loading works" clause.
- **Tested, verified:** two Playwright E2E suites exist and exercise real
  behavior, not smoke checks:
  - `examples/ideal/web/e2e/structure-mode-switch.spec.ts` — Text→Structure
    mount, no uncaught errors, node click updates the inspector, plus a
    unit-level test of the `buildStructureDoc` fallback path (regression
    for #428, shipped in PR #433).
  - `examples/ideal/web/e2e/structural-editing.spec.ts` (13.3K) — structural
    editing overlay across multiple node types (int, var, lambda, app, let,
    module), including node-type-specific selection behavior (compound
    nodes → `NodeSelection`, leaf nodes → inline CM6 editors).
- **Actively maintained**, not abandoned: `bridge_ffi.mbt` git history shows
  structure-mode-relevant commits through PR #670 (2026, most recent of the
  file's last 5 commits), well past the 2026-03-31 decision date.

The remaining open TODO.md §9 checkbox ("Structure mode — test and polish
PM block editor, verify lazy-loading works") should be checked off, or
narrowed to whatever specific polish item remains — not treated as a
blanket completion-state unknown.

## Consequences

- S6 ("Continuous app-layer modularization") is unblocked on this
  prerequisite: structure-mode code (`handle_structure_mode`,
  `bridge_ffi.mbt`'s structure-mode externs, `model.mbt`'s `EditorMode`) is
  stable, tested application logic and can be split into feature modules
  like any other mature area of `examples/ideal/main/` — no special
  in-progress handling needed.
- `docs/decisions-needed.md`'s structure-mode entry is removed as resolved.

## Deferred

- Narrowing or closing the TODO.md §9 checkbox itself (cosmetic; not a
  blocker for S6 and not actioned by this record).
