# Markdown Semantic Identity Bridge — Feasibility Prototype Design

**Status:** Design spike complete; implementation deferred pending a qualifying consumer failure.
**Issue:** #940
**Date:** 2026-07-24

## Outcome

The observed Markdown browser failure was not a semantic-identity failure.
Canopy #943 restored setext-heading text spans in the compatibility projection,
and Canopy #944 preserves the selected block and caret range across mode
switches using the existing reconciled `NodeId`. The current Markdown browser
has no outline or drag/reorder consumer requiring a semantic identity layer.

Do not begin this prototype unless a user-visible continuity failure remains
after projection metadata and browser-shell state are correct. A qualifying
failure must show that a logically continuous entity loses its reconciled
`NodeId` and that an implemented consumer (for example selection, outline, or
drag/reorder) cannot recover without semantic identity.

## Why

Canopy needs stable session-local identity for Markdown semantic entities
(headings today; paragraphs, list items, code blocks as follow-ups). The
existing projection pipeline already preserves `NodeId` across reparses via
generic reconciliation (`core/reconcile.mbt`), and Loom's generic
`ProjectionIdentityTracker` / `ProjectionIdentityBaseline` /
`StableProjectionLeaf` / `realign_projection_items_with_optional_edit`
(`dowdiness/loom/projection`, imported as `@loomproj`) provide edit-window
realignment for semantic leaves.

Two structural mismatches block direct reuse:

1. **Loom identity candidates include inline leaves** (the
   `ProjectionLeaf` / `StableProjectionLeaf` API operates at leaf granularity),
   while Canopy's Markdown projection is block-shaped:
   `ProjNode[@markdown.Block]` (`lang/markdown/proj/proj_node.mbt`,
   `core/proj_node.mbt`). A heading block contains inline content
   (`Heading(Int, Array[Inline])`); one block node maps to many inline leaves.
   One-to-one attachment of a Loom identity tracker leaf to a block ProjNode
   is not feasible without either flattening the projection (which would break
   the entire edit/view pipeline) or duplicating Markdown semantic leaf
   extraction in Canopy (rejected: the extraction logic belongs in Loom's
   Markdown grammar package).

2. **Loom's `MarkdownProjectionIdentityTracker` and `MarkdownNodeId` are
   private** to the Loom Markdown example package. They are not a public API
   and cannot be imported by Canopy. The generic `ProjectionIdentityTracker`
   is public, but it has no Markdown-specific knowledge.

The existing Canopy heading side table
(`lang/markdown/proj/sdeg_heading_side_table.mbt`) already implements a
package-private session-local `stable_id → current NodeId` association for
headings with a five-state lifecycle (Live, Missing, Tombstoned, Ambiguous,
Retired). It demonstrates that the ephemeral-association pattern works for
one entity kind. The question is whether the pattern can be generalized
through a Loom-owned facade without Canopy duplicating semantic extraction.

## Scope

In:
- A bounded feasibility prototype defining the boundary between a
  Loom-owned opaque block-mappable identity-session facade and a
  Canopy-owned ephemeral semantic-ID → current-NodeId association.
- State transition contract for the Canopy-owned association.
- Mapping contract and explicit unsupported outcomes.
- Prototype scope, non-goals, test matrix, and follow-up PR sequence.

Out:
- Implementing the facade (this document does not approve implementation).
- Changing `ProjNode`, `SourceMap`, `reconcile`, or the Markdown edit layer.
- Introducing a public `EntityId` or durable identity type.
- CRDT persistence of semantic identity.
- Non-Markdown languages.
- Modifying Loom's private `MarkdownProjectionIdentityTracker` or
  `MarkdownNodeId`.

## Current State — Evidence Links

| Component | Location | Role |
|-----------|----------|------|
| Block-shaped projection | `lang/markdown/proj/proj_node.mbt` | CST → `ProjNode[@markdown.Block]`; tree mirrors block structure |
| Generic reconcile | `core/reconcile.mbt` | Position/LCS-based NodeId preservation across reparses |
| Markdown move reconciliation | `lang/markdown/proj/move_reconcile.mbt` | Explicit `IdentityTransform::Move` provenance for block moves |
| Heading side table | `lang/markdown/proj/sdeg_heading_side_table.mbt` | Package-private session-local `stable_id → current NodeId` for headings |
| Heading side table memo | `lang/markdown/proj/sdeg_heading_side_table.mbt` (`build_markdown_heading_side_table_memo`) | Reactive derivation attached to parser; advances on valid snapshots, holds on invalid |
| Heading spike tests | `lang/markdown/proj/sdeg_heading_spike_wbtest.mbt` | Proves `ProjectionIdentityTracker` does not solve heading reorder or delete-restore |
| SDEG design direction | `docs/design/stable-document-entity-graph.md` | "Identity is a hypothesis with evidence" |
| SDEG invariant review | `docs/design/sdeg-invariant-review.md` | Core finding: surviving NodeId proves handle continuity, not semantic continuity |
| Identity ADR | `docs/decisions/2026-06-01-identity-and-reuse-mechanisms.md` | Three-mechanism layering; `ProjectionIdentityTracker` is mechanism #2 |
| Phase 0 spike archive | `docs/archive/2026-06-18-sdeg-phase0-markdown-heading-spike.md` | Heading-as-entity feasibility; `ProjectionIdentityTracker` insufficient for reorder |
| Public projection API | `lang/markdown/proj/pkg.generated.mbti` | Exports: `build_markdown_projection_memos`, `parse_to_proj_node`, `syntax_to_proj_node`, `proj_to_view_node`, `populate_token_spans` |
| Loom projection imports | `lang/markdown/proj/moon.pkg` | `"dowdiness/loom/projection" @loomproj` — provides `ProjectionLeaf`, `StableProjectionLeaf`, `ProjectionIdentityBaseline`, `realign_projection_items_with_optional_edit` |

## Chosen Boundary

### Loom-owned: opaque block-mappable identity-session facade

Loom provides an opaque facade that owns MarkdownIR lowering, semantic-key
extraction, and tracker advancement. The facade does not expose inline leaves,
Loom-internal `MarkdownNodeId`, or `MarkdownProjectionIdentityTracker` to
Canopy. Instead, it offers:

- **Block-mappable identity session**: an opaque handle created per parser
  session. On each successful source/edit transition, the session produces
  opaque session-local tokens paired with a *proposed block-match descriptor*.
  The descriptor must be generated in Loom; Canopy does not calculate a
  Markdown semantic key.
- **Rebuild-on-edit contract**: the session advances from source and optional
  edit input, then reports preserved, churned, or fresh tokens for the current
  successful projection.
- **No semantic extraction in Canopy**: Canopy only attempts to match each
  descriptor to a current block-shaped `ProjNode`. The prototype must prove
  that a descriptor can map to exactly one node; zero or multiple matches
  produce no association rather than a guessed one.

### Canopy-owned: ephemeral semantic-ID → current NodeId association

Canopy owns a thin, ephemeral association layer that:

- Holds a `Map[SemanticId, NodeId]` rebuilt after each successful projection.
- Is discarded entirely on projection failure or full rebuild (malformed
  input, `set_source` reset).
- Does not persist across sessions, CRDT sync, or reload.
- Does not become the document source of truth.

This mirrors the existing heading side table pattern
(`sdeg_heading_side_table.mbt`) but is generalized to accept identity tokens
from the Loom facade rather than seeding stable IDs from `NodeId` directly.

### Rejected Alternatives

| Alternative | Why rejected |
|-------------|-------------|
| **Import Loom's `MarkdownProjectionIdentityTracker` / `MarkdownNodeId` directly** | Private to Loom's Markdown example package; not a public API. Making them public would couple Loom's internal identity representation to Canopy's projection shape. |
| **Duplicate Markdown semantic leaf extraction in Canopy** | The extraction logic (heading level + inline text, list item content, code block info string) belongs in Loom's Markdown grammar. Duplicating it in Canopy creates a second source of truth for semantic keys that drifts when the grammar evolves. |
| **Flatten `ProjNode[@markdown.Block]` to inline leaves for Loom tracker** | Breaks the entire edit/view/protocol pipeline. `ProjNode` tree structure mirrors block structure; inline leaves are not projection nodes. |
| **One-to-one attach Loom `StableProjectionLeaf` to block `ProjNode`** | Block nodes contain multiple inline leaves; one block maps to many leaves. The attachment cardinality is wrong. |
| **Replace the heading side table with a direct Loom tracker call** | The side table already works for headings. The facade should abstract over it, not replace it before the facade is proven. |
| **Introduce a durable `EntityId` in this prototype** | Premature. The prototype validates whether the ephemeral association pattern generalizes; durable identity is a follow-up only if the prototype succeeds. |

## State Transition Table

The Canopy-owned ephemeral association has three states per semantic entity:

| Current state | Event | Next state | Effect |
|---------------|-------|------------|--------|
| *(none)* | Successful projection with new semantic entity | **Associated** | Insert `(SemanticId → NodeId)` into the map |
| **Associated** | Successful projection; entity preserved (same SemanticId, possibly new NodeId) | **Associated** | Update `NodeId` in the map |
| **Associated** | Successful projection; entity absent (SemanticId not in new projection) | **Dropped** | Remove from the map |
| **Associated** | Projection failure (malformed input, diagnostics non-empty, `Error` blocks present) | **Suspended** | Retain the map entry but mark it unavailable; do not advance absence counters |
| **Suspended** | Valid projection returns; entity present | **Associated** | Restore with new `NodeId` |
| **Suspended** | Valid projection returns; entity absent | **Dropped** | Remove from the map |
| **Suspended** | Another failure before recovery | **Suspended** | No change; entry remains unavailable |
| **Dropped** | Successful projection; entity reappears with same SemanticId | **Associated** | Re-insert with new `NodeId` |
| **Dropped** | Full rebuild (session reset, `set_source` on new document) | *(discarded)* | Entire map discarded |
| Any | Full rebuild / session discard | *(discarded)* | Entire map discarded; all entries lost |

Key invariants:
- The map is **always consistent with the current valid projection** or
  empty (after discard). It never holds stale associations that contradict
  the current projection.
- Failure suspends but does not advance lifecycle counters. This matches the
  existing heading side table's `HeadingSnapshotInvalid` behavior
  (`sdeg_heading_side_table.mbt`: invalid snapshots mark live/ambiguous rows
  unavailable without advancing the absence ladder).
- No tombstone or retirement state in the prototype. The existing heading
  side table's `Tombstoned`/`Retired` states are heading-specific lifecycle
  that the facade does not generalize.

## Mapping Contract

### What the facade provides

- An opaque identity session handle, created per parser session.
- A `present(session, source, edit?) → IdentityMapping` function that lowers
  Markdown and advances identity internally.
- For each current token, a *proposed block-match descriptor* generated by
  Loom, plus preservation/churn/fresh classification. The descriptor's exact
  public shape is a prototype question; it must be sufficient to identify one
  block node without exposing Markdown's private semantic key or inline leaves.
- Token equality is opaque to Canopy. Canopy compares tokens for equality
  only; it does not inspect, serialize, or persist them.

### What Canopy provides

- The current `ProjNode[@markdown.Block]`, `SourceMap`, and its current
  `NodeId` values after each successful projection.
- Deterministic matching of a Loom-provided descriptor to exactly one current
  block. Zero or multiple matches are reported as unmatched/ambiguous and do
  not enter the association map.

### Explicit unsupported outcomes

| Outcome | Behavior | Rationale |
|---------|----------|-----------|
| Semantic reorder (e.g., `# A\n# B` → `# B\n# A`) | Tokens churn; Canopy sees fresh tokens, not preserved | The generic `ProjectionIdentityTracker` does not solve reorder (`sdeg_heading_spike_wbtest.mbt`: "ProjectionIdentityTracker does not solve heading reorder"). The facade inherits this limitation. |
| Delete-restore recovery | Tokens are fresh after restore; no tombstone recovery | `ProjectionIdentityTracker` does not recover after committed delete (`sdeg_heading_spike_wbtest.mbt`: "ProjectionIdentityTracker does not recover after committed delete"). |
| Duplicate headings (`# A\n# A`) | Ambiguous; facade returns distinct tokens but Canopy cannot distinguish semantically | Heading side table already marks duplicates `HeadingAmbiguous` (`sdeg_heading_side_table.mbt`). |
| Inline content changes within a block | Block token preserved if semantic key is stable; inline leaves are not tracked | Block-shaped projection; inline changes are below the facade's granularity. |
| Cross-language identity | Not supported | Each language has its own facade session. |
| CRDT-peer identity | Not supported | Tokens are session-local; peers have independent sessions. |
| Persisted identity across reload | Not supported | Tokens are ephemeral; discarded on session end. |

## Prototype Scope

### In scope for the prototype

1. **Loom facade definition**: prototype an opaque Markdown block-identity
   session at the Markdown package boundary. It accepts source/edit input,
   owns lowering and semantic-key extraction, and returns opaque tokens with
   proposed block-match descriptors. Do not generalize the interface beyond
   Markdown until one Canopy consumer proves the descriptor contract.

2. **Canopy association layer**: generalize the heading side table pattern
   to consume facade tokens instead of seeding stable IDs from `NodeId`.
   The first consumer remains the heading side table; the prototype
   validates that the generalization does not regress heading behavior.

3. **Rebuild-on-edit wiring**: after each successful projection in
   `build_markdown_projection_memos`, present block observations to the
   facade session and rebuild the ephemeral association map. On failure,
   suspend the map.

4. **Whitebox tests**: extend `sdeg_heading_spike_wbtest.mbt` and
   `sdeg_heading_side_table_wbtest.mbt` to verify that the facade-backed
   association preserves heading identity for the cases the current side
   table already handles (rename, whitespace rewrite, malformed recovery)
   and correctly reports unsupported outcomes (reorder, delete-restore,
   duplicates).

### Non-goals

- Implementing semantic reorder recovery.
- Implementing delete-restore tombstone recovery.
- Extending to non-heading entity kinds (paragraphs, list items, code
  blocks). Follow-up after the prototype validates the facade pattern.
- Durable or CRDT-peer identity.
- Changing the `ProjNode` tree shape or the edit/view pipeline.
- Publishing the facade as stable public API. The prototype keeps it
  package-private or `pub(readonly)` until a second consumer proves reuse.

## Test Matrix

| Test | Current evidence | Prototype expectation |
|------|-----------------|----------------------|
| Heading rename preserves identity | `sdeg_heading_spike_wbtest.mbt`: "heading rename preserves session-local NodeId" | Facade token preserved; association map updated with same SemanticId, possibly new NodeId |
| Heading reorder churns identity | `sdeg_heading_spike_wbtest.mbt`: "ProjectionIdentityTracker does not solve heading reorder" | Facade tokens are fresh; association map drops old entries and inserts new ones |
| Delete-restore does not recover | `sdeg_heading_spike_wbtest.mbt`: "ProjectionIdentityTracker does not recover after committed delete" | Facade tokens are fresh after restore; no tombstone recovery |
| Duplicate headings are ambiguous | `sdeg_heading_side_table_wbtest.mbt`: "semantic side-table matcher marks duplicate headings ambiguous" | Facade returns distinct tokens; association layer marks ambiguous per existing semantics |
| Malformed input suspends association | `sdeg_heading_side_table.mbt`: `HeadingSnapshotInvalid` path | Map entries suspended; no absence counter advancement |
| Recovery from malformed input | `sdeg_heading_spike_wbtest.mbt`: "inline malformed-to-recovered heading preserves heading NodeId" | Map entries restored with new NodeId |
| Whitespace rewrite preserves identity | `sdeg_heading_spike_wbtest.mbt`: "format-like whitespace rewrite preserves heading NodeIds" | Facade tokens preserved; association map stable |
| Full rebuild discards all associations | No existing test (new behavior) | Map entirely discarded; subsequent projection starts fresh |

## Follow-Up PR Sequence

### PR 1 — Loom: define the opaque identity-session facade interface

- Add the facade types and session lifecycle to a Loom package.
- Define the source/edit input contract and the proposed block-match
  descriptor plus identity-mapping output contract.
- Keep the facade package-private or `pub(readonly)` until a second
  consumer proves reuse.
- No Markdown-specific logic in the facade interface; semantic key
  extraction is a callback or trait method provided by the language package.
- Validation: `moon check` and `moon test` in the Loom submodule.

### PR 2 — Loom: implement the facade for Markdown block observations

- Reuse Loom's existing Markdown semantic-key extraction (heading level +
  inline text, list item content, etc.) and `ProjectionIdentityTracker`
  internally for edit-window realignment.
- Prove that the facade can emit an unambiguous block-match descriptor for
  headings before adding other entity kinds.
- Validation: `moon check` and `moon test` in the Loom submodule.

### PR 3 — Canopy: bump Loom pin and consume the facade in the heading side table

- Bump the Loom submodule pointer.
- Modify `build_markdown_heading_side_table_memo` to obtain an identity
  session from the facade and present block observations after each
  successful projection.
- Replace direct `NodeId`-seeded stable IDs with facade tokens.
- Verify that existing heading side table tests still pass.
- Validation: `moon check`, `moon test`, `moon info && moon fmt` at
  workspace root.

### PR 4 — Canopy: generalize the ephemeral association beyond headings

- Extract the heading-specific association pattern into a reusable
  Canopy-owned ephemeral association layer that consumes facade tokens.
- Add the first non-heading entity kind (likely list items or code blocks)
  as a second consumer.
- Validation: `moon check`, `moon test`, `moon info && moon fmt` at
  workspace root.

### PR 5 — Browser: consume stable identity in the Markdown editor UI

- Wire the Markdown editor's outline panel, selection, and drag-drop to
  use facade tokens (via FFI) instead of raw `NodeId` for entity-level
  operations.
- Validate that selection survives heading rename and whitespace rewrite
  in the browser.
- Validation: `moon build --target js`, `npx tsc --noEmit` in
  `examples/web`, Playwright E2E in `examples/ideal/web`.

## Exit Criteria

The prototype succeeds when all of the following are true:

1. The Loom facade interface is defined and has at least one working
   implementation for Markdown block observations.
2. Canopy's heading side table consumes facade tokens without regressing
   any existing heading side table test.
3. The ephemeral association map correctly transitions through Associated,
   Suspended, and Dropped states per the state transition table above.
4. Unsupported outcomes (reorder, delete-restore, duplicates) are
   explicitly reported and tested, not silently mishandled.
5. A second entity kind (beyond headings) demonstrates that the facade
   pattern generalizes.
6. No `ProjNode`, `SourceMap`, `reconcile`, or edit-layer changes were
   required.

## Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| The facade interface is too abstract to be useful | Canopy cannot extract enough information from opaque tokens to drive UI | Define the mapping output contract with explicit preservation/churn/fresh classification before implementing |
| Loom's internal `ProjectionIdentityTracker` cannot be wrapped without leaking implementation details | The facade exposes too much or too little | Keep the facade as a thin wrapper; do not try to generalize the tracker itself |
| The heading side table's five-state lifecycle does not map cleanly to the three-state prototype | Regression in heading identity behavior | The prototype's three states (Associated, Suspended, Dropped) are a subset; Tombstoned/Retired remain heading-specific and stay in the side table, not the facade |
| Bumping the Loom pin introduces unrelated changes | CI breakage in Canopy | Bump pin in a dedicated PR with full workspace validation before consuming the facade |
| The facade adds per-keystroke overhead to the projection pipeline | Frame budget exceeded on large documents | The facade call is O(block count) per projection; benchmark before and after on the existing Markdown benchmark corpus |
| Loom descriptor cannot match one current block | Canopy cannot build a safe association without guessing | Prototype headings first; require exact-one matching through current `ProjNode`/`SourceMap`, and treat zero/multiple matches as unsupported |

## Notes

- This document does not claim that any API described here already exists
  or that implementation is approved. The facade interface, the Canopy
  association layer, and the follow-up PRs are all proposed work.
- The existing heading side table (`sdeg_heading_side_table.mbt`) is the
  strongest evidence that the ephemeral-association pattern works. The
  prototype should preserve and extend it, not replace it prematurely.
- The SDEG invariant review (`docs/design/sdeg-invariant-review.md`)
  identified the core finding that "a surviving NodeId proves
  projection-handle continuity, rather than semantic continuity." The
  facade inherits this limitation; the prototype makes it explicit rather
 than hiding it.
- The identity ADR (`docs/decisions/2026-06-01-identity-and-reuse-mechanisms.md`)
  documents three distinct identity mechanisms. The facade is a fourth
  layer that sits above mechanism #2 (`ProjectionIdentityTracker`) and
  below the SDEG entity layer. It does not replace or merge with the
  existing three mechanisms.
