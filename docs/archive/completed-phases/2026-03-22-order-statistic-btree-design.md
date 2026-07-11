# Order-Statistic B-tree Design

## Goal

Build a generic order-statistic B-tree library in MoonBit that serves as the document-order index for the eg-walker CRDT. This is Phase 1 of a three-phase plan to replace FugueTree's immutable HashMaps with a single B-tree that IS the document state.

## Motivation

### Current bottleneck

At 1000 defs (~39ms per keystroke):
- FugueTree immutable HashMap operations: ~20ms (dominant cost)
- Position cache rebuild via traverse_tree: ~5ms
- LCA index rebuild: ~5ms
- Parser + projection: ~9ms

### End-state vision (Phase 2-3)

The B-tree replaces FugueTree's HashMaps, position cache, and LCA index. Items live in B-tree leaves with CRDT metadata. One data structure, O(log n) everything. Expected: ~5ms at 1000 defs.

### This phase (Phase 1)

Standalone B-tree library with the API needed for Phase 2 integration. No CRDT coupling. Generic over element type. Usable as a drop-in position-indexed sequence.

## Architecture

### Data structure

The tree uses a sum-type node to make invalid states unrepresentable:

```moonbit
enum OrderNode[T] {
  Leaf(items: Array[T], total: Int)
  Internal(children: Array[OrderNode[T]], counts: Array[Int], total: Int)
}

struct OrderTree[T] {
  mut root: OrderNode[T]?
  min_degree: Int       // default 10 (benchmark to confirm for JS/Wasm)
  mut size: Int         // total leaf entries (not span — may differ when items have span > 1)
}
```

`Internal` nodes store `children` (no Option — all child slots are always valid) and `counts[i]` = total span in `children[i]`'s subtree. `Leaf` nodes store items directly. No keys — position is implicit from subtree counts.

`total` on each node = sum of spans in the subtree, enabling O(1) `span()` from the root.

**Mutability model:** OrderTree is mutable. `insert_at`, `delete_at`, `set_at` modify the tree in place. This is a deliberate departure from FugueTree's immutable HashMap — the undo system uses inverse operations (delete/undelete), not tree snapshots.

### Counts and spans

`counts[i]` tracks the **sum of `Spanning::span()` values** in the subtree rooted at `children[i]`. For items with `span() == 1` (single characters), counts equals item count. For merged runs (e.g., `VisibleRun` with `count > 1`), counts reflects the total span, not the number of leaf entries.

This means:
- Position navigation uses span arithmetic: subtract `counts[i]` to skip past child `i`
- `set_at(pos, item)` must propagate count changes to root if `span(new) != span(old)`
- After a merge of two adjacent items, the leaf's entry count decreases but span stays the same — counts are unaffected

### Core operations

**Phase 1a operates on `span() == 1` items only.** All positions map 1:1 to leaf entries. Multi-span items (`span() > 1`) and mid-item splitting require `Sliceable` and are deferred to Phase 1b.

| Method | Cost | Description |
|---|---|---|
| `insert_at(pos, item)` | O(log n) | Insert item at span position, update counts to root |
| `delete_at(pos) -> T?` | O(log n) | Remove item at span position, update counts to root |
| `get_at(pos) -> T?` | O(log n) | Look up item at span position |
| `set_at(pos, item)` | O(log n) | Replace item at position, propagate span change if any |
| `delete_range(start, end)` | O(k log n) | Remove k items in span range [start, end). Uses subtree splicing when possible, point-deletes otherwise. |
| `span() -> Int` | O(1) | Total span (root.total) |
| `size() -> Int` | O(1) | Total leaf entries (may differ from span when items have span > 1) |
| `iter() -> Iter[T]` | O(n) | Lazy left-to-right leaf scan |
| `each(f)` | O(n) | Callback-based traversal |
| `to_array() -> Array[T]` | O(n) | Collect all items in order |
| `from_array(items) -> OrderTree[T]` | O(n) | Bulk build bottom-up |

### Position navigation

To find span position P in a tree:

```
walk(node, remaining = P):
  match node:
    Leaf(items, _):
      // Walk items, subtracting span of each
      for item in items:
        if remaining < item.span():
          return (item, remaining)  // found: item + offset within it
        remaining -= item.span()
    Internal(children, counts, _):
      for i in 0..children.length():
        if remaining < counts[i]:
          return walk(children[i], remaining)
        remaining -= counts[i]
```

O(log n) — one comparison per tree level.

### Find result

`find` returns the item directly (not an index requiring a second lookup):

```moonbit
struct FindResult[T] {
  item: T          // the leaf item containing this position
  offset: Int      // offset within the item (0 for span-1 items)
}
```

This eliminates the double-lookup pattern in the current `Rle::find` + `Rle::get` usage.

### Bulk build

`from_array` builds the tree bottom-up in O(n):
1. Partition items into leaf-sized groups. Each leaf holds `min_degree - 1` to `2 * min_degree - 1` items. The last leaf may hold fewer if needed, but must hold at least `min_degree - 1` items (unless it's the only leaf). If the last group is underfull, redistribute items from the previous group.
2. Create leaf nodes from each group, computing `total` from span sums.
3. Build internal nodes layer by layer: each internal node holds `min_degree` to `2 * min_degree` children. Same redistribution rule for the last node at each level.
4. Repeat until one root node remains. The root is exempt from minimum occupancy.

This ensures all non-root nodes satisfy the B-tree occupancy invariant: at least `t-1` keys (leaves) or `t` children (internal).

### Underflow handling (delete)

When `delete_at` reduces a node below minimum occupancy (`min_degree - 1` items for leaves, `min_degree` children for internal nodes):
1. Try to borrow from left sibling (rotate through parent)
2. Try to borrow from right sibling (rotate through parent)
3. Merge with a sibling (combine two underfull nodes + parent separator)

This is the standard B-tree deletion algorithm. The existing `tree_structure_zoo` B-tree implements all three cases (`borrow_from_prev`, `borrow_from_next`, `merge`), providing a reference for the mechanics.

### Leaf merging (deferred to Phase 1b)

RLE compression in leaves (merging adjacent items via `Mergeable` trait) adds complexity around span changes, split boundaries, and count maintenance. Phase 1 starts with non-merging items (each item is one leaf entry). Phase 1b adds merging as a follow-up once the core tree is working.

### Rle-compatible interface

The OrderTree exposes the same methods that `Document` currently calls on `Rle[VisibleRun]`:

```moonbit
// Matches Rle::find(pos)
OrderTree::find(pos: Int) -> FindResult[T]?

// Matches Spanning::span(rle)
OrderTree::span() -> Int

// Matches Rle::iter()
OrderTree::iter() -> Iter[T]
```

### Reverse lookup (LV → position)

Phase 1 does not include reverse lookup (`find_by_value`). The current `Document::lv_to_position` does O(n) linear scan, and this is used infrequently (undo, cursor tracking).

Phase 2a will add a secondary `Array[Int?]` index mapping LV → span position for O(1) reverse lookup. This is required for:
- `Document::lv_to_position` (used by undo system via `Undoable` trait)
- Remote `Delete`/`Undelete` by LV (not by visible position)
- Cursor adjustment after remote ops

The index is deferred to Phase 2 because it requires CRDT-specific knowledge (LVs are sequential integers) that doesn't belong in a generic library. Phase 2a will maintain this index alongside the OrderTree, updating it on every insert/delete.

### Traits required from T

```moonbit
T : Spanning    // span(self) -> Int — drives position arithmetic in counts
                // logical_length(self) -> Int — optional, for text-offset queries
```

`Spanning::span` is the primary metric for position indexing. `Spanning::logical_length` is available for secondary queries (e.g., converting item positions to UTF-16 text offsets) but does not drive the tree's internal counts.

`Mergeable` is deferred to Phase 1b.

## What this does NOT include (Phase 2-3)

- CRDT metadata in leaves (Phase 2)
- LV → position reverse index (Phase 2)
- Retreat/advance state machine (Phase 3)
- Two-count nodes for prepare/effect versions (Phase 3)
- FugueTree replacement (Phase 2)
- Integration with Document (Phase 2)

## Module structure

```
order-tree/
├── moon.mod.json
├── src/
│   ├── moon.pkg
│   ├── order_tree.mbt          // OrderTree struct, public API
│   ├── order_node.mbt          // OrderNode enum, navigation, split/merge
│   ├── bulk_build.mbt          // from_array O(n) construction
│   ├── iter.mbt                // Iter[T] and each() implementation
│   ├── types.mbt               // FindResult
│   ├── order_tree_test.mbt     // blackbox tests
│   ├── order_node_wbtest.mbt   // whitebox tests for internals
│   ├── properties_test.mbt     // QuickCheck property tests
│   └── benchmark.mbt           // performance benchmarks
```

Single package, same structure as `rle/`.

## Testing strategy

### Unit tests
- insert_at/delete_at/get_at at boundaries (0, middle, end)
- delete_range for contiguous removal
- Split and merge node mechanics
- Count maintenance after insert/delete sequences (including span > 1 items)
- set_at with span-changing replacement
- Empty tree, single-item tree
- to_array / from_array roundtrip

### Property tests (QuickCheck)
- `insert_at(pos, x)` then `get_at(pos)` returns `x`
- `delete_at(pos)` reduces `span()` by the deleted item's span
- `from_array(items).to_array()` roundtrips
- Random insert/delete sequences maintain valid B-tree invariants (all leaves same depth, node sizes within bounds, counts sum correctly)
- Phase 1a: all items have `span() == 1`. Phase 1b adds tests with `span() > 1` items (merged runs) to exercise span arithmetic and `Sliceable` splitting

### Benchmarks
- insert_at sequential (1000, 10000 items)
- insert_at random positions (1000, 10000 items)
- get_at random positions (1000, 10000 items)
- delete_at random positions (1000, 10000 items)
- delete_range (1000, 10000 items)
- from_array bulk build (1000, 10000 items)
- iter full traversal (1000, 10000 items)

### min_degree tuning
Benchmark with min_degree = 2, 5, 10, 16, 32. The existing key-value B-tree shows min_degree=10 is ~3x faster than min_degree=2, but the position-indexed tree does integer arithmetic instead of key comparisons, so the optimal fanout may differ.

## Success criteria

1. All position operations are O(log n), verified by benchmarks
2. `span()` is O(1)
3. B-tree invariants hold after any sequence of operations (property tests)
4. Performance matches or beats the existing `BTree[K,V]` from tree_structure_zoo
5. API is compatible with what `Document` needs (find, span, iter)
6. Clean separation — no CRDT dependencies, pure data structure library

## Phase roadmap

| Phase | Scope | Outcome |
|---|---|---|
| **1a (this spec)** | OrderTree core | Position-indexed B-tree with insert/delete/get/find, no merging |
| **1b** | Leaf merging | Add `Mergeable` support for RLE compression in leaves |
| **2a** | Replace position cache | OrderTree as Document's position index, keep FugueTree for structure |
| **2b** | Replace FugueTree | B-tree leaves store CRDT items, eliminate HashMap |
| **3** | Full eg-walker | Retreat/advance, two-count nodes, critical version compaction |
