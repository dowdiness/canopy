# Projection Layer Incremental Updates

**Date:** 2026-03-15
**Status:** Approved

## Problem

Every edit triggers four O(n) passes in the projection pipeline because the projection is a right-folded nested Let spine. Changing any LetDef's init rebuilds every enclosing Let node.

## Research findings

### The projection is a nested Let spine, not a flat list

`to_proj_node` right-folds LetDef children into nested Let ProjNodes. Each Let embeds its entire tail as `body`, so changing `init_z` forces rebuilding Let("z"), Let("y"), and Let("x"). The entire spine rebuilds for ANY content edit.

### reconcile_ast is already O(n), not O(n*m)

Let nodes always have exactly 2 children `[init, body]`. The LCS DP table is always 2x2. Total cost is O(n) recursive calls through the nested spine — not O(n²).

### LetDef CST nodes are deduplicated by NodeInterner

`parse_let_item` uses `start_at` (no `try_reuse`), so LetDefs are re-parsed from scratch. But `NodeInterner` deduplicates them — `physical_equal` returns true for unchanged LetDefs.

### Eliminating reconciliation breaks structural edits

For content edits, positional matching works. For LetDef insertion/deletion, positional matching misaligns IDs. Reconciliation must be kept but can operate on flat arrays.

### prev_root/prev_proj alignment breaks after tree edits

`apply_tree_edit()` seeds `prev_proj_node` before reparsing. After a tree edit, `prev_proj` doesn't correspond to the previous CST. Any `physical_equal` scheme assuming alignment must account for this.

## Solution: FlatProj replaces nested Let spine

Introduce `FlatProj` as the primary projection representation. The nested Let form is eliminated from the hot path.

### FlatProj

```moonbit
pub struct FlatProj {
  defs : Array[(String, ProjNode, Int, NodeId)]  // (name, init, start, id)
  final_expr : ProjNode?
}
```

Lives in `projection/` package alongside ProjNode.

### Incremental update

1. Compare old and new SourceFile CST children via `physical_equal`
2. Unchanged LetDefs: reuse old `(name, init, start, id)` entry
3. Changed LetDefs: rebuild only that entry's init via `syntax_to_proj_node`

Content edits: O(n) pointer comparisons + O(changed_subtree) work.

### What changes

| Component | Current | After |
|-----------|---------|-------|
| `to_proj_node` | Returns nested ProjNode spine | Replaced by `to_flat_proj` returning FlatProj |
| `reconcile_ast` | Recursive traversal of nested spine | `reconcile_flat_proj` aligns flat arrays |
| `print_term` (for tree edits) | Walks nested Let chain | Iterates flat array: `let {name} = {init}\n` |
| `apply_tree_edit` | Navigates nested spine | Operates on flat array (simpler) |
| `projection_memo` | Stores nested ProjNode | Stores FlatProj |
| `register_node_tree` | Walks nested ProjNode | Walks FlatProj entries |
| `SourceMap::from_ast` | Walks nested ProjNode | Walks FlatProj entries |

### What stays the same

- `ProjNode` data structure — unchanged, still used for individual expressions (init subtrees, final expression)
- `syntax_to_proj_node` — unchanged, converts single CST expression → ProjNode
- Node IDs — stable via flat array alignment
- `physical_equal` on CstNode — the reuse detection mechanism

### Reconciliation on flat arrays

```moonbit
fn reconcile_flat_proj(
  old : FlatProj,
  new_defs : Array[(String, ProjNode, Int)],
  new_final : ProjNode?,
  counter : Ref[Int],
) -> FlatProj
```

- Scan old and new def arrays in parallel
- `physical_equal` on init ProjNodes to detect unchanged entries
- For unchanged: preserve old entry (including NodeId)
- For changed: assign new NodeId, reconcile init children
- For insertions/deletions: LCS alignment on the flat array (true top-level LCS)

### apply_tree_edit on FlatProj

Structural edits become array operations:
- Insert LetDef → insert entry in flat array
- Delete LetDef → remove entry from flat array
- Edit init → replace init ProjNode in entry
- Edit final expression → replace final_expr
- Convert back to text: iterate array printing `let {name} = {print_term(init)}\n{print_term(final_expr)}`

### Seeding after tree edits

`apply_tree_edit` seeds FlatProj directly. Since FlatProj is flat, the seed is straightforward — the structurally edited flat array. No prev_root/prev_proj alignment issue because FlatProj doesn't reference CstNodes.

## Expected outcome

- Content edits: O(n) physical_equal scan + O(changed_subtree) rebuild
- Structural edits: O(n) scan + O(k) LCS on k changed entries
- No nested spine rebuild on any edit
- Tree edits simpler (array operations vs spine navigation)

## Non-goals

- Changing the `ProjNode` data structure itself
- Making registry/source map incremental (optimize later)
- Changing the incr/Signal/Memo infrastructure
