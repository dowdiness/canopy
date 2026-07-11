# Lazy & Incremental Tree Refresh

**Date:** 2026-03-20
**Status:** Complete
**Scope:** `projection/tree_editor.mbt` — `TreeEditorState::refresh` optimization

---

## Problem

`TreeEditorState::refresh()` performs 4 O(n) passes on every projection change, even for a single-character edit:

1. **`build_loaded_node_index(self.tree)`** — walks the entire old interactive tree to build a `Map[NodeId, InteractiveTreeNode]`. Redundant: `self.loaded_nodes` already holds the same data.
2. **`refresh_node_with_reuse_impl`** — walks the entire new ProjNode tree to build the new interactive tree plus all structural indexes (`preorder_ids`, `parent_by_child`, `preorder_range_by_root`).
3. **`valid_ids` → HashSet** — converts the full ID array to a HashSet for stale UI pruning.
4. **Stale UI pruning** — intersects `collapsed_nodes`, filters `selection`, `editing_node`, `dragging`, `drop_target`.

The structural indexes (pass 2) are only consumed by rare tree operations (Delete, DragOver, Drop, SelectRange). They are never needed during typing.

### Consumer Analysis

| Index | Consumers | When needed |
|-------|-----------|-------------|
| `loaded_nodes` | `get_loaded_node`, `apply_edit`, `hydrate_subtree`, stamp comparison in next refresh | Always |
| `preorder_ids` + `preorder_range_by_root` | `collect_subtree_ids` (Delete, hydrate), `collect_nodes_in_range` (SelectRange) | Tree operations only |
| `parent_by_child` | `is_descendant_of` (DragOver, Drop), `hydrate_subtree` (Expand) | Tree operations (drag-and-drop + expand) |
| `valid_ids` | Stale UI pruning of `selection`, `editing_node`, `dragging`, `drop_target` | Refresh only — can be derived from `loaded_nodes.keys()` instead of separate array |

---

## Design

### Principles

1. **Don't compute what you don't need.** Structural indexes are irrelevant during typing.
2. **Maintain, don't rebuild.** `loaded_nodes` should be carried across refreshes, not thrown away and rebuilt.
3. **Use the tree as the index.** The `InteractiveTreeNode` tree encodes parent-child relationships. Don't duplicate them eagerly.
4. **Prune selectively.** Stale entries in `collapsed_nodes` (immutable HashSet, used only for `contains` checks) are harmless. But `selection` (Array, iterable/countable), `editing_node`, `dragging`, and `drop_target` (all `NodeId?`) must be pruned to avoid inflated counts or stranded UI state. Derive valid IDs from `loaded_nodes.keys()` instead of building a separate `valid_ids` array.

### Architecture

Split indexes into two categories:

**Always maintained:**
- `loaded_nodes: Map[NodeId, InteractiveTreeNode]` — carried across refreshes, never rebuilt from scratch.

**Lazy (built on first access, invalidated on tree change):**
- `cached_parent_map: Map[NodeId, NodeId]?` — built when `is_descendant_of` is first called.
- `cached_preorder: LazyPreorder?` — built when `collect_subtree_ids` or `collect_nodes_in_range` is first called.

These are plain `Option` fields, **not `Ref`**. `TreeEditorState` is used as an immutable value type — every operation returns a new struct via `{ ..self, ... }`. Using `Ref` would cause old and new state snapshots to share the same mutable cache, silently corrupting cached values when old states are accessed (e.g., for undo, comparison, or React concurrent mode). With plain `Option`, each state snapshot owns its own cache independently.

```
TreeEditorState {
  tree: InteractiveTreeNode?
  loaded_nodes: Map[NodeId, InteractiveTreeNode]

  // UI state (unchanged)
  selection, collapsed_nodes, editing_node, ...

  // Lazy structural indexes (plain Option, not Ref)
  priv cached_parent_map: Map[NodeId, NodeId]?
  priv cached_preorder: LazyPreorder?
}

struct LazyPreorder {
  ids: Array[NodeId]
  range_by_root: Map[NodeId, (Int, Int)]
}
```

**Invalidation rule:** Any operation that changes `tree` sets both cached fields to `None` in the returned struct. Operations that only change UI state on existing nodes (Select, Collapse, Expand) carry over the cached values — the structural shape hasn't changed.

**Stale UI pruning:** Eliminated for `collapsed_nodes` (immutable HashSet, stale entries are harmless). Retained for `selection`, `editing_node`, `dragging`, `drop_target`, and `drop_position` — these are observable (iterable/countable) and stale entries would cause inflated counts or stranded UI state. The pruning uses `loaded_nodes.get(id)` checks instead of building a separate `valid_ids` HashSet, avoiding the O(n) array-to-HashSet conversion.

**Lazy getter pattern:** Since `TreeEditorState` is an immutable value type, getters that populate lazy caches must return a new state alongside the result. Callers that need structural indexes call the getter and use the returned (potentially updated) state going forward. Alternatively, the lazy computation can be done eagerly at the call site (e.g., `build_parent_map_from_tree` called inline in `is_descendant_of`) if the result doesn't need to be cached across calls — for one-off operations like a single drag validation, this is simpler.

---

## Phase 1: Lazy Indexes

### Refresh Algorithm

**Current (4 O(n) passes):**
1. `build_loaded_node_index(self.tree)` — O(n)
2. `refresh_node_with_reuse_impl` — O(n), builds tree + all indexes
3. `valid_ids` → HashSet — O(n)
4. Stale UI pruning — O(n)

**New (1 O(n) pass + lightweight pruning):**
1. Walk new ProjNode tree, stamp-compare against `self.loaded_nodes` directly, build new `InteractiveTreeNode` tree + new `loaded_nodes`. No structural indexes, no `valid_ids` array.
2. Prune `selection`, `editing_node`, `dragging`, `drop_target`, `drop_position` using `new_loaded_nodes.get(id)` checks — O(selection_size + constant), not O(n).
3. Return new state with `cached_parent_map = None`, `cached_preorder = None`.

### Simplified `refresh_node_with_reuse_impl`

Remove parameters:
- `valid_ids: Array[NodeId]` — no longer collected
- `indexes: TreeStructureIndexes` — no longer populated
- `parent_id: NodeId?` — no longer tracking

Remove internal bookkeeping:
- `preorder_ids.push(node_id)` — gone
- `parent_by_child[node_id] = parent_id` — gone
- `preorder_range_by_root[node_id] = (start, end)` — gone

Only output: `InteractiveTreeNode` + entries in new `loaded_nodes` map.

For collapsed subtrees, `record_projection_subtree` simplifies to just counting descendants (for `Elided(count)`) without any index bookkeeping.

### Lazy Index Access

Since `TreeEditorState` is an immutable value type, lazy caches cannot be mutated in place. Two strategies, used depending on context:

**Strategy A: Compute inline (for one-off operations).** Call `build_parent_map_from_tree(self.tree)` or `build_preorder_from_tree(self.tree)` directly at the call site. Simple, no caching overhead. Best for operations that happen once per user interaction (e.g., a single drag validation).

**Strategy B: Cache and return updated state (for repeated access).** Return `(result, updated_state)` from the getter. The caller uses the updated state going forward. Best when multiple operations in the same handler need the same index.

```moonbit
fn TreeEditorState::ensure_parent_map(self) -> (Map[NodeId, NodeId], TreeEditorState) {
  match self.cached_parent_map {
    Some(map) => (map, self)
    None => {
      let map = build_parent_map_from_tree(self.tree)
      (map, { ..self, cached_parent_map: Some(map) })
    }
  }
}
```

In practice, most consumers are internal functions called once per user action, so Strategy A (inline computation) is simpler and sufficient. Strategy B is available for hot paths if profiling shows repeated index construction.

Consumers change from direct field access to function calls:
- `collect_subtree_ids` → calls `build_preorder_from_tree` or `self.ensure_preorder()`
- `is_descendant_of` → calls `build_parent_map_from_tree` or `self.ensure_parent_map()`
- `collect_nodes_in_range` → calls `build_preorder_from_tree` or `self.ensure_preorder()`
- `hydrate_subtree` → calls `build_parent_map_from_tree` for parent lookup

### `apply_selection_edit` Fix

Current: `build_loaded_node_index(Some(updated))` — full O(n) rebuild after selection change.

New: Patch only the changed nodes. `apply_selection_to_node` currently returns `(InteractiveTreeNode, Bool)` — it needs to be extended to also return a changed-path array (like `update_node_collapsed` already does). Then use `update_loaded_nodes_for_path` (which already exists) instead of `build_loaded_node_index`.

This requires modifying `apply_selection_to_node` to return `(InteractiveTreeNode, Bool, Array[InteractiveTreeNode])` — matching the pattern already used by `update_node_collapsed` and `replace_loaded_subtree_node`.

---

## Phase 2: Subtree Skip

Phase 1 reduces refresh from 4 passes to 1, but that 1 pass still visits every ProjNode. Phase 2 skips unchanged subtrees entirely.

### Mechanism

Before descending into a ProjNode's children during refresh, check if the entire subtree can be reused:

```moonbit
fn can_reuse_subtree(proj_node, prev_node, ui_state) -> Bool {
  // 1. Previous node exists with same ID (guaranteed by lookup)
  // 2. Same kind shape (Int value, Var name, etc.)
  // 3. UI state unchanged (collapsed, selected, editing, drop_target)
  // 4. Children count matches AND every child's ProjNode.node_id
  //    matches the corresponding previous InteractiveTreeNode.id
}
```

If all checks pass: reuse the previous `InteractiveTreeNode`, carry over all its `loaded_nodes` entries by walking the reused subtree, skip recursion into children.

### Why This Is Safe

`reconcile_ast` preserves `node_id` only when the kind matches (`same_kind_tag`). If a ProjNode has the same ID as before AND its children all have matching IDs, the subtree structure is identical to last time. UI state is checked explicitly.

### Performance Impact

An 80-def program where the user edits one def: FlatProj's LCS tells us 79 defs are unchanged. Phase 2 skips stamp comparison and node construction for all 79, visiting only the 1 changed def's subtree for full processing. The reused subtrees still incur O(subtree_size) `loaded_nodes` map insertions for carry-over, but this is a simple map copy with no stamp comparison, no UI state lookup, and no allocation of new `InteractiveTreeNode` structs.

Net cost: O(total_nodes) map insertions (carry-over) + O(changed_def_depth) full processing. The constant factor for carry-over is much lower than full refresh processing.

### Loaded Nodes Carry-Over

When reusing a subtree, walk the reused `InteractiveTreeNode` to copy its entries into the new `loaded_nodes` map. This is O(subtree_size) but avoids stamp comparison overhead and has no allocation beyond map insertions. For typical unchanged defs (3-5 nodes deep), this is negligible.

---

## Impact Summary

| Scenario | Current | Phase 1 | Phase 2 |
|----------|---------|---------|---------|
| Type 1 char in 80-def program | 4 x O(n) | 1 x O(n) lightweight | O(n) map carry-over + O(changed_def) full processing |
| SelectRange | O(n) eager | O(n) lazy, one-time | O(n) lazy, one-time |
| Delete node | O(n) eager | O(subtree) lazy preorder | O(subtree) |
| Drag validation | O(n) eager | O(depth) lazy parent walk | O(depth) |
| Select node | O(n) loaded_nodes rebuild | O(changed_path) patch | O(changed_path) patch |

---

## Testing Strategy

1. **Behavioral equivalence** — All existing `tree_editor_wbtest.mbt` tests pass, with one expected change: the `"refresh prunes stale ids from UI state"` test assertion for `collapsed_nodes` must change from `content="false"` to `content="true"` since stale `collapsed_nodes` entries are no longer pruned. All other assertions in that test (selection, editing_node, dragging, drop_target, drop_position) remain unchanged — those fields are still pruned.
2. **Reuse verification** — New whitebox tests verify:
   - Refresh after single-char edit reuses unchanged subtrees (Phase 2)
   - Lazy indexes are `None` after refresh, populated after first tree operation
   - Stale `collapsed_nodes` entries persist harmlessly after refresh
3. **Benchmark comparison** — Use existing `BenchmarkSession::deferred_full_cycle_timed()` to measure `tree_refresh_ms` phase before and after, on 20-def and 80-def programs.
4. **No new dependencies** — pure refactor of `projection/tree_editor.mbt`.

---

## Files Changed

| File | Change |
|------|--------|
| `projection/tree_editor.mbt` | All changes — struct fields, refresh algorithm, lazy getters, subtree skip, selection fix |
| `projection/tree_editor_wbtest.mbt` | New tests for reuse verification, lazy index behavior, stale ID tolerance |
| `projection/pkg.generated.mbti` | `moon info` regeneration (struct field changes) |

---

## Non-Goals

- Incremental structural index patching (would add complexity for marginal gain over lazy)
- Memo-derived interactive tree (would require deeper architectural change to Signal/Memo pipeline)
- Rabbita VDOM diff optimization (separate concern, downstream of this change)
