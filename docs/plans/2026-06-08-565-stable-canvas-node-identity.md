# #565 — Stable source-backed canvas node identity

## Problem

Current behavior is driven by a dual-identity model: positional node IDs in the canvas model coexist with source-layer reparsing and a separate binding-recovery shim. The canvas ID path is currently created from indices (for example `NodeId(index + 1)`) while source-side remapping relies on binding maps (`examples/canvas/main/graph_dsl_adapter.mbt:170-176`, `:240-246`, `:226-230`). That split makes selection/inspector/action IDs fragile when ordering changes because the canonical tracker authority is not consistently used end-to-end (`examples/canvas/main/graph_dsl_adapter.mbt:551-605`, `:623-641`, `:901-930`).  

`GraphNode::id()` is not unstable in a clean delete; observed churn appears when the reparse path is coarse-grained (atomic whole-source or atomic replace semantics). The Loom `ProjectionIdentityTracker` keeps IDs stable by edit-window realignment of positional changes, with fresh allocation only when the edit crosses its continuity guarantees (`loom/loom/src/core/projection_identity.mbt:625-631`, `:657-667`, `:710-759`, `:815-824`).

## Empirical findings (proven 2026-06-08)

Keep this table as the behavioral ground truth:

| Reparse/repair path | `GraphNode::id()` behavior |
|---|---|
| Whole-source `set_source` reorder (atomic) | `node#0:x` and `node#1:x` swap (id churn) |
| `apply_edit` atomic replace spanning move | `node#0:x` and `node#1:x` swap (id churn) |
| `apply_edit` delete-then-insert per edit | id for surviving moved node remains stable |
| Clean delete / localized param edit | previously existing ids remain stable |

The row above is consistent with `GraphNode::id()` being token-based binding identity plus the tracker’s realignment behavior (`loom/loom/src/core/projection_identity.mbt:531-560`, `:565-588`, `:625-631`, `:657-667`, `:710-759`, `:815-824`).  

`projection.mbt` currently enforces duplicate-binding rejection for the grammar source, which remains a hard prerequisite if identity is keyed to tracker tokens (`loom/examples/graph-dsl/src/projection.mbt:283-292`).

## Constraints

1. `NodeId/EdgeId` are shared model primitives with JSON contracts and are currently `pub(all) struct Int` wrappers in `lib/canvas-graph/graph_model/model.mbt:6,38`. Codec paths currently serialize numeric identifiers (`lib/canvas-graph/graph_model/model.mbt:25-35`, `:55-65`, `:57-67`, `:174-183`, `:288-329`).  

2. The source panel currently exposes a whole-document path: `EditorChanged(String)` is fed through `set_source_graph_source_checked` and `attachment.set_source` (`examples/canvas/main/source_demo.mbt:42-43`, `:101-107`, `:192-203`), with parse/reparse paths that are coarse and can trigger churn (`examples/canvas/main/graph_dsl_adapter.mbt:901-929`).  

3. Duplicate-binding rejection is present in the source projection and is non-negotiable for token identity correctness (`loom/examples/graph-dsl/src/projection.mbt:283-292`).  

4. Rabbitita binding direction says reusable bindings should expose subscription-shaped APIs via `@sub` (rather than raw FFI consumption), with payload-tagging semantics and stable subscription keys (`rabbita/rabbita/sub/design.md:1-77`, `rabbita/doc/using_subscriptions/readme.mbt.md:1-155`, `rabbita/rabbita/websocket/listen.mbt:1-117`). The existing `lib/rabbita_codemirror/codemirror.mbt:634-652` listen signature currently emits whole-doc only, so extension must occur in the binding layer.

## Design

### Layer 1 — Identity as a String

Collapse identity to a single authority: Loom `ProjectionIdentityTracker` tokens (`GraphNode::id()`), with `NodeId` moved to `String` and no registry/binding-recovery layer.

- `NodeId` is a `String` equal to `GraphNode::id()` from the tracker, and is the only cross-frame identity for nodes (`loom/examples/graph-dsl/src/graph_doc.mbt:171-205`).
- `EdgeId` is derived deterministically from `(source_node_id, target_node_id, target_port)`; there is no mutable `Int` allocator for edges and no global edge registry.  
- Delete all intern-table/recovery behavior, because identity is now intrinsic in tokens and does not need remapping from a secondary map.

This replaces current positional minting (`NodeId(index + 1)`) in canvas projection and source adapter (`examples/canvas/main/graph_dsl_adapter.mbt:170-176`, `:226-230`, `:240-246`) and aligns JS/TS payload surfaces with the shared model’s adapter contract.

Because ID is now tracker-owned:
- `examples/canvas/main/canvas_init.mbt` must produce string IDs from pointer events for the hand-built canvas (`examples/canvas/main/canvas_init.mbt:1-32`).
- `examples/canvas/web/src/graph-adapter.ts` should carry opaque string handles in source-backed operations and pointer data attributes.

Rename behavior: rename churn is expected in the tracker (`GraphNode::id()` token changes), so a local hook is required to rewrite selection/inspector/action references from old NodeId to new NodeId inside the canvas operation path. The existing precedent is `rename_layout_binding` (`examples/canvas/main/graph_dsl_adapter.mbt:608-620`). This is a rename-specific continuation step, not binding-recovery.

### Layer 2 — Feed the tracker edits (delta editor)

Canvas source editing must provide per-change deltas into the tracker:
- Current canvas demos already have CM6 plumbing that produces ordered changes (`examples/ideal/web/src/cm-inline.ts:20-27`, `examples/ideal/web/src/leaf-editor.ts:37-38`, `examples/ideal/web/src/bridge.ts:68`, `examples/ideal/web/src/bridge.ts:155-186`) and maps to `@core.Edit` (`examples/ideal/main/crdt_reexport.mbt:171-181`, `editor/sync_editor_text.mbt:323-339`).
- `lib/rabbita_codemirror/codemirror.mbt:634-652` currently emits only whole-doc deltas, so we must extend the binding to expose structured `{from, to, insert}` edit payloads through `listen`.  

Binding implementation requirements:
- Follow canonical Sub-binding pattern in `rabbita/rabbita/websocket/listen.mbt` (private `suberror`, `let mut tagger`, `update_tagger`, function-based API, and key that tracks presence only, not tagger identity) (`rabbita/rabbita/websocket/listen.mbt:1-117`).
- Match subscription invariants from `rabbita/doc/using_subscriptions/readme.mbt.md` and `rabbita/rabbita/sub/design.md` (`rabbita/doc/using_subscriptions/readme.mbt.md:1-155`, `rabbita/rabbita/sub/design.md:1-77`).
- JS side consumes `update.changes.iterChanges()`, maps to `@core.Edit.new(start, old_len, new_len)` equivalents, and emits per-change callbacks.

Operationally, `Canvas` source panel should call `apply_edit` for each change sequentially (a CM6 transaction may contain multiple changes; applying in order preserves moved-node stability), and rely on whole-source `set_source` only for initialization/programmatic resets.

### Layer 3 — Retire now-dead selection remap plumbing

With token identities and change-based feeding, the previous central remap utilities are no longer required:
- `source_selected_node_bindings`
- `source_selection_from_bindings`
- `remap_selection_to_bindings`
- `sync_local_operation_state` remap arm for delete
- `set_source_graph_source_checked` capture/replay block

Current source-side call points:
- `graph_dsl_adapter.mbt` remap utilities and capture blocks (`:551-605`, `:623-641`, `:901-930`).
- `sync_local_operation_state` path in local operation handling (`:1064-1080`) currently carries delete remap behavior that becomes dead code under Layer 1+2.

This closes #565 and makes #566 obsolete because identity restoration is intrinsic rather than reconstructed.

## Implementation staging

The two architectural axes remain separable:

1. **Option A — Land both together:** implement String identity and delta-editor in one PR so selection/inspector stability is guaranteed in reorder scenarios.
2. **Option B — Identity-first with transitional bridge:** keep existing whole-source `set_source` during rollout by converting old->new source into edits or retaining a temporary, explicitly marked recovery bridge; delete that bridge once Layer 2 lands.

Both options preserve the empirical constraint that source-backed tests relying on binding-preserved reorder semantics only fully pass when granular edits are active.

## Residual limitations

Single transaction atomic replace that reorders multiple nodes can still churn IDs under Layer 1 if it is not expressed as granular edits; this is currently the same fundamental boundary as Loom’s token allocator behavior when the edit window no longer provides continuity (`loom/loom/src/core/projection_identity.mbt:625-631`, `:657-667`, `:710-759`, `:815-824`).  

A future bulk formatter command emitting one large replace must be sequenced as granular deltas to avoid broader churn; this is an editor pipeline choice, not a model fault.  

Multi-selects spanning churned nodes still degrade to fresh identities on the affected nodes in those atomic paths, with unaffected nodes and unrelated references retaining identity stability.

## Test plan (failing-first)

All listed tests remain source-backed design-level checks; assertions migrate to string IDs where currently numeric.

- Selection/inspector survive delta-driven source reorder with no remap call (`examples/canvas/main/graph_dsl_adapter_wbtest.mbt:493`).
- Selection survives delete of an earlier node and does not remap via binding helpers (`examples/canvas/main/graph_dsl_adapter_wbtest.mbt:441-490`).
- A node keeps identity across unrelated parameter edits (`loom/loom/src/core/projection_identity.mbt` behavior + `examples/canvas/main/graph_dsl_adapter_wbtest.mbt` existing reorder/delete probes).
- New node IDs are never reused; deleted node IDs are never resurfaced.
- Rename preserves identity through the rename-local hook (`examples/canvas/main/graph_dsl_adapter.mbt:608-620`).
- Existing source-backed wbtests continue: clear/delete/multi-select order/invalid-source no-remap (`examples/canvas/main/graph_dsl_adapter_wbtest.mbt:441-490`, `:529-543`, `:564-607`).

Additional structural checks:
- `lib/canvas-graph/graph_model/model.mbt:25-35`, `:55-65`, `:288-329` updated to string JSON handling without semantic downgrade.
- `examples/canvas/web/src/graph-adapter.ts` pointer and payload paths updated to opaque string IDs.
- `lib/rabbita_codemirror/codemirror.mbt` and JS binding layer accept and emit structured deltas with suberror-safe callback semantics.

## Open questions

1. Should the string-ID migration include an explicit one-time wire version marker for persisted handles from older numeric IDs?  
2. Should the delta path in Canvas be switched atomically across the whole source-edit surface or behind a feature flag until all dependent adapters are migrated?  
3. For `GraphAttachment::apply_edit`, should retries/reconciliation tolerate JS listener dropouts by falling back to `set_source` and accepting one-time churn windows?

## PR2 execution addendum (validated 2026-06-09)

Empirical re-validation (whitebox probe on `GraphAttachment`, since removed) refined
the design and answered the open questions. Token format is
`"node#<occurrence>:<binding>"` (e.g. `node#0:osc`), and the tracker realigns ids by
content on every reparse — including whole-source `set_source`. Measured:

| Path | Survivor/target token |
|---|---|
| `set_source` delete of a *different* binding line | **STABLE** (`node#0:reverb` unchanged) |
| `apply_edit` (delta) delete of a different binding line | **STABLE** |
| `set_source` *reorder* (swap two bindings) | **CHURNS** (`node#0:osc` → `node#1:osc`) |

Consequences for PR2:

- **No delete-to-delta conversion.** Survivor tokens are stable under the existing
  whole-source delete path, so `source_delete_lowering` may keep emitting
  `WholeSourceReplacement`. Selection over a survivor stays valid with **no remap**.
- **Layer 3 (retire the binding-recovery shim) is correct for delete + param-edit +
  editor-driven reorder.** A CM6 reorder is a delta delete+insert pair (stable per the
  empirical table), so editor reorders preserve identity without remap.
- **`set_source` becomes reset/init-only.** The one residual churn case is an atomic
  `set_source` reorder — now a programmatic-reset path, not a user gesture. The old
  `graph_dsl_adapter_wbtest.mbt` "reorder via `set_source` preserves selection by binding"
  cases (currently asserting positional remap) are rewritten: editor-delta reorders assert
  identity preservation; any remaining `set_source` reorder asserts the residual
  (selection cleared/dropped on churn), not remap.
- **Rename** changes the token (binding is embedded), so a rename-local continuation hook
  rewrites live `interaction` selection old-token → new-token (replacing today's
  `rename_layout_binding`, which stays for binding-keyed layout). `action_log` keeps the
  old token as a historical record — it is display-only (TS `JSON.parse`s it, never
  replays it against the tracker), so no rewrite there.
- **EdgeId** is derived from the 4-tuple `(source_token, source_port, target_token,
  target_port)` (source_port included so multi-output nodes don't collide). No allocator,
  no `next_edge_id`. Derived ids are consistent within a render; on rename an endpoint
  token change re-derives the edge id for one render cycle (acceptable; disconnect
  hit-tests within the current render).
- **`next_node_id : Int`** is kept only as the hand-built (non-source) canvas mint counter
  (`NodeId(next_node_id.to_string())`); source-backed and hand-built ids never share a
  `CanvasState`, so no collision.
- **Open Q1: bump `GRAPH_OPERATION_VERSION` 1→2 (no compat decode path).** No persisted
  numeric-id JSON exists to migrate (no `localStorage`; `action_log` is in-memory per
  session, read-out-only, never replayed into `apply_source_graph_operation`), so a
  numeric-accepting decode path is unwarranted and would re-introduce the int/token
  ambiguity this PR removes. But `from_json` gates on `version == GRAPH_OPERATION_VERSION`,
  so leaving the format-defining marker at 1 while the NodeId wire encoding changed
  (number→string) would make "v1" denote two incompatible formats. Bumping to 2 keeps the
  marker honest: any pre-bump payload is rejected with a clear `unsupported version 1`
  rather than a confusing `expected string`. TS producers and serialization snapshots move
  to 2 in lockstep. Test fixtures migrate to string ids.
- **Lookup:** loom gains `GraphDoc::find_node_by_id(String)` (landed in a loom PR; canopy
  loom pin bumped). `graph_node_for_canvas_id` resolves via it instead of `nodes[raw-1]`.
- **Layer 3 mechanism = prune-by-token-existence, not pure deletion.** The binding-capture/
  replay helpers (`source_selected_node_bindings`, `source_selection_from_bindings`,
  `remap_selection_to_bindings`, and the `set_source`/`apply_codemirror_changes`/delete
  capture blocks) are deleted and replaced by a single `prune_selection_to_doc(doc)`:
  after every reparse, filter `interaction.selected_nodes` to tokens that still resolve via
  `doc.find_node_by_id`, recompute `selected` as the first survivor (else `None`), reset the
  drag preview. This is token-existence filtering, not binding re-resolution: survivors keep
  their stable tokens (so selection persists with no mapping), deleted/churned tokens drop
  out naturally. `realized_source_operation` is *kept* (it stamps the logged `AddNode` with
  the new node's real token via `canvas_id_for_binding`) — it is log realization, not
  selection recovery, so it is out of the shim's scope.
- **FFI node-id params become `String`.** All pointer/hover entry points
  (`source_graph_pointer_down/up`, hand-built `pointer_down`, `canvas_init` handlers) take a
  `String` node id; the `node_id <= 0` "none" sentinel becomes the empty string `""`.
- **Rename selection hook:** in `sync_local_operation_state`'s `RenameNode` arm, in addition
  to `rename_layout_binding` (binding-keyed layout, kept), rewrite any occurrence of the
  renamed node's *old* token in `interaction.selected`/`selected_nodes` to its *new* token
  (old token from `old_doc` by binding; new token from `new_doc.find_node(new_binding).id()`).
