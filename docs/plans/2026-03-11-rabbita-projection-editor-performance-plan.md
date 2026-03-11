# Design: Rabbita Projection Editor Performance Recovery

**Parent:** [Performance Issues](../performance/RABBITA_PROJECTION_EDITOR_ISSUES.md)
**Related:** [2026-03-10 Memo-Derived ProjNode Design](./2026-03-10-memo-derived-projnode-design.md)
**Phase 5 Detail:** [2026-03-11 Tree Editor Subtree Reuse And Elision](./2026-03-11-tree-editor-subtree-reuse-design.md)
**Status:** Proposed
**Date:** 2026-03-11

---

## Problem

The Rabbita projectional editor currently composes several whole-document and whole-tree operations into a single synchronous input cycle:

1. full-document CRDT replacement on each `textarea` input
2. full-source reactive parse
3. full projection derivation
4. full `TreeEditorState` rebuild
5. full recursive view regeneration and diff

That architecture makes typing latency scale with total document and tree size instead of the edited span.

## Goal

Make the editor responsive under normal typing and tree-edit workloads by changing the architecture, not by tuning isolated hotspots.

The target design is:

- text edits are represented as deltas, not whole-string replacements
- parser state is updated incrementally from the same deltas
- projection refresh is driven by changed data, not unconditional full refreshes
- UI-only tree actions do not trigger parser/projection work
- render work is reduced to changed subtrees wherever possible

## Non-Goals

- Replacing Rabbita
- Replacing the CRDT
- Eliminating all full-tree traversals in one step
- Solving collaborative multi-user latency in this plan

## Success Criteria

### Functional

- Typing and backspace use edit-based APIs end-to-end.
- UI-only tree actions (`Select`, `Collapse`, `Expand`) do not trigger parser/projection recompute.
- Tree-edit operations preserve node identity semantics already established by the memo-derived projection work.

### Performance

- Keystroke cost scales primarily with edited span, not full document length.
- Projection refresh is not executed on every UI-only action.
- Large-tree typing is visibly responsive in Rabbita.

### Validation

- Add instrumentation or benchmark coverage for typing latency and refresh breakdown.
- Keep existing editor/projection correctness tests green.

---

## Architecture Direction

## Single Source of Truth: Edit Stream

The core mistake in the current design is letting DOM text input enter the system as a whole new string. The corrected architecture treats the user edit as the source of truth and feeds the same edit through every downstream layer:

```text
DOM input delta
  -> SyncEditor text edit API
  -> CRDT edit application
  -> parser incremental update
  -> projection memo refresh
  -> targeted tree/UI refresh
```

This means the first two priorities from the performance investigation are one architectural change, not two unrelated optimizations.

## Split Immediate Text Feedback From Structural Refresh

Typing must stay responsive even when projection refresh is more expensive than the text edit itself. The plan therefore separates:

- immediate text-state update
- structural projection/tree refresh

The initial implementation may still perform both in the same turn, but the interfaces must permit deferred or coalesced structural refresh later.

## Keep SyncEditor As The Integration Boundary

`SyncEditor` should remain the facade that owns:

- text document mutation
- undo grouping
- parser update
- memo-derived projection access

Rabbita should not coordinate parser or projection internals directly.

---

## Plan

### Phase 0. Measure the Current Pipeline

Before changing behavior, add coarse timing around:

- text edit application
- parser update
- `get_proj_node()`
- `TreeEditorState::refresh`
- Rabbita render/update cycle

This does not need browser-grade profiling first. Simple timers around the current hot path are enough to confirm which steps dominate on small, medium, and large examples.

**Deliverables**

- lightweight timing hooks or debug logging
- one baseline note appended to the performance doc

**Initial baseline from this branch (release, 2026-03-11)**

- Parser microbenchmarks in `editor/performance_benchmark.mbt`:
  - medium (80 lets): reactive full reparse `473.73 us`, imperative incremental `495.21 us`
  - large (320 lets): reactive full reparse `5.18 ms`, imperative incremental `5.33 ms`
- Rabbita typing-path benchmark note:
  - the old Rabbita benchmark loops were discarded because they reused one mutable editor state across the whole run, which polluted the measurement with growing undo/history state
  - `examples/rabbita/perf_report` is now wired through the real Rabbita reducer path via `BenchmarkSession`
  - fresh medium release samples from the fixed harness:
    - legacy `set_text + refresh`: `318 ms/edit`
    - incremental `apply_text_edit + refresh`: `294 ms/edit`
    - deferred `TextInput` only: `267 ms/edit`
    - deferred full cycle (`TextInput` + `RefreshProjection`): `343 ms/edit`
  - large release sample from the fixed harness:
    - first large deferred `TextInput` edit did not complete within a `5+ minute` observation window, so large-tree keystroke latency is still effectively non-interactive
  - current harness spot-check after adding `large` mode and iteration override:
    - `timeout 60s moon run perf_report medium 1` emitted one completed line before timeout:
      - legacy `set_text + refresh`: `336 ms/edit`
    - the same bounded run did not complete the remaining medium cases within `60s`
    - `timeout 60s moon run perf_report large 1` emitted no completed report lines before timing out
    - practical conclusion: the harness is now easier to drive, but it still needs timeout-aware per-case reporting before it is a reliable large-tree measurement tool

These numbers imply the parser delta work alone is not the dominant win. The remaining bottleneck is still projection/tree refresh and downstream UI rebuild on non-trivial trees.

**Current practical analysis from this branch**

- The subtree reuse / elision / hydration work is a meaningful architectural improvement, but it is not yet a large-tree performance fix.
- The branch improves correctness and keeps more UI work local, especially for selection and collapsed-subtree handling.
- The remaining worst-case cost still appears to be dominated by the structural pipeline rather than tree-widget work:
  - projection rebuild / reconcile
  - source map rebuild
  - `TreeEditorState::refresh(...)`
  - surrounding deferred full-cycle reducer work
- Medium-path behavior may improve incrementally, especially on deferred interactions, but the current harness still shows eager legacy refresh in the hundreds of milliseconds per edit.
- Large-tree behavior remains the blocking problem: even `large 1` still fails to produce a usable completed line within a practical bounded run.

So the correct read of this branch is:

- `yes` as an incremental structural/performance win
- `no` as the final answer to large-tree responsiveness
- `no` as evidence that stable `60fps` is now within reach without another round of structural pipeline optimization and better measurement

### Phase 1. Introduce Edit-Based Text APIs In SyncEditor

Add a public API that expresses text edits directly, for example:

```moonbit
pub fn SyncEditor::apply_text_edit(
  self,
  start : Int,
  deleted_len : Int,
  inserted : String,
  timestamp_ms : Int
) -> Unit
```

Requirements:

- apply the minimal CRDT edit instead of replacing the full document
- record undo through `UndoManager`
- preserve cursor semantics currently expected by Rabbita

`set_text(new_text)` can remain as a compatibility helper, but Rabbita typing must stop using it.

**Why first**

This removes the worst front-of-pipeline cost and gives the parser a usable edit representation.

### Phase 2. Feed Incremental Edits Into The Parser Layer

Change the editor/parser boundary so the parser consumes the same text delta applied to the CRDT.

Two acceptable implementation directions:

1. extend the reactive parser path so it can accept incremental text edits directly
2. introduce an incremental parser adapter owned by `SyncEditor`, then derive existing memos from that state

Selection criteria:

- preserve current memo-derived `ProjNode` integration
- avoid reparsing from the full source string after each keystroke
- keep one authoritative parser state owned by `SyncEditor`

This phase is the real architectural fix. Without it, Phase 1 only shifts the bottleneck from CRDT rewrite to full parse.

**Deliverables**

- edit-driven parser update API
- `SyncEditor` wired to that API
- regression tests for typing/backspace/edit-in-middle

### Phase 3. Separate Text Edits From UI-Only Tree Actions

Refactor Rabbita update handling so `TreeEdited(op)` does not always round-trip through the editor.

Rules:

- `Select`, `Collapse`, `Expand`, and similar UI-only ops update only `TreeEditorState`
- structural ops (`CommitEdit`, `WrapInLambda`, reorder, insert, delete) still call `editor.apply_tree_edit(...)`

This should eliminate a large amount of unnecessary parser/projection work immediately.

**Deliverables**

- explicit predicate or operation classification for structural vs UI-only tree edits
- updated Rabbita reducer logic
- regression tests for no-text-change UI operations

### Phase 4. Make Projection Refresh Coalescible

Once text edits and parser edits are incremental, make the refresh boundary explicit.

Introduce a `refresh_projection_if_needed()` style boundary in `SyncEditor` or the Rabbita integration layer so text input and structural refresh are not permanently welded together.

Possible first step:

- keep eager refresh for structural tree edits
- allow typed text input to coalesce multiple edits before tree refresh

This phase should be designed so future debounce/scheduling work is additive, not invasive.

**Deliverables**

- explicit dirty/refresh boundary
- clear documentation for when projection state is guaranteed fresh

### Phase 5. Reduce Tree Rebuild And Render Scope

After the edit and parser pipelines are corrected, optimize the UI layer:

- avoid rebuilding unchanged subtrees in `TreeEditorState::refresh`
- introduce keyed or identity-aware child rendering where Rabbita permits it
- stop recomputing sidebar selection data by scanning the full tree

This phase is intentionally later because it is not worth optimizing whole-tree UI rebuilds until the input and parse architecture is fixed.

**Deliverables**

- reduced `TreeEditorState` churn
- reduced VDOM diff work on insert/reorder heavy trees

---

## API Changes

### SyncEditor

Add:

```moonbit
pub fn SyncEditor::apply_text_edit(
  self,
  start : Int,
  deleted_len : Int,
  inserted : String,
  timestamp_ms : Int
) -> Unit
```

Potentially add:

```moonbit
pub fn SyncEditor::refresh_projection_if_needed(self) -> Unit
```

---

## Roadmap To Stable 60fps

The current Stage 1-5 tree-editor work should be treated as an intermediate step toward a `60fps` target, not the final performance fix. The next optimization work should proceed in this order:

**Caveat:** This roadmap is a higher-level prioritization overlay, not a replacement for the phase plan above. If later edits change phase ordering or scope, this section should be updated to stay aligned with the main implementation plan.

1. Add end-to-end timing for the deferred edit path.
   Measure:
   - text edit application
   - parser update
   - projection rebuild / reconcile
   - `SourceMap` rebuild
   - `TreeEditorState::refresh(...)`
   - Rabbita update / render cost

2. Fix the dominant large-tree hotspot before broad cleanup.
   Large-tree deferred refresh is still effectively non-interactive, so the next phase should target the worst measured slice directly.

3. Make projection metadata incremental by affected region.
   The likely next wall is still whole-tree rebuild of structural metadata such as preorder indexes, parent links, and source maps. If those remain full-tree on every edit, stable frame-budget behavior is unlikely.

4. Preserve strict separation between local UI work and structural refresh.
   UI-only actions must remain immediate and should continue to avoid parser or projection work unless explicitly required.

5. Allow structural refresh to be deferred/coalesced when it cannot fit the frame budget.
   Immediate interaction response should be prioritized over forcing every full structural update into one synchronous turn.

6. Revisit render-scope optimization after compute costs are bounded.
   Only after the compute path is measured and improved should the next wave focus on Rabbita subtree diff/render behavior.

7. Evaluate against frame-budget metrics, not just average benchmark throughput.
   Track:
   - p50 / p95 / p99 for UI-only operations
   - p50 / p95 for deferred full-cycle refresh
   - explicit `< 16ms` and `< 50ms` thresholds across small, medium, and large scenarios

This ordering reflects the practical conclusion from the current branch: subtree reuse and elision improve medium deferred behavior, but worst-case large-tree latency still points to full projection metadata work as the next major bottleneck.

Keep:

- `apply_tree_edit(...)`
- `get_proj_node()`
- `get_source_map()`

Deprecate for interactive typing:

- `set_text(new_text)`

### Rabbita Example

Change `TextInput(new_text)` handling to:

1. compute a minimal splice between old text and new text
2. call `apply_text_edit(...)`
3. refresh projection/tree state only through the new boundary

If DOM event data is insufficient for a robust minimal edit, add controlled selection/cursor tracking in the example rather than falling back to full-string replacement.

---

## Migration Strategy

### Step 1

Add the new `SyncEditor` text-edit API and tests without changing Rabbita.

### Step 2

Switch Rabbita typing to the new API and verify no behavioral regressions.

### Step 3

Change parser integration to consume incremental edits rather than whole-source rebuilds.

### Step 4

Split UI-only tree edits from structural tree edits.

### Step 5

Add refresh coalescing and then optimize tree/render scope.

This ordering keeps correctness risk low while ensuring each step produces a measurable latency win.

---

## Risks

### Input Diff Correctness

Computing minimal text deltas from DOM input can be tricky around IME, selection replacement, and multi-character edits.

Mitigation:

- keep the edit API general
- test replace-selection, paste, delete-range, and backspace
- treat IME support as an explicit validation item rather than an assumed success

### Parser Integration Complexity

The current reactive parser path is source-string-oriented. Making it truly incremental may require loom changes beyond Rabbita.

Mitigation:

- isolate the parser boundary change behind `SyncEditor`
- land the public API before optimizing internal memo plumbing

### Freshness Contracts

If projection refresh becomes coalesced, callers must know when `get_proj_node()` and `get_source_map()` are guaranteed fresh.

Mitigation:

- define a strict refresh contract in `SyncEditor`
- make stale/fresh boundaries explicit in naming and docs

### Premature UI Micro-Optimization

It is easy to spend time optimizing tree rendering before fixing the edit/parse pipeline.

Mitigation:

- do not start Phase 5 until Phases 1 through 3 are complete and remeasured

---

## Testing Plan

### Editor Tests

- typing single-character insert
- backspace/delete single character
- replace selected range
- insert in middle of document
- projection/node identity preserved after incremental text edit

### Rabbita Behavior Tests

- UI-only tree actions do not mutate text
- UI-only tree actions do not trigger projection refresh path
- structural tree edits still round-trip through text correctly

### Performance Checks

- compare typing latency before and after Phase 1
- compare parse/update time before and after Phase 2
- compare `TreeEdited(Select)` cost before and after Phase 3

---

## Recommended Implementation Order

If this work is done as multiple PRs, the order should be:

1. instrumentation baseline
2. `SyncEditor::apply_text_edit(...)`
3. Rabbita typing migration
4. incremental parser integration
5. UI-only tree action split
6. refresh coalescing
7. tree/render scope reduction

That sequence fixes the architecture first, then trims the remaining UI overhead.

## Exit Criteria

This plan is complete when:

- Rabbita typing no longer uses whole-string replacement
- parser updates are edit-driven rather than whole-source rebuilds
- UI-only tree actions avoid parser/projection work
- performance measurements show clear improvement on medium and large trees
