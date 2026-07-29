# btree

Counted B+ tree for [MoonBit](https://www.moonbitlang.com/) with O(log n) position-indexed access, insert, delete, and range operations.

All data lives in leaf nodes. Internal nodes store only child pointers and span counts for positional navigation — a B+ tree indexed by cumulative span rather than keys.

## Install

```bash
moon add dowdiness/btree
```

## How It Works

```
Internal(counts=[5, 3, 4], total=12)
├── Leaf(elem=a, span=5)     positions [0, 5)
├── Leaf(elem=b, span=3)     positions [5, 8)
└── Leaf(elem=c, span=4)     positions [8, 12)
```

Navigation uses the `counts` array as a cumulative index. To find position 6: `counts[0]=5` (skip), `6-5=1` into child 1 → `Leaf(b)` at offset 1.

Elements implement `BTreeElem` (requires `Spanning` + `Mergeable` + `Sliceable` from `dowdiness/rle`) for slice-aware range operations. `delete_range` merges newly adjacent boundary leaves when their elements are mergeable; insertion callbacks and `from_sorted` callers remain responsible for any broader canonicalization policy.

## Quick Start

```moonbit
// Define your element type
struct TextRun {
  text : String
  len : Int
}

// Implement BTreeElem traits (HasLength, Spanning, Mergeable, Sliceable)
impl @rle.HasLength for TextRun with fn length(self) -> Int { self.len }
impl @rle.Spanning for TextRun with fn span(self) -> Int { self.len }
impl @rle.Mergeable for TextRun with fn can_merge(a : TextRun, b : TextRun) -> Bool {
  true
}
impl @rle.Mergeable for TextRun with fn merge(a : TextRun, b : TextRun) -> TextRun {
  { text: a.text + b.text, len: a.len + b.len }
}
// ... plus Sliceable
impl @btree.BTreeElem for TextRun

// Use the tree
let tree : @btree.BTree[TextRun] = @btree.BTree::new()
tree.init_root({ text: "hello", len: 5 }, 5)
```

## API

| Method | Description | Complexity |
|--------|-------------|------------|
| `BTree::new(min_degree?)` | Create empty tree (default min_degree=10) | O(1) |
| `get_at(pos)` | Element at span position | O(log n) |
| `find(pos)` | Element + offset within element | O(log n) |
| `mutate_for_insert(pos, callback)` | Insert via leaf splice callback | O(log n) |
| `mutate_for_delete(pos, callback)` | Delete via leaf splice callback | O(log n) |
| `delete_range(start, end)` | Delete span range [start, end), with boundary repair/merge | O(log n) path planning/splice; O(n) current worst-case repair* |
| `from_sorted(items, min_degree?)` | Bulk-build from sorted `(elem, span)` pairs | O(n) |
| `view(start?, end?)` | Slice elements in range | O(k + log n) |
| `iter()` | Lazy cursor-based iterator | O(n) total |
| `each(f)` | Visit all elements | O(n) |
| `to_array()` | Collect all elements | O(n) |
| `span()` | Total span (cached) | O(1) |
| `size()` | Number of leaves | O(1) |

*Current worst-case repair can visit every child in the repaired subtree after range deletion.

## API Contracts

### Construction

Calling `new` creates an empty tree. Both `new` and `from_sorted` normalize
`min_degree` to the inclusive interval `[2, @int.MAX_VALUE / 2]`.
Use `init_root` to install the first element before calling
`mutate_for_insert`; `from_sorted([])` is another empty construction.
Calling `init_root` on an already initialized tree aborts with
`BTree::init_root: tree is already initialized` instead of replacing its
contents.

Every successful mutation preserves the empty-tree lifecycle invariant:
`size() == 0` if and only if the root is absent and `is_empty() == true`.

`init_root` and every `(element, span)` pair passed to `from_sorted` require a
strictly positive span. Invalid spans abort with
`BTree::init_root: leaf span must be positive` or
`BTree::from_sorted: leaf spans must be positive`, respectively.

`from_sorted` preserves input order but does not merge adjacent elements;
callers own any no-adjacent-mergeable canonicalization policy.

### Cumulative span range

A valid tree's cumulative span is always in `0..=@int.MAX_VALUE`; zero is the
empty-tree value, and `@int.MAX_VALUE` itself is supported. Construction or a
callback splice whose prospective total exceeds that range aborts with
`BTree: cumulative span must be in 0..=@int.MAX_VALUE` before an invalid root
can be observed.

Point mutations prepare and propagate through copy-on-write path arrays.
Range deletion completes its splice, boundary merge, and repair on the same
unpublished candidate. The tree publishes the candidate only after all
checked totals succeed, so an overflow rejection leaves its root, size, and
contents unchanged. A splice callback has already run by the time its returned
spans can be checked; external side effects performed by that callback are not
part of the tree-state rollback guarantee.

### Positions and ranges

Positions are measured in the cumulative units supplied by leaf spans. Ranges
are half-open `[start, end)`.

| Operation | Accepted bounds | Other input |
|-----------|-----------------|-------------|
| `find(pos)`, `get_at(pos)` | `0 <= pos < span()` | Return `None` for an empty tree, a negative position, or `pos >= span()`. |
| `mutate_for_insert(pos, callback)` | A non-empty tree and `0 <= pos <= span()`; the end position is valid. | Abort for an empty tree or a position outside the accepted bounds. Use `init_root` for the first element. |
| `mutate_for_delete(pos, callback)` | `0 <= pos < span()` | Return `None` without calling the callback for an empty tree or an out-of-bounds position. |
| `delete_range(start, end)` | `0 <= start < end`; `end` is clamped to `span()`. | No-op for an empty tree, a negative start, an empty or reversed range, or `start >= span()`. |
| `view(start?, end?)` | Defaults to `[0, span())`; a negative start clamps to `0`, and an omitted or oversized end clamps to `span()`. | Return an empty array when the clamped range is empty or reversed, its end is negative, its start is at or beyond `span()`, or the tree is empty. |

### Callback and splice contract

`LeafContext` captures the current element, its span, the offset within it,
its child index, and optional adjacent leaf values. `left_neighbor()` and
`right_neighbor()` return the captured values; the context exposes no live
tree collection.

A callback computes and returns a `Splice` description. The
engine applies that description after the callback returns and performs the
required propagation and rebalancing.

`Splice.start_idx` is inclusive and `Splice.end_idx` is exclusive in the
current leaf parent's child array. Callers must maintain
`0 <= start_idx <= end_idx <= parent child count`; arbitrary invalid indices
are not separately validated.

`new_leaves` replace that interval in order.
Every replacement span must be positive, or propagation aborts with
`BTree splice: leaf spans must be positive`. Their prospective cumulative
total must also satisfy the cumulative span range above.

The canonical splice shapes are:

| Shape | Replaced child interval | `new_leaves` |
|-------|-------------------------|--------------|
| Insert before child `i` | `[i, i)` | `[new]` |
| Replace child `i` | `[i, i + 1)` | `[replacement]` |
| Delete child `i` | `[i, i + 1)` | `[]` |
| Split child `i` | `[i, i + 1)` | `[left, right, ...]` |

Both mutation entry points support every structurally valid splice shape in
this table. Their `insert` and `delete` names describe descent and return-value
behavior; they do not restrict the callback to cardinality-increasing or
cardinality-decreasing replacements.

## Relationship to Other Libraries

```
dowdiness/rle          Traits: Spanning, Mergeable, Sliceable
    ↑
dowdiness/btree        Counted B+ tree (this library)
    ↑
dowdiness/order-tree   High-level API: insert_at, delete_at, from_array
```

- **rle** defines the element contracts. Any type implementing `BTreeElem` can be stored.
- **btree** is the engine — tree structure, navigation, rebalancing, range operations.
- **order-tree** adds convenience: `insert_at(pos, elem)`, `delete_at(pos)`, `from_array(items)`, operator overloads (`tree[pos]`, `tree[start:end]`).

Use `btree` directly when you need low-level control (custom splice callbacks). Use `order-tree` for standard sequence operations.

## Design

This is a **counted B+ tree**, also known as an order-statistic tree:

- **B+ tree**: data only in leaves, internal nodes are navigational
- **Counted**: `counts` array replaces keys — navigation by span position, not key comparison
- **RLE-aware where requested**: slice-aware range operations can merge newly adjacent boundary leaves

The tree maintains these structural invariants:
- All leaves at the same depth
- Internal nodes have between `min_degree` and `2 * min_degree` children (root excepted)
- `counts[i] == children[i].total()` and `total == sum(counts)`

Canonical no-adjacent-mergeable-leaf policy is enforced by higher-level callers (for example `order-tree`) or by insertion/bulk-build callbacks that choose to pre-merge input.
