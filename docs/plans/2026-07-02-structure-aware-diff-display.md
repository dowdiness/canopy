## Structure-aware diff display from reconciliation trace

Tracking issue: [#830](https://github.com/dowdiness/canopy/issues/830)

**Why:** The Patch panel currently shows `Array[SpanEdit]` (character-level text diffs). After a structural edit like `WrapInLambda(node_42)`, the user sees "insert '(' at 15, insert 'x) => ' at 16" — correct but useless. The editor knows the edit was a wrap (via `IdentityTransform::Wrap(inner=42)`), but this information is discarded after reconciliation. We can instrument the reconciliation pipeline to emit a structural change trace alongside the reconciled tree, making the patch panel show "Wrapped node #42 in a lambda" instead.

Level: `docs/architecture/grove-and-structural-identity.md` Level 0/1 display.

### Design

Instead of a separate `compute_structured_diff(old, new)` that re-runs LCS (duplicates work + can't distinguish a Wrap from a coincidental same-kind match), the diff is an **instrumented reconciliation trace**. The existing `reconcile_children` already computes:

- `old_matched[i] = j` / `new_matched[j] = i` — which children matched via LCS
- `structural_pair / try_unmatched_hint_pair` — which nodes got identity-preserving hints
- `assign_fresh_ids` — which nodes got new IDs (no identity preserved)

### Two layers: reconciliation trace vs user-visible diff

The instrumentation captures every decision point in reconciliation as a `ReconcileTraceEvent` — including `Matched` (LCS said "same node"). This is the raw trace. The user-visible `StructuredChange` is a **filtered projection** of the trace that omits `Matched` events.

```moonbit
/// Raw trace from the reconciliation walker — every decision point.
pub(all) enum ReconcileTraceEvent {
  Matched(parent_id : NodeId, old_index : Int, new_index : Int, node_id : NodeId, kind_tag : String)
  Inserted(parent_id : NodeId, index : Int, node_id : NodeId, kind_tag : String)
  Deleted(parent_id : NodeId, index : Int, node_id : NodeId, kind_tag : String)
  Wrapped(inner_id : NodeId, wrapper_node_id : NodeId, wrapper_kind : String)
  Unwrapped(wrapper_id : NodeId, kept_id : NodeId, wrapper_kind : String)
  Renamed(node_id : NodeId, kind_tag : String)
  Freshened(parent_id : NodeId, index : Int, node_id : NodeId, kind_tag : String)
}

/// User-facing structural change — Matched events filtered out.
pub(all) enum StructuredChange {
  Inserted(parent_id : NodeId, index : Int, node_id : NodeId, kind_tag : String)
  Deleted(parent_id : NodeId, index : Int, node_id : NodeId, kind_tag : String)
  Wrapped(inner_id : NodeId, wrapper_node_id : NodeId, wrapper_kind : String)
  Unwrapped(wrapper_id : NodeId, kept_id : NodeId, wrapper_kind : String)
  Renamed(node_id : NodeId, kind_tag : String)
  Freshened(parent_id : NodeId, index : Int, node_id : NodeId, kind_tag : String)
}
```

Note: `Moved` is deliberately excluded from both enums. The current `reconcile_children` matches children within the same parent via LCS and cannot detect cross-parent movement. `Moved` will always be represented as `Deleted + Inserted` until cross-parent reconciliation (match_entities / SDEG) is available. If a future consumer needs explicit move detection, add it then — the enum shapes are additive.

The trace closure populates the `trace_ref` `Array` on each reconciliation pass. The caller (Patch panel) filters to `StructuredChange` by dropping `Matched` events. This keeps the raw trace available for debugging without exposing noise to the user.

Consequence: exit criterion 3 ("empty diff produces []") refers to `StructuredChange`, not the raw trace. `ReconcileTraceEvent` always contains `Matched(root)`.

### Implementation approach

The reconciliation runs inside an `incr` Derived memo — it fires automatically on every text change. An "on-demand" callback cannot be injected into an already-running Derived closure. Instead, pass an optional `trace_ref: Option[Ref[Array[ReconcileTraceEvent]]]` to `build_projection_memos`:

```moonbit
pub fn[T : TreeNode + Eq] build_projection_memos(
  rt : @incr.Runtime,
  syntax_tree : @incr.Derived[@seam.SyntaxNode],
  syntax_to_proj : (@seam.SyntaxNode, Ref[Int]) -> ProjNode[T],
  populate_spans : (SourceMap, @seam.SyntaxNode, ProjNode[T]) -> Unit,
  reconcile_node? : (ProjNode[T], ProjNode[T], Ref[Int]) -> ProjNode[T] = reconcile,
  trace_ref? : Option[Ref[Array[ReconcileTraceEvent]]] = None,
  label? : String = "generic",
) -> ...  // unchanged return type
```

When `trace_ref` is `Some(ref)`, the reconcile closure populates `ref.val` on each pass. When `None`, event emission is skipped (zero runtime cost — a single `trace_ref.is_none()` check at each decision point; the `Show`-based formatting of `kind_tag` is the real cost and must be gated behind the same check). The Patch panel reads from this Ref when visible.

The events are collected during the recursive `reconcile_children` / `reconcile_hinted` / `structural_pair` walk. Each call site that currently produces or skips a child emits one event via `trace_ref`.

### Scope

- **Core layer** — `core/reconcile.mbt`: emit `ReconcileTraceEvent` at each decision point inside `reconcile_children` / `structural_pair` / `assign_fresh_ids`
- **Core layer** — `core/projection_memo.mbt`: add `trace_ref` parameter to `build_projection_memos`, thread it into reconciliation
- **View layer** — `examples/ideal/main/`: Patch panel reads `trace_ref` and renders `StructuredChange` events

### Exit criteria

1. `core/reconcile.mbt` emits `ReconcileTraceEvent` through the `trace_ref`. Unit tests in `core/reconcile_hints_wbtest.mbt` verify events for Wrap, Unwrap, RenameLeaf, and LCS-only (no hint) cases using existing TestExpr fixtures.
2. Patch panel shows structural diff events. At minimum: a collapsible "Structural changes" section listing events as formatted text (e.g., `Wrapped #42 in Lambda`). A new tab is NOT required — extend the existing Patch tab's entry row.
3. Empty diff (no structural change, same text) produces `[]` `StructuredChange` events (raw `ReconcileTraceEvent` still contains `Matched(root)`).
4. Tracing is opt-in — `trace_ref` defaults to `None`, and the production path (`build_lambda_projection_memos` without tracing) allocates no trace array and formats no event strings.
5. `moon check` + `moon test` pass. `git diff *.mbti` reviewed.

### Non-goals

- Not redesigning the Patch panel layout. Events render as text lines in the existing tab.
- Not storing diff events across reparses — the `trace_ref` array is replaced on each reconciliation pass, not accumulated.
- Not connected to any diff-of-diffs or version history UI.

### Existing code to reuse

- `core/reconcile.mbt` — `reconcile_children`, `structural_pair`, `try_unmatched_hint_pair`, `assign_fresh_ids`
- `core/projection_memo.mbt` — `build_projection_memos` (reconcile closure entry point)
- `core/reconcile_hints_wbtest.mbt` — TestExpr fixtures, Wrap/Unwrap test trees
- `view_bottom.mbt` — Patch panel entry rendering (`view_patch_log`)

### New code

- `core/diff_event.mbt` — `ReconcileTraceEvent` + `StructuredChange` enums + `Show` impls
- Modifications to `core/projection_memo.mbt` — add `trace_ref` parameter to `build_projection_memos`, pass it to reconciliation
- Modifications to `core/reconcile.mbt` — accept and use `trace_ref` in `reconcile_hinted` / `reconcile_children`, emit events at each decision point
- Modifications to `view_bottom.mbt` — structural diff display in patch entries
