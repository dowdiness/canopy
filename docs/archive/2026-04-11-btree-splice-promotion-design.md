# BTree Splice Promotion Design

## Problem

`BTree::delete_range` reconstructs boundary subtrees (left/right of the deleted range) via `rebuild_boundary_chain_optional`. These subtrees can contain underfull internal nodes (< min_degree children) at arbitrary levels when boundary material is sparse. Currently detected by `splice_has_underfull_descendants` and handled by an O(n) full-tree rebuild fallback. Goal: eliminate the fallback with O(log n) chain repair.

## Key Insight

Underfull nodes in a boundary subtree form a **chain** (single path), not a tree. Each reconstructed level has "kept siblings" (valid original subtrees) plus one reconstructed child from the level below. Only the reconstructed child can be underfull. So repair is a linear walk, not a tree traversal.

## Algorithm: Chain Repair

### Overview

After constructing a boundary subtree, walk the boundary chain from bottom to top. At each level, if the boundary node is underfull, repair it using the same borrow/merge operations used elsewhere in the B-tree:

1. **Borrow from sibling** — if an adjacent sibling (a valid original subtree) has > min_degree children, move one child to the underfull node. Sibling must have > min_degree (not >=) to preserve its own validity.
2. **Merge with sibling** — if no sibling can lend, merge the underfull node with an adjacent sibling. Merge partner has at most min_degree children (since it can't lend), so merged size ≤ (min_degree - 1) + min_degree = 2*min_degree - 1. No overflow possible.
3. **Propagate upward** — if merge makes the parent underfull, repeat at the next level
4. **Insertion-site repair** — if the boundary subtree root is still underfull after chain repair, apply repair at the splice insertion site (within the LCA's children array) before normal propagation begins. This requires extending `propagate_node_splice` to detect and repair underfull `new_children`.

### Height Invariant

Borrow and merge operations do **not** change subtree height. A merge combines two sibling nodes into one at the same level — the parent loses a child but stays at the same height. Height changes only at the actual tree root (via `normalize_root_after_delete`), which is already handled.

### Empty Levels

**Current behavior**: `rebuild_boundary_chain_optional` skips empty levels (`if children.length() > 0`).

**New behavior**: do not skip empty levels. An empty level represents a height position that must be preserved. However, `Internal(children=[], counts=[], total=0)` is **not a valid node** in this codebase — invariant checks reject it.

**Solution**: use `Option` to represent the boundary child at each level during construction. When a level has no boundary material, represent it as `None` rather than an empty Internal node. The repair function handles `None` boundary children by immediately merging the level with its sibling (effectively absorbing the boundary child's position into the sibling).

### Repair Function

```
fn repair_boundary_chain(
  node: BTreeNode[T],
  boundary_indices: Array[Int],  // per-level child index of the boundary child
  min_degree: Int,
) -> BTreeNode[T]
```

Walk `boundary_indices` from deepest to shallowest:
1. At each level, access the boundary child via `boundary_indices[level]`
2. If underfull, call repair (borrow or merge) on that level's children/counts
3. **Detect merge**: `ensure_min_after_splice` currently returns `Unit`. Need a variant that reports whether a merge occurred and the direction (left or right), because merge shifts child indices at higher levels.
4. If merge occurred, update `boundary_indices` for ancestor levels and recompute parent's counts/total
5. Return the repaired subtree root

### Integration into `delete_range`

1. In `plan_delete_range`: after calling `left_boundary_subtree` / `right_boundary_subtree` / `merged_boundary_subtree`, call `repair_boundary_chain` on each boundary subtree
2. In `propagate_node_splice`: after applying the splice, check each `new_children` entry for underfull roots. If found, apply insertion-site repair (borrow from or merge with adjacent children at the LCA level).
3. Remove `splice_has_underfull_descendants` check from `BTree::delete_range`
4. Remove `delete_range_rebuild` fallback
5. Remove `node_has_underfull` and `splice_has_underfull_descendants` helper functions

### Boundary Chain Indices

For one-sided boundaries (`left_boundary_subtree`, `right_boundary_subtree`):
- `keep_left=true`: boundary child is the **last** child at each level
- `keep_left=false`: boundary child is the **first** child at each level
- Index is deterministic from the `keep_left` flag — implicit, no metadata needed

For merged boundaries (`merged_boundary_subtree` via `merge_boundary_chain`):
- Boundary child position depends on the interleaving of left and right path suffixes
- Position is **not** simply "alternating sides" — it depends on the child_idx of each frame
- `merge_boundary_chain` must return explicit per-level boundary indices alongside the subtree node

### Interaction Between Left and Right Boundary Repairs

When the splice has both a left and right boundary subtree as `new_children`:
- Repair left boundary first, then right boundary
- Left repair cannot affect right boundary (they are separate children at the LCA level)
- However, if left repair's chain causes a merge at the boundary root level, the splice's `new_children` array changes length, which shifts the right boundary's index
- **Solution**: track both boundary positions in `new_children` and update the right index if left repair causes a merge at the root level

## Complexity

- **Time**: O(h * d) where h = tree height, d = min_degree. At each of h levels, borrow/merge touches O(d) children.
- **Space**: O(h) for the boundary path.
- With d treated as constant (typical: 10-20), this is **O(log n)**.
- vs current fallback: O(n) leaf collection + O(n) rebuild.

## Open Questions (Resolve During Prototype)

1. **Empty boundary child representation**: Should `rebuild_boundary_chain_optional` return `(BTreeNode[T], Array[Int])` (node + chain indices), or should the repair be integrated into the construction itself?
2. **`ensure_min_after_splice` return type**: Should we modify the existing function to return merge info, or create a new variant? Modifying changes the interface used by propagation.
3. **Insertion-site repair in `propagate_node_splice`**: How to detect which `new_children` entries are boundary subtree roots that need repair? Pass metadata from `plan_delete_range`?
4. **Merged boundary chain tracking**: Does `merge_boundary_chain` need restructuring, or can we add indices as a return value?

## Prototype Plan

Before full implementation, prototype these specific scenarios in whitebox tests:

1. **One-sided chain with empty deepest level** — verify repair merges the empty level correctly
2. **Two underfull repaired roots at one LCA** — verify insertion-site repair handles both boundaries
3. **Merged-boundary chain with explicit per-level indices** — verify index tracking through `merge_boundary_chain`
4. **Insertion-site repair only** — case where chain repair fixes all internal levels but root is still underfull

## Testing Strategy

1. **Existing tests pass unchanged** — the "underfull fallback" test should now take the repair path
2. **Prototype scenarios above** as explicit whitebox tests
3. **Property tests** — existing `prop_delete_range_preserves_invariants` covers random inputs
4. **Remove fallback and verify** — all property test cases must pass without the O(n) rebuild

## Non-Goals

- `from_sorted` with height constraint — not needed for chain repair
- Changing the `plan_delete_range` pipeline structure beyond adding repair
- Optimizing repair for the common case (most deletes don't trigger underfull)

## Precedent

Rust's `BTreeMap::split_off` uses the same pattern: construct a "pillar" at the correct height, move suffixes along the split path, then fix borders via steal/merge. See `alloc/collections/btree/fix.rs`.
