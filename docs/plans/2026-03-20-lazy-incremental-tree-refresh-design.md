# Lazy & Incremental Tree Refresh

**Date:** 2026-03-20
**Status:** Design approved
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
| `parent_by_child` | `is_descendant_of` (DragOver, Drop), `hydrate_subtree` | Drag-and-drop only |
| `valid_ids` | Stale UI pruning | Never needed — stale entries are harmless |

---

## Design

### Principles

1. **Don't compute what you don't need.** Structural indexes are irrelevant during typing.
2. **Maintain, don't rebuild.** `loaded_nodes` should be carried across refreshes, not thrown away and rebuilt.
3. **Use the tree as the index.** The `InteractiveTreeNode` tree encodes parent-child relationships. Don't duplicate them eagerly.
4. **Stale is harmless, let it leak.** A stale `NodeId` in `collapsed_nodes` or `selection` costs a few bytes and never causes incorrect behavior — all access goes through `loaded_nodes.get(id)` which returns `None`.

### Architecture

Split indexes into two categories:

**Always maintained:**
- `loaded_nodes: Map[NodeId, InteractiveTreeNode]` — carried across refreshes, never rebuilt from scratch.

**Lazy (built on first access, invalidated on tree change):**
- `lazy_parent_map: Ref[Map[NodeId, NodeId]?]` — built when `is_descendant_of` is first called.
- `lazy_preorder: Ref[LazyPreorder?]` — built when `collect_subtree_ids` or `collect_nodes_in_range` is first called.

```
TreeEditorState {
  tree: InteractiveTreeNode?
  loaded_nodes: Map[NodeId, InteractiveTreeNode]

  // UI state (unchanged)
  selection, collapsed_nodes, editing_node, ...

  // Lazy structural indexes
  priv lazy_parent_map: Ref[Map[NodeId, NodeId]?]
  priv lazy_preorder: Ref[LazyPreorder?]
}

struct LazyPreorder {
  ids: Array[NodeId]
  range_by_root: Map[NodeId, (Int, Int)]
}
```

**Invalidation rule:** Any operation that changes `tree` sets both lazy refs to `None`. Operations that only change UI state on existing nodes (Select, Collapse, Expand) don't invalidate — the structural shape hasn't changed.

**Stale UI pruning:** Eliminated entirely. Stale entries in `collapsed_nodes` or `selection` reference node IDs that don't exist in `loaded_nodes`, so they're silently ignored on access.

---

## Phase 1: Lazy Indexes

### Refresh Algorithm

**Current (4 O(n) passes):**
1. `build_loaded_node_index(self.tree)` — O(n)
2. `refresh_node_with_reuse_impl` — O(n), builds tree + all indexes
3. `valid_ids` → HashSet — O(n)
4. Stale UI pruning — O(n)

**New (1 O(n) pass):**
1. Walk new ProjNode tree, stamp-compare against `self.loaded_nodes` directly, build new `InteractiveTreeNode` tree + new `loaded_nodes`. No structural indexes, no `valid_ids`.
2. Set `lazy_parent_map = None`, `lazy_preorder = None`.
3. Return new state.

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

```moonbit
fn TreeEditorState::get_parent_map(self) -> Map[NodeId, NodeId] {
  match self.lazy_parent_map.val {
    Some(map) => map
    None => {
      let map = build_parent_map_from_tree(self.tree)
      self.lazy_parent_map.val = Some(map)
      map
    }
  }
}

fn TreeEditorState::get_preorder(self) -> LazyPreorder {
  match self.lazy_preorder.val {
    Some(idx) => idx
    None => {
      let idx = build_preorder_from_tree(self.tree)
      self.lazy_preorder.val = Some(idx)
      idx
    }
  }
}
```

Consumers change from direct field access to getter calls:
- `collect_subtree_ids` → uses `self.get_preorder()`
- `is_descendant_of` → uses `self.get_parent_map()`
- `collect_nodes_in_range` → uses `self.get_preorder()`
- `hydrate_subtree` → uses `self.get_parent_map()`

### `apply_selection_edit` Fix

Current: `build_loaded_node_index(Some(updated))` — full O(n) rebuild after selection change.

New: Patch only the changed nodes. `apply_selection_to_node` already returns a changed flag. Walk only the changed path and update those entries in `loaded_nodes`.

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

An 80-def program where the user edits one def: FlatProj's LCS tells us 79 defs are unchanged. Phase 2 skips all 79, visiting only the 1 changed def's subtree. Refresh goes from O(total_nodes) to O(changed_def_depth).

### Loaded Nodes Carry-Over

When reusing a subtree, walk the reused `InteractiveTreeNode` to copy its entries into the new `loaded_nodes` map. This is O(subtree_size) but avoids stamp comparison overhead and has no allocation beyond map insertions. For typical unchanged defs (3-5 nodes deep), this is negligible.

---

## Impact Summary

| Scenario | Current | Phase 1 | Phase 2 |
|----------|---------|---------|---------|
| Type 1 char in 80-def program | 4 x O(n) | 1 x O(n) lightweight | O(1 def's subtree) |
| SelectRange | O(n) eager | O(n) lazy, one-time | O(n) lazy, one-time |
| Delete node | O(n) eager | O(subtree) lazy preorder | O(subtree) |
| Drag validation | O(n) eager | O(depth) lazy parent walk | O(depth) |
| Select node | O(n) loaded_nodes rebuild | O(changed_path) patch | O(changed_path) patch |

---

## Testing Strategy

1. **Behavioral equivalence** — All existing `tree_editor_wbtest.mbt` tests pass unchanged. The optimization is internal; external behavior is identical.
2. **Reuse verification** — New whitebox tests verify:
   - Refresh after single-char edit reuses unchanged subtrees (Phase 2)
   - Lazy indexes are `None` after refresh, populated after first tree operation
   - Stale collapsed/selection IDs don't cause errors
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
