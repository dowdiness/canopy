# Projection Layer Incremental Updates

**Date:** 2026-03-15
**Status:** Draft (revised after review)

## Problem

Every edit triggers four O(n) passes in the projection pipeline:

1. `to_proj_node()` — full syntax tree → ProjNode right-fold
2. `reconcile_ast()` — recursive traversal of nested Let spine
3. `register_node_tree()` — flat registry rebuild
4. `SourceMap::from_ast()` — position mapping rebuild

## Research findings

### The projection is a nested Let spine, not a flat list

`to_proj_node` right-folds LetDef children into nested Let ProjNodes:

```
Let("x", init_x, Let("y", init_y, Let("z", init_z, Expr)))
```

Each Let's `children` is `[init, body]` where `body` is the entire remaining chain. Changing `init_z` forces rebuilding Let("z"), Let("y"), and Let("x") because each node's body child changed. **The entire spine rebuilds for ANY content edit.**

`physical_equal` on SourceFile CST children can detect which init subtree changed, but the right-fold itself is always O(n) — n new Let ProjNodes must be created with updated body references.

### reconcile_ast is already O(n), not O(n*m)

`reconcile_children` uses LCS, but Let nodes always have exactly 2 children `[init, body]`. The DP table is always 2x2. The total cost is O(n) recursive calls through the 80-deep Let spine, each with a constant-size LCS — not one 80x80 LCS as initially assumed.

### Eliminating reconciliation breaks structural edits

For content edits, positional matching works. For LetDef insertion/deletion, positional matching misaligns IDs for all subsequent LetDefs. Reconciliation must be kept.

### LetDef CST nodes are deduplicated by NodeInterner

`parse_let_item` uses `start_at` (no `try_reuse`), so LetDefs are re-parsed from scratch. But `NodeInterner` deduplicates structurally identical nodes — `physical_equal(old, new)` returns true for unchanged LetDefs.

### prev_root/prev_proj alignment breaks after tree edits

`apply_tree_edit()` seeds `prev_proj_node` with a structurally edited projection BEFORE reparsing. After a tree edit, `prev_proj` doesn't correspond to the previous CST. Any `physical_equal` scheme assuming alignment would break on this path.

## Revised approach: flat top-level projection

The nested Let spine forces O(n) rebuilds because each node embeds its successors. The fix: introduce a **flat intermediate representation** at the SourceFile level, then fold to nested Let only when needed.

### Flat representation

```moonbit
struct FlatProj {
  defs : Array[(String, ProjNode, Int, NodeId)]  // (name, init, start, id)
  final_expr : ProjNode?
}
```

### Incremental update on flat representation

1. Compare old and new SourceFile CST children via `physical_equal`
2. For unchanged LetDefs: reuse the old `(name, init, start, id)` entry
3. For changed LetDefs: rebuild only that entry's init via `syntax_to_proj_node`
4. Patch the flat array in O(1) for content edits

### Fold to nested Let on demand

When the UI needs a nested ProjNode tree (for rendering, tree editing):
- Right-fold `FlatProj.defs` into nested Let ProjNodes
- Cache the result and invalidate when `FlatProj` changes
- The fold is O(n) but only runs when the nested form is actually accessed

### What this changes

- `to_proj_node` → `to_flat_proj` (returns `FlatProj`)
- `projection_memo` stores `FlatProj` and lazily folds
- `reconcile_ast` operates on `FlatProj` (align flat arrays, not nested spines)
- Registry and source map build from `FlatProj` directly

### Trade-offs vs current approach

| | Current (nested spine) | Flat intermediate |
|---|---|---|
| Content edit cost | O(n) right-fold + O(n) reconcile | O(n) physical_equal scan + O(1) patch |
| Structural edit cost | O(n) right-fold + O(n) reconcile | O(n) scan + O(k) reconcile on flat array |
| Nested tree access | O(1) — already computed | O(n) lazy fold — only when accessed |
| Data structure change | None | New `FlatProj` type |

### What stays the same

- `syntax_to_proj_node` (single expression → ProjNode) — unchanged
- `ProjNode` data structure — unchanged
- The nested Let form — still produced, just lazily
- Node IDs — still stable via flat array alignment

## Open questions

1. Does the UI/rendering always need the nested form, or can it work with `FlatProj` directly? If it can use `FlatProj`, the lazy fold becomes unnecessary.

2. Should `FlatProj` live in the `projection` package or the `editor` package?

3. How does `apply_tree_edit` work with `FlatProj`? It currently operates on the nested ProjNode tree. Would it need to be updated, or can it fold → edit → unfold?

## Non-goals

- Changing the `ProjNode` data structure itself
- Making registry/source map incremental (optimize later)
- Changing the incr/Signal/Memo infrastructure
