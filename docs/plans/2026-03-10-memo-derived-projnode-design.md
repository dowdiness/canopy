# Design: Memo-Derived ProjNode & CanonicalModel Retirement

**Parent:** [Grand Design §3](./03-unified-editor.md) Phase 2
**Related:** [§5 Tree Edit Roundtrip](./05-tree-edit-roundtrip.md), [TODO §6](../../TODO.md)
**Status:** Approved
**Date:** 2026-03-10

---

## Problem

`SyncEditor` and `CanonicalModel` maintain parallel state that must be manually synchronized. `CanonicalModel` holds AST, node registry, source map, dirty flags, edit history, and a node ID counter — but most of these duplicate state already managed by SyncEditor's CRDT (`OpLog`), undo (`UndoManager`), and parsing (`ReactiveParser`). The `apply_tree_edit` method requires callers to pass both `SyncEditor` and `CanonicalModel`, leaking internal coupling.

## Solution

Move CanonicalModel's useful state (ProjNode, registry, source map, ID counter) into Memo-derived fields on `SyncEditor`. Delete CanonicalModel entirely. Refactor tree edit operations to be functional (no mutation target).

---

## Prerequisites

Two loom/projection API changes are required before the Memo integration:

1. **Expose `ReactiveParser::runtime()`** — `ReactiveParser` creates its own `@incr.Runtime` internally and does not expose it. The new Memos (`proj_memo`, `registry_memo`, `source_map_memo`) must live on the same Runtime to participate in the reactive dependency graph. Either expose `runtime() -> Runtime` or accept an external Runtime at construction time.

2. **Add `derive(Eq)` to `ProjNode`** — `Memo::new` requires `T : Eq`. `ProjNode` currently only derives `Show`. Must add `Eq` (and ensure `@ast.Term` already has `Eq`, which it does). This is a compile-time requirement, not just a backdating optimization.

---

## Data Model

### SyncEditor gains projection fields

```moonbit
pub struct SyncEditor {
  // existing
  priv doc : @text.TextDoc
  priv undo : @undo.UndoManager
  priv parser : @loom.ReactiveParser[@parser.SyntaxNode]
  priv mut cursor : Int

  // new: projection derivation
  priv proj_memo : @incr.Memo[@proj.ProjNode?]
  priv registry_memo : @incr.Memo[Map[@proj.NodeId, @proj.ProjNode]]
  priv source_map_memo : @incr.Memo[@proj.SourceMap]
  priv prev_proj_node : Ref[@proj.ProjNode?]   // side-channel for reconciliation (Ref for closure capture)
  priv next_node_id : Ref[Int]                 // counter for stable IDs (Ref for closure capture)
}
```

### Memo dependency chain

```
source_text (Signal[String])     ← existing in ReactiveParser
    ↓
cst_memo (Memo[CstStage])       ← existing in ReactiveParser
    ↓
proj_memo (Memo[ProjNode?])     ← NEW: CST → ProjNode → reconcile with prev
    ↓
    ├── registry_memo (Memo[Map[NodeId, ProjNode]])  ← NEW: tree traversal
    └── source_map_memo (Memo[SourceMap])              ← NEW: position mapping
```

### CanonicalModel field disposition

| Field | Fate |
|---|---|
| `ast` | → `proj_memo` on SyncEditor |
| `node_registry` | → `registry_memo` on SyncEditor |
| `source_map` | → `source_map_memo` on SyncEditor |
| `next_node_id` | → mutable field on SyncEditor |
| `dirty_projections` | Deleted — Memo auto-tracks |
| `edit_history` | Deleted — tree edits must record into `UndoManager`, not a parallel model-local history |
| `history_position` | Deleted — `UndoManager` is the only undo/redo state |

`CanonicalModel` type and `canonical_model.mbt` are deleted. No remaining consumers.

---

## Public API

### Projection accessors on SyncEditor

```moonbit
pub fn SyncEditor::get_proj_node(self) -> ProjNode?
pub fn SyncEditor::get_source_map(self) -> SourceMap  // cached Memo value
pub fn SyncEditor::get_node(self, id : NodeId) -> ProjNode?
pub fn SyncEditor::node_at_position(self, position : Int) -> NodeId?
pub fn SyncEditor::get_node_range(self, id : NodeId) -> Range?
```

`get_proj_node`, `get_source_map`, `get_node`, `node_at_position`, and `get_node_range` read Memo-owned caches directly. `get_source_map()` returns the cached `source_map_memo` value so external callers do not pay an extra tree walk/sort on every refresh.

### Tree edit signature change

```moonbit
// before:
pub fn SyncEditor::apply_tree_edit(self, canonical : CanonicalModel, op : TreeEditOp) -> Result[Unit, String]

// after:
pub fn SyncEditor::apply_tree_edit(self, op : TreeEditOp, timestamp_ms : Int) -> Result[Unit, String]
```

### TreeEditorState API change

```moonbit
// before:
pub fn TreeEditorState::from_model(model : CanonicalModel) -> TreeEditorState
pub fn TreeEditorState::refresh_from_model(self, model : CanonicalModel) -> TreeEditorState

// after:
pub fn TreeEditorState::from_projection(proj : ProjNode?, source_map : SourceMap) -> TreeEditorState
pub fn TreeEditorState::refresh(self, proj : ProjNode?, source_map : SourceMap) -> TreeEditorState
```

TreeEditorState stays external to SyncEditor — it is purely UI state (selection, collapsed nodes, drag) and not all consumers need it.

---

## Internal Flow

### ProjNode derivation

```
ReactiveParser.cst()                    ← cached CST (Memo)
    ↓
SyntaxNode::from_cst(cst)
    ↓
unwrap_expression_root(syntax_root)
    ↓
syntax_to_proj_node(expr_root, &counter) ← SyntaxNode → ProjNode (positions from CST)
    ↓
reconcile_ast(prev, new_proj, &counter) ← LCS matching (stable node IDs)
    ↓
proj_memo result                        ← ProjNode with stable IDs + accurate positions
```

Goes CST → SyntaxNode → ProjNode directly, skipping Term → unparse → reparse. The ReactiveParser's cached CST provides incremental parsing; `syntax_to_proj_node` provides position-preserving conversion, but it must still receive the unwrapped expression root just like `parse_to_proj_node` does today.

### Reconciliation state (side-channel approach)

The Memo compute function closes over SyncEditor, reads `prev_proj_node` (untracked), reconciles, and updates it as a side effect. Tree edits may also seed `prev_proj_node` with the structurally edited `ProjNode` before committing text, so the next reparse reconciles against the edit result instead of the pre-edit tree. The impurity is benign — it only stores state for the next computation. Requires single-threaded Runtime evaluation (current guarantee).

```moonbit
let proj_memo = @incr.Memo::new(rt, fn() {
  let cst_stage = parser.cst()
  let syntax_root = @seam.SyntaxNode::from_cst(cst_stage.cst)
  let expr_root = @proj.unwrap_expression_root(syntax_root)
  let counter = Ref::new(next_node_id)
  let new_proj = @proj.syntax_to_proj_node(expr_root, counter)
  let reconciled = match prev_proj_node {
    None => new_proj
    Some(prev) => @proj.reconcile_ast(prev, new_proj, counter)
  }
  next_node_id = counter.val
  prev_proj_node = Some(reconciled)
  Some(reconciled)
})
```

### reconcile_ast signature change

```moonbit
// before (CanonicalModel for ID generation + registry cleanup):
fn reconcile_ast(old: ProjNode, new: ProjNode, model: CanonicalModel) -> ProjNode

// after (counter only — registry is derived, no cleanup needed):
pub fn reconcile_ast(old: ProjNode, new: ProjNode, counter: Ref[Int]) -> ProjNode
```

Same for helpers:

```moonbit
// assign_fresh_ids: CanonicalModel → Ref[Int]
fn assign_fresh_ids(node: ProjNode, counter: Ref[Int]) -> ProjNode

// reconcile_children: CanonicalModel → Ref[Int]
fn reconcile_children(old: Array[ProjNode], new: Array[ProjNode], counter: Ref[Int]) -> Array[ProjNode]
```

The `unregister_node_tree_from_model` calls in `reconcile_children` are removed — the registry is fully derived by `registry_memo`, so cleanup is unnecessary. The `unregister_node_tree_from_model` calls in `CanonicalModel::apply_operation` disappear with the type deletion.

### apply_tree_edit flow

```
1. proj = self.get_proj_node()                    // current ProjNode from Memo
2. new_proj = apply_edit_to_proj(proj, op, ...)   // functional structural edit
3. new_text = @ast.print_term(new_proj.kind)      // unparse
4. self.seed_proj_node(Some(new_proj))            // seed reconcile baseline with edit result
5. self.set_text_and_record(new_text, timestamp_ms) // CRDT ops + UndoManager history
6. // Memo chain reparses text and reconciles against seeded new_proj
```

### Parse errors

If the CST has errors, `syntax_to_proj_node` produces `Error(...)` nodes. Reconciliation still works — `Error` nodes get fresh IDs. This matches current behavior.

---

## Projection Package Refactoring

### Functions that stay

| Function | Change |
|---|---|
| `parse_to_proj_node(text)` | No change — standalone parser wrapper |
| `reconcile_ast(old, new, counter)` | **Extracted, made pub** — `Ref[Int]` replaces `CanonicalModel` |
| `syntax_to_proj_node(node, counter)` | **Made pub** — used by SyncEditor's Memo |
| `unwrap_expression_root(node)` | **Made pub** — SyncEditor's Memo must mirror `parse_to_proj_node` root handling |
| `SourceMap::new/rebuild/get_range/innermost_node_at` | No change |
| `ProjNode::new(...)` | No change |

### Functions that change

| Before | After |
|---|---|
| `text_lens_get(CanonicalModel)` | Deleted — callers use `@ast.print_term(proj.kind)` directly |
| `text_lens_put(CanonicalModel, String)` | Deleted — logic split into `syntax_to_proj_node` + `reconcile_ast` in Memo |
| `tree_lens_apply_edit(CanonicalModel, TreeEditOp)` | → `apply_edit_to_proj(ProjNode, TreeEditOp, Map[NodeId, ProjNode], Ref[Int]) -> Result[ProjNode, String]` |
| `tree_lens_get/tree_lens_put` | Deleted — trivial CanonicalModel wrappers |

### Helper functions migrated to standalone

These functions currently live as methods on `CanonicalModel` or as helpers in `canonical_model.mbt`. They are refactored into free functions (or `ProjNode` methods) in `tree_lens.mbt`, since they serve the tree edit logic:

| Function | Current location | New form |
|---|---|---|
| `update_node_in_tree(root, target_id, new_node)` | `canonical_model.mbt` | Free function in `tree_lens.mbt` (already pure) |
| `remove_child_at(node, index)` | `canonical_model.mbt` | Free function in `tree_lens.mbt` (already pure) |
| `insert_child_at(node, index, child)` | `canonical_model.mbt` | Free function in `tree_lens.mbt` (already pure) |
| `get_node_in_tree(root, target_id)` | `canonical_model.mbt` | Free function in `tree_lens.mbt` (already pure) |
| `find_parent_recursive(node, target_id)` | `canonical_model.mbt` | Free function in `tree_lens.mbt` (already pure) |

`apply_edit_to_proj` reimplements the logic of `CanonicalModel::apply_operation` using these free functions plus the `Map[NodeId, ProjNode]` registry for lookups (replacing `CanonicalModel::get_node`). The `find_parent` lookup uses `find_parent_recursive` on the ProjNode tree directly instead of going through the model.

### Files deleted

| File | Reason |
|---|---|
| `canonical_model.mbt` | Type retired |
| `canonical_model_wbtest.mbt` | Tests rewritten against functional APIs |
| `lens.mbt` | `Lens[M,P]` / `LensDiff[M,P,E]` only used by CanonicalModel lenses |

---

## Testing

### Tests that change

| Test file | Change |
|---|---|
| `editor/tree_edit_bridge_test.mbt` | Remove CanonicalModel from setup. Use `editor.get_proj_node()` for node IDs. |
| `projection/lens_test.mbt` | Test functional APIs (`reconcile_ast` with counter, `apply_edit_to_proj`) |
| `projection/tree_editor_wbtest.mbt` | `from_model` → `from_projection` |
| `projection/text_lens_regression_wbtest.mbt` | Test `reconcile_ast` directly |

### New tests

| Test | Verifies |
|---|---|
| `get_proj_node` basic | Text → ProjNode derivation via Memo chain |
| `get_proj_node` caching | Same node IDs when called twice without text change |
| `get_proj_node` after edit | Node ID preservation for unchanged subtrees |
| `get_source_map` accuracy | Node positions match text ranges |
| `get_node` / `node_at_position` | Registry and source map derived correctly |
| `apply_tree_edit` without CanonicalModel | Same 10 roundtrip tests, simplified setup |
| `apply_tree_edit` undo/redo | Tree edits are recorded in `UndoManager`, not lost |
| `apply_tree_edit` seeded reconciliation | Structural edits preserve intended node IDs after memo reparse |
| `apply_edit_to_proj` unit tests | Each TreeEditOp variant |

---

## Migration Order

Steps 0a-0b are loom/projection prerequisites. Steps 1-4 are additive (no breakage). Steps 5-8 are breaking but all in-repo.

0a. **Prerequisite:** Expose `ReactiveParser::runtime()` in loom (or accept external Runtime)
0b. **Prerequisite:** Add `derive(Eq)` to `ProjNode`
1. Refactor `reconcile_ast`, `reconcile_children`, `assign_fresh_ids` to take `Ref[Int]` instead of `CanonicalModel`
2. Expose `syntax_to_proj_node` and `unwrap_expression_root` as pub
3. Add Memo fields + projection accessors to SyncEditor
4. Add `apply_edit_to_proj` functional API (migrate helper functions from `canonical_model.mbt` to `tree_lens.mbt`)
5. Update `apply_tree_edit` signature to take `timestamp_ms` and record into `UndoManager` (breaking — update bridge tests simultaneously)
6. Update `TreeEditorState` API (breaking — update tree editor tests simultaneously)
7. Update Rabbita example:
   - Remove `canonical : @proj.CanonicalModel` from `Model` struct
   - Remove `text_lens_put(canonical, text)` calls — `editor.set_text(text)` is sufficient
   - Replace `TreeEditorState::from_model(canonical)` with `TreeEditorState::from_projection(editor.get_proj_node(), editor.get_source_map())`
   - Replace `tree_state.refresh_from_model(canonical)` with `tree_state.refresh(editor.get_proj_node(), editor.get_source_map())`
   - Replace `editor.apply_tree_edit(canonical, op)` with `editor.apply_tree_edit(op, timestamp_ms)`
   - Replace `canonical.get_errors()` with `editor.get_errors()` (already delegates to ReactiveParser diagnostics)
8. Delete `CanonicalModel`, `canonical_model_wbtest.mbt`, `lens.mbt`, old lens functions, old tests

---

## Risks

- **Double reconciliation on tree edits:** `set_text_and_record` triggers Memo chain reparse+reconcile, but the structural edit already produced a correct ProjNode. The reconciliation should preserve IDs via LCS. Acceptable for lambda calculus scale; consistent with current double-parse (TODO.md §6).
- **Memo[ProjNode?] Eq requirement:** `ProjNode` must derive `Eq` for `Memo::new` to compile (see Prerequisites). Positions always change on text edits, so backdating won't fire — downstream Memos always recompute. This is fine.
- **Memo-owned `SourceMap` is mutable:** `get_source_map()` now returns the cached `source_map_memo` object directly for performance. Callers must treat it as read-only; mutating it via `SourceMap::apply_edit` / `rebuild` can corrupt the cache seen by later readers.
- **SyncEditor ↔ projection dependency deepens:** Already exists (`editor/moon.pkg.json` imports projection). No new package dependency, just more usage surface.
