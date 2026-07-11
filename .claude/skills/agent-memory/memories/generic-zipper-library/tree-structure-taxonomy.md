---
summary: "Taxonomy of tree structures for generic zipper library — rose/binary/btree/finger/trie with editor use cases"
created: 2026-04-04
tags: [zipper, data-structures, taxonomy, finger-tree, trie]
related: [core/proj_node.mbt, order-tree/src/walker_types.mbt]
---

# Tree Structure Taxonomy for Generic Zippers

## Already Implemented in Canopy

### Rose Tree (ProjNode)
- Shape: `T * List(X)` — node with data and array of children
- Context: `T * List(X) * List(X)` — parent data, left siblings, right siblings
- Use: AST navigation, DOM-like trees, file system trees
- Consumer: ProjNode[T] for projectional editing

### B-Tree (OrderTree)
- Shape: `Leaf(T, Int) | Internal(Array(X), Array(Int))`
- Context: `{ children, counts, child_idx }`
- Use: Counted sequences, CRDT positioning, O(log n) indexed access
- Consumer: OrderTree[VisibleRun] for FugueMax positions

## Worth Adding

### Binary Tree
- Shape: `1 + X * T * X`
- Context: `WentLeft(T, BinTree) | WentRight(BinTree, T)` — two variants
- Use: Foundation for BST, AVL, red-black, splay trees
- Notable: Splay operation IS a zipper operation (rotate focus to root via path)

### Finger Tree (monoid-annotated)
- Shape: `Empty | Single(T) | Deep(Array[T], FingerTree[Node[T]], Array[T])`
- Key insight: parameterize by MONOID, same shape gives different data structures
- (Int, +) → indexed sequence, (Max, max) → priority queue, (Interval, union) → interval tree
- Use in Canopy: SourceMap range queries with O(1) local cursor movement
- One zipper implementation, many abstract data types

### Trie
- Shape: `{ value: V?, children: Map[K, Trie[K, V]] }`
- Context: `{ key: K, parent_value: V?, siblings: Map[K, Trie[K, V]] }`
- Navigation: go down by key, go up, go to sibling key. Path IS a prefix.
- Use: Scope resolution (variable name lookup), autocomplete, module resolution

### Rope
- Shape: `Leaf(String) | Concat(Rope, Rope, Int)` — binary tree for text
- Context: Same as binary tree + weight annotation
- Use: Text editing cursor with O(1) local movement, O(log n) position lookup

## Theoretical Taxonomy

Organized by algebraic structure of positions:

| Category | Structure | Positions form | Focus means |
|----------|-----------|---------------|-------------|
| Tree | Rose, Binary | Free algebra (paths = words over child indices) | "I'm at this node" |
| Sequence | B-tree, Finger, Rope | Free monoid (linear order) | "I'm at this position" |
| Map | Trie | Free algebra over alphabet (strings) | "I'm at this prefix" |

Note: This is a practical grouping, not a standard theoretical taxonomy. The theory organizes by functor shape (polynomial functors, monoid-annotated types, indexed containers). The practical grouping maps to how the zipper is USED in an editor.

## Priority for Library

1. Rose tree (Phase 1 — needed for compact view)
2. B-tree (refactor OrderTree to use it)
3. Binary tree (when a consumer appears)
4. Finger tree (when monoid-annotated queries are needed)
5. Trie (when scope/autocomplete needs it)
