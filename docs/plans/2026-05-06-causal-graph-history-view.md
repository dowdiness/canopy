# Causal Graph History View — Phase 1

## Why

Canopy's CRDT (event-graph-walker) carries rich causal structure: every operation
records its parents, agent, and sequence, forming a DAG that captures *exactly*
how the document came to be. Today this structure is invisible — the OpLog tab
is a stub (`"No operations recorded"`), and users have no surface to see who
made what change, where collaborators diverged, or how merges resolved.

Most editors hide the CRDT and present a linear undo stack. A structure editor
should do the opposite: expose causal structure as a first-class collaboration
surface. This is consistent with the projectional bridge vision — show users
the real structure, don't simulate a flat one.

The infrastructure is already in place: `CausalGraph` implements
`@alga.DirectedGraph`, the graphviz pipeline (parse → layout → SVG) is wired
in `examples/ideal/main/view_bottom.mbt`, and the bottom-panel scaffold has a
working tab system. Phase 1 lights up that machinery for the causal DAG.

## Design Principles

1. **The CRDT is the feature, not an implementation detail.** The graph is
   product, not debug-only. Rendering quality and clarity matter.
2. **Read-only first, interaction later.** A static, accurate, legible DAG is
   strictly more valuable than a half-working interactive one. Time-travel,
   selection-driven highlighting, and editing operations are deferred.
3. **Agent identity is the primary axis.** Color encodes *who*; layout encodes
   *causality*. The two together communicate collaboration at a glance.
4. **Frontier is privileged.** "Now" is the most important thing on screen —
   highlight the frontier (current tips) prominently.
5. **Scale honestly.** Small graphs get full detail. Large graphs collapse
   linear single-agent runs into chain nodes; never render 10k DOM nodes.
6. **Reuse the existing pipeline.** No new layout engine, no new SVG renderer.
   `@gv_parser` → `@gv_layout` → `@gv_svg` already works.

## Scope

In:
- New module `examples/ideal/main/view_history.mbt` — DOT generation from
  `CausalSnapshot`, frontier highlighting, agent coloring, chain compression.
- `examples/ideal/main/view_bottom.mbt` — wire a new `History` tab variant.
- `examples/ideal/main/model.mbt` — extend `BottomTab` with `History`.
- New CSS rules in the ideal editor stylesheet for agent-colored nodes and
  frontier emphasis.
- Whitebox tests for DOT generation (snapshot a small constructed graph).

Out (deferred to later phases):
- Time-travel (clicking a node to rewind editor state).
- Selection-driven ancestor cone highlight.
- Swimlane / git-log-style custom layout.
- Operation detail popovers (insert/delete content preview).
- Replacing the existing `OpLog` tab — `History` is added alongside.
- Wiring into `examples/web/` (ideal editor only for Phase 1).
- Changes to egw public API. Phase 1 reads only existing accessors.

## Current State

- `CausalGraph` (egw `internal/causal_graph/`) implements
  `@alga.DirectedGraph`. Each `GraphEntry` exposes `parents : Array[Int]`,
  `agent : String`, `seq : Int`, `timestamp : Int`.
- `CausalGraph::get_frontier()` returns the current tips.
- `OpLog::causal_graph()` exposes the graph from the OpLog held by the editor.
- `view_bottom.mbt` already runs the full graphviz pipeline for the lambda
  resolver tab — the `render_dot_to_svg` helper is reusable.
- `BottomTab` is `enum { Problems, OpLog, CrdtState, Graphviz }`. Phase 1 adds
  a `History` variant.

## Design

### Data flow

```
Model.editor → SyncEditor::causal_snapshot()
                              │
                              ▼
                  collect_history_data
                  (snapshot + local agent →
                   entries, frontier set, agent palette)
                              │
                              ▼
                    chain_compress
                  (collapse linear runs)
                              │
                              ▼
                    emit_dot_string
                              │
                              ▼
                  render_dot_to_svg
                              │
                              ▼
                    inject into DOM
```

### Function design (prose, not code)

**`collect_history_data(snap : CausalSnapshot, local_agent : String) -> HistoryData`**
- Walk all LVs in the half-open range `0..<snap.op_count()`. For each
  LV, call `snap.entry(lv)` to obtain `parents`, `agent`, `seq`.
- The `local_agent` argument is required because the palette rule pins
  the local agent to color index 0, and that identity is not carried by
  the snapshot — it lives in `SyncEditor` / `Model`.
- Build a deterministic agent → color mapping: `local_agent` → 0,
  remaining unique agents → 1..7 in lexicographic order, wrapping after 8.
- Return frontier as a `Set[Int]` (built from `snap.frontier()`) for O(1)
  "is this a tip?" checks during compression and DOT emission.

**Invariant:** pure over `(snap, local_agent)`. Two calls with the same
inputs produce identical output. Determinism comes from the palette rule;
no other ordering is observable.

**`chain_compress(data : HistoryData, snap : CausalSnapshot) -> CompressedData`**
- Outdegree is read from `snap.children_count(lv)`. Indegree is read from
  the entry's `parents.length()`.
- A *chain* is a maximal run of LVs where each interior node has indegree
  exactly 1 (the previous node) and outdegree exactly 1 (the next node).
  Branches and merges break chains. The indegree/outdegree rule is the
  *correctness* condition — it guarantees the quotient graph is
  well-defined.
- Same-agent and contiguous-seq are an additional Phase 1 *policy*: even
  when the topology permits compression, only collapse runs from a
  single agent so the visual abstraction matches user mental model
  ("agent A typed 47 characters in a row"). This is conservative — a
  cross-agent indegree=1/outdegree=1 chain is rare but legal, and we
  choose to render it expanded for clarity. (Note: remote ops via
  `add_version_with_seq` can produce non-contiguous seq even within
  one agent; the policy permits seq gaps as long as agent matches.)
- Compressed nodes carry the full LV member list `[lv₀, lv₁, …, lvₙ]`,
  not just `(start, end, count)`. The DOT label can render as
  `"agent (47 ops)"` for Phase 1, but retaining the LV list is
  required for future selection / time-travel features and costs
  almost nothing.
- Frontier nodes are *never* collapsed — always rendered as singleton
  nodes so the user can see exactly where "now" is.
- Phase 1 threshold: only compress chains of length ≥ 5. Below that,
  rendering each node is clearer than the abstraction.

**Invariant:** compression preserves the *quotient* causal graph —
external reachability relations are unchanged. It does **not** preserve
per-op visibility; that lives in the LV member list, not in the rendered
output. Edges between chains preserve original parent relationships,
mapped to compressed node IDs. The mapping is unique because the
indegree=1/outdegree=1 rule forbids any external node from pointing
into the middle of a chain (that would give the middle node indegree>1)
and forbids any middle node from pointing outward (outdegree>1).

**`emit_dot_string(data : CompressedData, local_agent : String) -> String`**
- Produces a `digraph` with:
  - One node per compressed/uncompressed LV.
  - One edge per parent link (compressed appropriately).
  - Node attributes: `label`, `fillcolor` (agent color), `style=filled`,
    `penwidth` (thicker for frontier nodes).
  - Frontier nodes get a distinct stroke color (palette: amber on dark
    theme, matching the project's design tokens in `.impeccable.md`).
- Layout direction `rankdir=TB` (time flows top to bottom — earliest LVs
  at the top).
- Roots (LVs with no parents) are pinned to the top rank explicitly.
- Agent IDs appearing in labels MUST be DOT-escaped: backslash-escape
  `"` and `\`, and reject embedded newlines (replace with space). Agent
  IDs are user-controlled in the protocol, so this is a correctness
  requirement, not just hygiene.

**Invariant:** the emitted DOT must successfully parse via `@gv_parser` —
verified by the round-trip in tests, including a fuzz-style test with
agent IDs containing `"`, `\`, `{`, `}`, and high-Unicode codepoints.

**`view_history(model : Model) -> Html`**
- If the editor has zero ops, render an empty-state message reusing
  the existing `class="no-problems"` style.
- Otherwise, render an empty `<div id="canopy-history-container">` and
  rely on the same `AfterRender` cmd pattern used by the Graphviz tab to
  inject SVG after the DOM is mounted.

**`history_render_cmd(model : Model) -> Cmd`**
- Mirrors `graphviz_render_cmd`. Guarded by `bottom_tab == History &&
  bottom_visible`. Calls `collect_history_data` →
  `chain_compress` → `emit_dot_string` → `render_dot_to_svg` →
  `js_set_inner_html("canopy-history-container", svg)`.

### Color palette

Agents get colors from a fixed 8-color palette tuned for the dark theme
(`#1a1a2e` background). Assignment rule (deterministic, single source of
truth): the local agent gets index 0; remaining agents get indices 1..7
in lexicographic order of agent ID, wrapping after 8. Palette colors
themselves are out of scope for this doc — pick during prototyping with
the `/critique` skill.

Frontier highlight: stroke color separate from fill, so frontier-and-color
remain readable simultaneously.

### Tab integration

`BottomTab::History` slots between `OpLog` and `CrdtState` in the tab list.
The existing `OpLog` stub stays — we don't replace it in Phase 1, since
`OpLog` is intended to be a flat operation list view and `History` is a
graph view. They can coexist; future work may consolidate.

### Performance budget

- Re-render on every model update is fine for Phase 1 if op_count < 200.
- Above that, memoize on `(editor_identity, op_count)`. The causal graph
  is append-only in current egw — `op_count` alone is a monotonic
  generation. `frontier_hash` adds nothing in append-only mode.
  `editor_identity` guards against future document replacement or
  non-append semantics; without it the cache could collide across
  document swaps. Graphviz layout is the expensive step.
- **Defining `editor_identity`:** in canopy this is the *physical
  identity* of the `SyncEditor[T]` instance — the same `SyncEditor`
  always returns the same identity, and a freshly constructed one
  returns a different one. Implement as a process-local incrementing
  counter assigned at `SyncEditor::new_generic` time and exposed via
  a new `pub fn[T] SyncEditor::identity(self) -> Int` accessor. Agent
  ID / peer ID is **not** sufficient — those can be reused across
  document swaps and would silently collide in the cache.
- Hard ceiling for Phase 1: 1000 ops. **Do not truncate by recency** —
  a "most recent 1000 LVs" cut is not ancestry-closed, so it can drop
  required parents and silently misrepresent the DAG. Above the ceiling,
  Phase 1 *refuses to render* and shows a placeholder ("Graph too large
  — N ops; collapsing UI deferred to Phase 2"). Real scaling work
  (ancestry-closed prefix collapse with boundary edges, or swimlane
  layout) is a separate project.

## Phases

**Phase 0 — Expose a narrow `CausalSnapshot` (cross-submodule prerequisite).**

Codex review (2026-05-06) flagged that returning the full `CausalGraph`
bakes in LV-indexed storage, the `@alga.DirectedGraph` contract, and the
`agent/seq/timestamp` field shape as public commitments. That is a real
long-term cost if egw later changes representation. A narrow read-only
snapshot type is the better boundary.

- In `event-graph-walker`: add a new public package
  `event-graph-walker/history` (or `causal_snapshot`) exposing a
  read-only view type:

  ```moonbit
  pub struct CausalSnapshot { /* opaque */ }

  pub fn CausalSnapshot::op_count(self) -> Int
  pub fn CausalSnapshot::entry(self, lv : Int) -> SnapshotEntry?
  pub fn CausalSnapshot::frontier(self) -> Array[Int]
  pub fn CausalSnapshot::children_count(self, lv : Int) -> Int

  pub struct SnapshotEntry { /* opaque */ }

  pub fn SnapshotEntry::parents(self) -> ArrayView[Int]
  pub fn SnapshotEntry::agent(self) -> String
  pub fn SnapshotEntry::seq(self) -> Int

  // SnapshotEntry is opaque (`pub` struct with no exposed fields,
  // accessed via methods). Field-shaped exposure (`pub(all)`) was
  // rejected: even read-only field access via `pub` makes any field
  // rename or removal a breaking API change for downstream pattern
  // matching. With accessor methods, future revisions can add or
  // remove backing fields freely as long as the method surface is
  // preserved or evolved deprecation-style. `parents()` returns an
  // `ArrayView` to avoid copying; the underlying array is owned by
  // the snapshot.
  ```

  `children_count` is provided so chain compression can detect outdegree
  without exposing the full successors iterator. `timestamp` is omitted
  from `SnapshotEntry` until a use case appears.
- In `event-graph-walker`: keep `internal/causal_graph` internal. The
  new `history` package is responsible for materializing a
  `CausalSnapshot` from whatever internal representation egw chooses;
  the *public* surface (the methods listed above) stays narrow
  regardless. Implementation detail (zero-copy reference vs. owned
  copy) is left to egw and not constrained by this spec.
- In `event-graph-walker`: add `pub fn Document::causal_snapshot(self)
  -> @history.CausalSnapshot` in `internal/document/document.mbt`.
  `Document` stays internal; only this public method surfaces through
  `TextState`.
- In `event-graph-walker`: add `pub fn TextState::causal_snapshot(self)
  -> @history.CausalSnapshot` in `text/text_doc.mbt`.
- In `event-graph-walker`: bump version to 0.3.0 (additive, no breakage)
  and update `CHANGELOG.md`.
- In canopy `editor/moon.pkg`: add
  `"dowdiness/event-graph-walker/history"` to imports.
- In canopy `editor/`: add two accessors in a new file
  `sync_editor_history.mbt`:
  - `pub fn[T] SyncEditor::causal_snapshot(self : SyncEditor[T]) -> @history.CausalSnapshot`
  - `pub fn[T] SyncEditor::identity(self : SyncEditor[T]) -> Int` —
    returns a *construction identity* assigned when the `SyncEditor`
    is constructed. Two `SyncEditor` instances constructed separately
    have different identities; the same instance always returns the
    same value. Implementation: a private module-level counter
    incremented in `SyncEditor::new_generic`, stored in a new
    `priv identity : Int` field on `SyncEditor[T]`. **Concurrency
    assumption:** `SyncEditor::new_generic` is called from a single
    thread. MoonBit's web/native single-threaded runtime makes this
    trivially true today; if egw or canopy gains multi-thread editor
    construction, the counter must be made atomic. The cache key in
    Phase 1b uses this identity.
- Acceptance: `moon test` passes in egw; canopy `moon check` passes with
  the new submodule pointer; a smoke test in canopy/editor constructs
  a `SyncEditor`, calls `causal_snapshot()`, asserts `op_count() == 0`
  and `frontier() == []` on a fresh editor; constructs two `SyncEditor`
  instances and asserts their `identity()` values differ.
- This is a separate egw PR, landed and merged to egw `main` *before*
  Phase 1a touches canopy. Per project convention
  (`feedback_no_direct_push`), open a PR rather than pushing to egw
  main.

**Trade-off accepted:** `CausalSnapshot` does not expose
`@alga.DirectedGraph`, so canopy loses "free" toposort/reachable. For
this visualization we don't need them — chain compression and DOT
emission only need parents, op_count, frontier, and children_count.
If a future canopy feature needs full graph algorithms over the causal
DAG, that future need will justify either widening the snapshot
surface or implementing alga's trait on the snapshot itself.

**Phase 1a — DOT generation (no UI).**
- Implement `collect_history_data`, `chain_compress`, `emit_dot_string`.
- Whitebox tests: hand-construct small `CausalSnapshot` instances
  (linear, branching, merging, multi-agent) by driving a `SyncEditor`
  through scripted ops and reading the resulting snapshot. Tests live
  in canopy and consume the public `CausalSnapshot` API only — they do
  not import `internal/causal_graph` types.
- Acceptance: snapshot tests pass; round-trip through `@gv_parser` succeeds;
  the test list above (1–13) is fully covered.

**Phase 1b — UI integration.**
- Add `BottomTab::History`, `view_history`, `history_render_cmd`.
- CSS for agent palette and frontier emphasis.
- Manual verification in `examples/ideal` dev server: linear edits, undo,
  simulated multi-agent merge (whatever harness the existing CRDT tests use).
- Acceptance: visual inspection of three scenarios (single-agent linear,
  two-agent diverge, two-agent merge) shows correct structure.

**Phase 1c — Polish pass.**
- Run `/critique` on the resulting view (per project convention for visual
  features).
- Address P0/P1 findings: legibility, color contrast, spacing.
- Acceptance: critique score ≥ baseline of other ideal-editor panels.

## Tests

Whitebox (Phase 1a):
1. Empty graph → empty `digraph { }`.
2. Single op → one node, no edges. That node is on the frontier.
3. Linear 3-op chain (single agent) → not compressed (below threshold);
   3 nodes, 2 edges. The tail is on the frontier.
4. Linear 10-op chain (single agent), with the chain extended by one
   additional op (so LVs 0..9 form an interior chain and LV 10 is the
   frontier tip) → LVs 0..9 compressed to 1 node labeled
   `"agent (10 ops)"`; LV 10 rendered as a singleton frontier node.
   *(The original "10-op chain compresses to 1 node" wording was
   incorrect — the tip is on the frontier and frontier nodes are never
   collapsed, per the chain_compress invariant.)*
5. Linear 10-op chain (single agent) where the chain itself terminates
   at the frontier — LV 9 is the sole frontier node, LVs 0..8 are
   strictly interior. Expected: LVs 0..8 compressed into one node
   (chain of length 9, ≥ 5 threshold); LV 9 rendered as a singleton
   frontier node.
6. Two-agent divergence (root → A1, root → B1) → 3 nodes, 2 edges, two
   distinct fill colors; both A1 and B1 are frontier tips.
7. Merge (A1, B1 → C1 with parents=[A1, B1]) → C1 has two incoming edges,
   C1 is the only frontier tip.
8. Cross-agent indegree=1/outdegree=1 chain → renders expanded (Phase 1
   policy: same-agent only).
9. Same-agent chain with seq gap (e.g., remote `add_version_with_seq`
   inserts seq 7 then later seq 9 from the same agent with no
   intervening seq 8) → still compressed (policy permits seq gaps as
   long as agent matches).
10. Frontier highlighting: render a graph where LVs 5 and 7 are tips →
    nodes 5 and 7 get the frontier stroke; others don't.
11. Boundary: 1000-op graph renders; 1001-op graph emits the
    "Graph too large" placeholder without invoking layout. Ceiling
    check happens before DOT/layout work.
12. Agent ID escaping: snapshot containing agents named `agent"with"quotes`,
    `agent\with\backslash`, and `agent{brace}` produces DOT that
    round-trips through `@gv_parser.parse_dot` without error.
13. DOT round-trip: every emitted string from tests 1–12 parses via
    `@gv_parser.parse_dot` without error.

Manual (Phase 1b):
- Linear typing in single-agent mode.
- Undo/redo cycle.
- Two-tab simulated collaboration if available; otherwise scripted
  multi-agent insert.

## Open Questions

1. **~~Where does the `CausalGraph` come from in the ideal editor?~~**
   *Resolved 2026-05-06: blocked.* The accessor path from
   `Model.editor → SyncEditor.doc → TextState.inner → Document.oplog →
   CausalGraph` is closed at three points:
   - `SyncEditor.doc : TextState` is `priv` with no accessor.
   - `TextState.inner : Document` is `priv`, and `Document` lives in
     egw's `internal/document` (not a public package).
   - `OpLog` lives in egw's `internal/oplog` (not a public package).

   `OpLog::causal_graph()` is itself public, but unreachable from canopy
   because all packages above it are `internal/`. **Phase 0** (new) is
   required before Phase 1b.

2. **Agent palette source.** Hardcode in this module, or pull from a
   shared design-tokens file? Prefer shared if one exists; otherwise
   inline and migrate later.
3. **Should `History` replace `OpLog` eventually?** Defer. Decide after
   Phase 1c based on whether `OpLog` text view still feels useful next
   to the graph.
4. **~~Memoization key under undo.~~** *Resolved 2026-05-06: premise
   was wrong.* Codex review confirmed via `internal/oplog/oplog.mbt`
   and `internal/document/document.mbt` that egw undo does **not**
   prune the graph — undo appends fresh delete/undelete ops on the
   current frontier. The actual hazard is document replacement / future
   non-append semantics. Cache key updated above to
   `(editor_identity, op_count)`.

## Risks

- **Layered DOT layout doesn't read well for wide graphs.** Mitigation:
  measure on real multi-agent scenarios in Phase 1b. If unreadable, this
  spec is wrong and we need to skip ahead to swimlane layout — flag
  early, don't push through.
- **Agent identity is unstable in tests / fuzz scenarios.** Mitigation:
  deterministic palette rule (local=0, then lexicographic); document this
  in the `collect_history_data` contract.
- **Graph grows without bound.** Phase 1 refuses to render past 1000 ops.
  Real scaling work — ancestry-closed prefix collapse — is a separate
  project. Recency-based truncation is **explicitly rejected** because it
  is not ancestry-closed and silently misrepresents the DAG.

## Next Steps

1. Land Phase 0 in egw as its own PR. This is the critical-path
   prerequisite — Phase 1a depends on the new
   `event-graph-walker/history` package being importable.
2. Bump the egw submodule pointer in canopy and confirm `moon check`
   passes across the workspace.
3. Land Phase 1a (DOT generation + tests) as a canopy PR. Codex
   review per `feedback_codex_design_review.md` before merge.
4. Land Phase 1b (UI wiring) in a second canopy PR.
5. Land Phase 1c (polish) in a third canopy PR after `/critique`.

## References

- `event-graph-walker/internal/causal_graph/directed_graph.mbt` —
  alga `DirectedGraph` impl for `CausalGraph`.
- `examples/ideal/main/view_bottom.mbt` — reference graphviz pipeline
  integration.
- `docs/plans/2026-04-04-scope-colored-tree-view-design.md` — analogous
  visual-feature spec for principle reuse.
- `project_projectional_bridge_vision.md` — broader rationale for
  exposing real structure to users.
