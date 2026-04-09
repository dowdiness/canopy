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

Elements implement `BTreeElem` (requires `Spanning` + `Mergeable` + `Sliceable` from `dowdiness/rle`). Adjacent leaves with the same identity merge automatically — this is RLE compression at the tree level.

## Quick Start

```moonbit
// Define your element type
struct TextRun {
  text : String
  len : Int
}

// Implement BTreeElem traits (Spanning, Mergeable, Sliceable)
impl @rle.Spanning for TextRun with span(self) { self.len }
impl @rle.Mergeable for TextRun with can_merge(a, b) { true }
impl @rle.Mergeable for TextRun with merge(a, b) {
  { text: a.text + b.text, len: a.len + b.len }
}
// ... plus Sliceable, HasLength
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
| `delete_range(start, end)` | Delete span range [start, end) | O(log n)* |
| `view(start?, end?)` | Slice elements in range | O(k + log n) |
| `iter()` | Lazy cursor-based iterator | O(n) total |
| `each(f)` | Visit all elements | O(n) |
| `to_array()` | Collect all elements | O(n) |
| `span()` | Total span (cached) | O(1) |
| `size()` | Number of leaves | O(1) |

*Falls back to O(n) rebuild when boundary subtrees are underfull.

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
- **RLE-aware**: adjacent mergeable leaves auto-compress

The tree maintains these invariants:
- All leaves at the same depth
- Internal nodes have between `min_degree` and `2 * min_degree` children (root excepted)
- `counts[i] == children[i].total()` and `total == sum(counts)`
- No adjacent mergeable leaves (RLE invariant)
