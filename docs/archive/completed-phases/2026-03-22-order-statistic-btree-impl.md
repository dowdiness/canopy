# Order-Statistic B-tree Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a generic order-statistic B-tree (`OrderTree[T]`) in MoonBit — a position-indexed sequence with O(log n) insert/delete/lookup via subtree counts.

**Architecture:** Sum-type `OrderNode[T]` enum (Leaf | Internal) with `total` span counts. Internal nodes store `counts[i]` = span of child subtree. Navigation by span arithmetic. No keys — position is implicit. Phase 1a: `span() == 1` items only.

**Tech Stack:** MoonBit, `dowdiness/rle` traits (`Spanning`, `HasLength`), QuickCheck for property tests

**Spec:** `docs/plans/2026-03-22-order-statistic-btree-design.md`

**Note:** File structure deviates from the spec's single `order_node.mbt` — this plan splits node operations into `navigate.mbt`, `insert.mbt`, `delete.mbt` for better separation of concerns. `order_node_wbtest.mbt` is renamed to `invariant_wbtest.mbt` to reflect its actual purpose. Property tests use `properties_wbtest.mbt` (whitebox) since they need access to `check_invariants`.

---

## File Structure

| File | Responsibility |
|------|---------------|
| `order-tree/moon.mod.json` | Module definition |
| `order-tree/src/moon.pkg` | Package config with deps |
| `order-tree/src/types.mbt` | `OrderNode[T]` enum, `OrderTree[T]` struct, `FindResult[T]` struct |
| `order-tree/src/navigate.mbt` | Position navigation: `find_node`, `get_at` internals |
| `order-tree/src/insert.mbt` | `insert_at`, `split_child` |
| `order-tree/src/delete.mbt` | `delete_at`, `borrow_from_prev/next`, `merge_nodes` |
| `order-tree/src/order_tree.mbt` | Public API: `new`, `insert_at`, `delete_at`, `get_at`, `set_at`, `find`, `span`, `size`, `delete_range` |
| `order-tree/src/iter.mbt` | `iter() -> Iter[T]`, `each(f)`, `to_array()` |
| `order-tree/src/bulk_build.mbt` | `from_array` O(n) bottom-up construction |
| `order-tree/src/order_tree_test.mbt` | Blackbox unit tests |
| `order-tree/src/invariant_wbtest.mbt` | Whitebox B-tree invariant checks |
| `order-tree/src/properties_wbtest.mbt` | QuickCheck property tests (whitebox — needs check_invariants) |
| `order-tree/src/order_tree_benchmark.mbt` | Performance benchmarks |

---

### Task 1: Scaffold the module

**Files:**
- Create: `order-tree/moon.mod.json`
- Create: `order-tree/src/moon.pkg`
- Create: `order-tree/src/types.mbt`

- [ ] **Step 1: Create module files**

`order-tree/moon.mod.json`:
```json
{
  "name": "dowdiness/order-tree",
  "version": "0.1.0",
  "source": "src",
  "deps": {
    "dowdiness/rle": { "path": "../rle" },
    "moonbitlang/quickcheck": "0.9.9"
  },
  "readme": "README.md",
  "license": "Apache-2.0",
  "keywords": ["btree", "order-statistic", "data-structure"],
  "description": "Order-statistic B-tree with O(log n) position-indexed operations"
}
```

`order-tree/src/moon.pkg`:
```json
import {
  "dowdiness/rle" @rle,
}

import {
  "moonbitlang/core/bench" @bench,
  "moonbitlang/core/quickcheck",
  "moonbitlang/quickcheck" @qc,
} for "test"
```

`order-tree/src/types.mbt`:
```moonbit
///|
/// Result of a position lookup in the tree.
pub struct FindResult[T] {
  item : T
  offset : Int
} derive(Show, Eq)

///|
/// A node in the order-statistic B-tree.
/// Leaf nodes store items directly.
/// Internal nodes store children with per-child span counts.
pub(all) enum OrderNode[T] {
  Leaf(items~ : Array[T], total~ : Int)
  Internal(
    children~ : Array[OrderNode[T]],
    counts~ : Array[Int],
    total~ : Int,
  )
} derive(Show, Eq)

///|
/// Order-statistic B-tree: a position-indexed sequence with O(log n) operations.
/// Items are ordered by insertion position, not by key comparison.
/// Each internal node caches subtree span counts for fast navigation.
pub struct OrderTree[T] {
  mut root : OrderNode[T]?
  min_degree : Int
  mut size : Int
} derive(Show, Eq)

///|
let default_min_degree : Int = 10
```

- [ ] **Step 2: Verify compilation**

Run: `cd order-tree && moon check`
Expected: 0 errors

- [ ] **Step 3: Commit**

```bash
cd order-tree && git init && git add -A && git commit -m "feat: scaffold order-tree module with types"
```

---

### Task 2: Constructor and basic queries (`new`, `span`, `size`, `is_empty`)

**Files:**
- Create: `order-tree/src/order_tree.mbt`
- Create: `order-tree/src/order_tree_test.mbt`

- [ ] **Step 1: Write failing tests**

```moonbit
///|
test "new creates empty tree" {
  let tree : OrderTree[TItem] = OrderTree::new()
  inspect(tree.span(), content="0")
  inspect(tree.size(), content="0")
  inspect(tree.is_empty(), content="true")
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `moon test -f order_tree_test.mbt`
Expected: FAIL — methods don't exist

- [ ] **Step 3: Implement constructors and queries**

`order-tree/src/order_tree.mbt`:
```moonbit
///|
pub fn[T] OrderTree::new(min_degree? : Int = default_min_degree) -> OrderTree[T] {
  { root: None, min_degree, size: 0 }
}

///|
pub fn[T] OrderTree::is_empty(self : OrderTree[T]) -> Bool {
  self.root is None
}

///|
pub fn[T] OrderTree::span(self : OrderTree[T]) -> Int {
  match self.root {
    None => 0
    Some(Leaf(total~, ..)) => total
    Some(Internal(total~, ..)) => total
  }
}

///|
pub fn[T] OrderTree::size(self : OrderTree[T]) -> Int {
  self.size
}
```

- [ ] **Step 4: Run tests**

Run: `moon test -f order_tree_test.mbt`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: add OrderTree constructor and basic queries"
```

---

### Task 3: Position navigation (`get_at`, `find`)

**Files:**
- Create: `order-tree/src/navigate.mbt`
- Modify: `order-tree/src/order_tree.mbt`
- Modify: `order-tree/src/order_tree_test.mbt`

- [ ] **Step 1: Write failing tests**

```moonbit
///|
test "get_at on empty tree returns None" {
  let tree : OrderTree[TItem] = OrderTree::new()
  inspect(tree.get_at(0), content="None")
}

///|
test "find on empty tree returns None" {
  let tree : OrderTree[TItem] = OrderTree::new()
  inspect(tree.find(0), content="None")
}
```

- [ ] **Step 2: Implement navigation**

`order-tree/src/navigate.mbt`:
```moonbit
///|
/// Navigate to the item at span position `pos` within a node.
/// Returns (item, offset_within_item) or None if out of bounds.
fn[T : @rle.Spanning] OrderNode::navigate(
  self : OrderNode[T],
  pos : Int,
) -> FindResult[T]? {
  match self {
    Leaf(items~, ..) => {
      let mut remaining = pos
      for i = 0; i < items.length(); i = i + 1 {
        let s = @rle.Spanning::span(items[i])
        if remaining < s {
          return Some({ item: items[i], offset: remaining })
        }
        remaining = remaining - s
      }
      None
    }
    Internal(children~, counts~, ..) => {
      let mut remaining = pos
      for i = 0; i < children.length(); i = i + 1 {
        if remaining < counts[i] {
          return children[i].navigate(remaining)
        }
        remaining = remaining - counts[i]
      }
      None
    }
  }
}
```

In `order-tree/src/order_tree.mbt`, add:
```moonbit
///|
pub fn[T : @rle.Spanning] OrderTree::get_at(self : OrderTree[T], pos : Int) -> T? {
  match self.root {
    None => None
    Some(node) =>
      match node.navigate(pos) {
        Some(result) => Some(result.item)
        None => None
      }
  }
}

///|
pub fn[T : @rle.Spanning] OrderTree::find(
  self : OrderTree[T],
  pos : Int,
) -> FindResult[T]? {
  match self.root {
    None => None
    Some(node) => node.navigate(pos)
  }
}
```

- [ ] **Step 3: Run tests**

Run: `moon test -f order_tree_test.mbt`
Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "feat: add position navigation (get_at, find)"
```

---

### Task 4: Insert with leaf splitting (`insert_at`)

**Files:**
- Create: `order-tree/src/insert.mbt`
- Modify: `order-tree/src/order_tree.mbt`
- Modify: `order-tree/src/order_tree_test.mbt`

- [ ] **Step 1: Write failing tests**

```moonbit
///|
/// Test wrapper with span=1. Avoids implementing Spanning for Int
/// (which would pollute the public API via .mbti).
priv struct TItem {
  value : Int
} derive(Show, Eq)

///|
impl @rle.HasLength for TItem with length(_self) -> Int { 1 }

///|
impl @rle.Spanning for TItem with span(_self) -> Int { 1 }

///|
fn ti(v : Int) -> TItem { { value: v } }

///|
test "insert_at into empty tree" {
  let tree : OrderTree[TItem] = OrderTree::new()
  tree.insert_at(0, ti(42))
  inspect(tree.span(), content="1")
  inspect(tree.size(), content="1")
  inspect(tree.get_at(0), content="Some(42)")
}

///|
test "insert_at at beginning" {
  let tree : OrderTree[TItem] = OrderTree::new()
  tree.insert_at(0, 1)
  tree.insert_at(0, 2)
  inspect(tree.get_at(0), content="Some(2)")
  inspect(tree.get_at(1), content="Some(1)")
}

///|
test "insert_at at end" {
  let tree : OrderTree[TItem] = OrderTree::new()
  for i = 0; i < 5; i = i + 1 {
    tree.insert_at(i, i)
  }
  inspect(tree.span(), content="5")
  for i = 0; i < 5; i = i + 1 {
    inspect(tree.get_at(i) == Some(i), content="true")
  }
}

///|
test "insert_at triggers leaf split" {
  let tree : OrderTree[TItem] = OrderTree::new(min_degree=2)
  // max keys per leaf = 2*2-1 = 3. Insert 4 to trigger split.
  for i = 0; i < 4; i = i + 1 {
    tree.insert_at(i, i * 10)
  }
  inspect(tree.span(), content="4")
  inspect(tree.get_at(0), content="Some(0)")
  inspect(tree.get_at(3), content="Some(30)")
}

///|
test "insert_at 100 sequential items" {
  let tree : OrderTree[TItem] = OrderTree::new(min_degree=3)
  for i = 0; i < 100; i = i + 1 {
    tree.insert_at(i, i)
  }
  inspect(tree.span(), content="100")
  inspect(tree.get_at(0), content="Some(0)")
  inspect(tree.get_at(50), content="Some(50)")
  inspect(tree.get_at(99), content="Some(99)")
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `moon test -f order_tree_test.mbt`
Expected: FAIL

- [ ] **Step 3: Implement insert_at**

`order-tree/src/insert.mbt` — implement:
- `OrderNode::insert_into_leaf(pos, item, min_degree)` — insert item at position in leaf, split if full, return optional split result `(new_node, promoted_total)`
- `OrderNode::insert_into_internal(pos, item, min_degree)` — navigate by counts, recurse, handle child split by inserting new child
- `OrderNode::split_leaf(min_degree)` — split a full leaf into two, return right half + its total
- `OrderNode::split_internal(min_degree)` — split a full internal node into two

In `order-tree/src/order_tree.mbt`, add:
```moonbit
pub fn[T : @rle.Spanning] OrderTree::insert_at(
  self : OrderTree[T],
  pos : Int,
  item : T,
) -> Unit
```

The implementation should:
1. Clamp `pos` to `[0, span()]` — inserting beyond span appends at end, negative prepends
2. If root is None, create a Leaf with the single item
3. Otherwise, call `root.insert(pos, item, min_degree)`
4. If root splits, create new Internal root with two children
5. Update `self.size += 1`

- [ ] **Step 4: Run tests**

Run: `moon test -f order_tree_test.mbt`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: add insert_at with leaf splitting"
```

---

### Task 5: Delete with underflow handling (`delete_at`)

**Files:**
- Create: `order-tree/src/delete.mbt`
- Modify: `order-tree/src/order_tree.mbt`
- Modify: `order-tree/src/order_tree_test.mbt`

- [ ] **Step 1: Write failing tests**

```moonbit
///|
test "delete_at from single-item tree" {
  let tree : OrderTree[TItem] = OrderTree::new()
  tree.insert_at(0, 42)
  let deleted = tree.delete_at(0)
  inspect(deleted, content="Some(42)")
  inspect(tree.is_empty(), content="true")
}

///|
test "delete_at from beginning" {
  let tree : OrderTree[TItem] = OrderTree::new()
  for i = 0; i < 5; i = i + 1 { tree.insert_at(i, i) }
  let deleted = tree.delete_at(0)
  inspect(deleted, content="Some(0)")
  inspect(tree.get_at(0), content="Some(1)")
  inspect(tree.span(), content="4")
}

///|
test "delete_at from end" {
  let tree : OrderTree[TItem] = OrderTree::new()
  for i = 0; i < 5; i = i + 1 { tree.insert_at(i, i) }
  let deleted = tree.delete_at(4)
  inspect(deleted, content="Some(4)")
  inspect(tree.span(), content="4")
}

///|
test "delete_at triggers underflow and borrow" {
  let tree : OrderTree[TItem] = OrderTree::new(min_degree=2)
  for i = 0; i < 5; i = i + 1 { tree.insert_at(i, i * 10) }
  // Delete enough to trigger underflow + borrow/merge
  for i = 0; i < 3; i = i + 1 { ignore(tree.delete_at(0)) }
  inspect(tree.span(), content="2")
  inspect(tree.get_at(0), content="Some(30)")
  inspect(tree.get_at(1), content="Some(40)")
}

///|
test "delete_at out of bounds returns None" {
  let tree : OrderTree[TItem] = OrderTree::new()
  tree.insert_at(0, 1)
  inspect(tree.delete_at(5), content="None")
  inspect(tree.span(), content="1")
}
```

- [ ] **Step 2: Implement delete_at**

`order-tree/src/delete.mbt` — implement:
- `OrderNode::delete_from_leaf(pos)` — remove item at position, return it
- `OrderNode::delete_from_internal(pos, min_degree)` — navigate by counts, recurse, handle underflow
- `OrderNode::borrow_from_prev(idx)` — borrow from left sibling via parent rotation
- `OrderNode::borrow_from_next(idx)` — borrow from right sibling via parent rotation
- `OrderNode::merge_children(idx)` — merge two children

In `order_tree.mbt`:
```moonbit
pub fn[T : @rle.Spanning] OrderTree::delete_at(
  self : OrderTree[T],
  pos : Int,
) -> T?
```

Handle root shrinking: if root is Internal with 0 children after delete, replace with its single child or None.

- [ ] **Step 3: Run tests**

Run: `moon test -f order_tree_test.mbt`
Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "feat: add delete_at with underflow handling"
```

---

### Task 6: `set_at`, `delete_range`

**Files:**
- Modify: `order-tree/src/order_tree.mbt`
- Modify: `order-tree/src/order_tree_test.mbt`

- [ ] **Step 1: Write failing tests**

```moonbit
///|
test "set_at replaces item" {
  let tree : OrderTree[TItem] = OrderTree::new()
  for i = 0; i < 5; i = i + 1 { tree.insert_at(i, i) }
  tree.set_at(2, 99)
  inspect(tree.get_at(2), content="Some(99)")
  inspect(tree.span(), content="5")
}

///|
test "delete_range removes contiguous items" {
  let tree : OrderTree[TItem] = OrderTree::new()
  for i = 0; i < 10; i = i + 1 { tree.insert_at(i, i) }
  tree.delete_range(3, 7)
  inspect(tree.span(), content="6")
  inspect(tree.get_at(0), content="Some(0)")
  inspect(tree.get_at(3), content="Some(7)")
}
```

- [ ] **Step 2: Implement set_at and delete_range**

`set_at`: implement `OrderNode::set_in_node(pos, item) -> T?` that navigates to the leaf and performs in-place replacement (`items[idx] = new_item`), returning the old item. This is separate from `navigate` (which returns a copy). Since Phase 1a has `span() == 1`, no span propagation needed. (Add span propagation for Phase 1b when `span(new) != span(old)`.)

`delete_range`: loop `delete_at(start)` for `end - start` times. Simple O(k log n) implementation.

- [ ] **Step 3: Run tests**

Run: `moon test -f order_tree_test.mbt`
Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "feat: add set_at and delete_range"
```

---

### Task 7: Iteration (`iter`, `each`, `to_array`)

**Files:**
- Create: `order-tree/src/iter.mbt`
- Modify: `order-tree/src/order_tree_test.mbt`

- [ ] **Step 1: Write failing tests**

```moonbit
///|
test "to_array returns items in order" {
  let tree : OrderTree[TItem] = OrderTree::new()
  for i = 0; i < 5; i = i + 1 { tree.insert_at(i, i) }
  inspect(tree.to_array(), content="[0, 1, 2, 3, 4]")
}

///|
test "each visits items in order" {
  let tree : OrderTree[TItem] = OrderTree::new()
  for i = 0; i < 5; i = i + 1 { tree.insert_at(i, i) }
  let result : Array[Int] = []
  tree.each(fn(item) { result.push(item) })
  inspect(result, content="[0, 1, 2, 3, 4]")
}

///|
test "iter yields items lazily" {
  let tree : OrderTree[TItem] = OrderTree::new()
  for i = 0; i < 5; i = i + 1 { tree.insert_at(i, i) }
  let result = tree.iter().collect()
  inspect(result, content="[0, 1, 2, 3, 4]")
}
```

- [ ] **Step 2: Implement iteration**

`order-tree/src/iter.mbt`:
- `OrderNode::each(f)` — recursive in-order leaf walk
- `OrderTree::each(f)` — delegate to root
- `OrderTree::to_array()` — collect via `each`
- `OrderTree::iter() -> Iter[T]` — build `Iter` using MoonBit's CPS-based `Iter` type: `Iter::new(fn(yield_) { self.each(fn(item) { match yield_(item) { IterEnd => abort("") | IterContinue => () } }); IterContinue })`. Alternatively, implement via `each` using the standard pattern from the codebase. Check `rle/src/rle.mbt` lines 211-213 for reference.

- [ ] **Step 3: Run tests**

Run: `moon test -f order_tree_test.mbt`
Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "feat: add iter, each, to_array"
```

---

### Task 8: Bulk build (`from_array`)

**Files:**
- Create: `order-tree/src/bulk_build.mbt`
- Modify: `order-tree/src/order_tree_test.mbt`

- [ ] **Step 1: Write failing tests**

```moonbit
///|
test "from_array empty" {
  let tree : OrderTree[TItem] = OrderTree::from_array([])
  inspect(tree.is_empty(), content="true")
}

///|
test "from_array single item" {
  let tree = OrderTree::from_array([42])
  inspect(tree.span(), content="1")
  inspect(tree.get_at(0), content="Some(42)")
}

///|
test "from_array roundtrip" {
  let items = Array::makei(100, fn(i) { i })
  let tree = OrderTree::from_array(items)
  inspect(tree.span(), content="100")
  inspect(tree.to_array() == items, content="true")
}

///|
test "from_array with min_degree=2 maintains invariants" {
  let tree : OrderTree[TItem] = OrderTree::from_array(
    Array::makei(20, fn(i) { i }),
    min_degree=2,
  )
  inspect(tree.span(), content="20")
  // Verify roundtrip
  for i = 0; i < 20; i = i + 1 {
    inspect(tree.get_at(i) == Some(i), content="true")
  }
}
```

- [ ] **Step 2: Implement from_array**

Signature:
```moonbit
pub fn[T : @rle.Spanning] OrderTree::from_array(
  items : Array[T],
  min_degree? : Int = default_min_degree,
) -> OrderTree[T]
```

`order-tree/src/bulk_build.mbt`:
1. If empty, return empty tree
2. Partition items into leaf groups of `max_items = 2 * min_degree - 1`. Redistribute last group if underfull.
3. Create `Leaf` nodes from each group.
4. While more than one node: group nodes into internal-node-sized batches (`max_children = 2 * min_degree`). Build `Internal` nodes with `counts` from children's `total` values. Redistribute last group if underfull.
5. Return tree with single remaining node as root.

- [ ] **Step 3: Run tests**

Run: `moon test -f order_tree_test.mbt`
Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "feat: add from_array bulk build"
```

---

### Task 9: B-tree invariant checks (whitebox tests)

**Files:**
- Create: `order-tree/src/invariant_wbtest.mbt`

- [ ] **Step 1: Write invariant checking functions and tests**

```moonbit
///|
/// Verify B-tree invariants:
/// 1. All leaves are at the same depth
/// 2. Non-root nodes have [t-1, 2t-1] items (leaves) or [t, 2t] children (internal)
/// 3. counts[i] == children[i].total for all internal nodes
/// 4. total == sum of item spans (leaves) or sum of counts (internal)
fn[T : @rle.Spanning] check_invariants(tree : OrderTree[T]) -> Bool {
  // implement
}

///|
test "invariants hold after sequential inserts" {
  let tree : OrderTree[TItem] = OrderTree::new(min_degree=2)
  for i = 0; i < 50; i = i + 1 {
    tree.insert_at(i, i)
    inspect(check_invariants(tree), content="true")
  }
}

///|
test "invariants hold after sequential deletes" {
  let tree : OrderTree[TItem] = OrderTree::new(min_degree=2)
  for i = 0; i < 50; i = i + 1 { tree.insert_at(i, i) }
  for i = 0; i < 50; i = i + 1 {
    ignore(tree.delete_at(0))
    inspect(check_invariants(tree), content="true")
  }
}

///|
test "invariants hold after from_array" {
  for n = 0; n < 100; n = n + 1 {
    let tree = OrderTree::from_array(Array::makei(n, fn(i) { i }), min_degree=2)
    inspect(check_invariants(tree), content="true")
  }
}
```

- [ ] **Step 2: Run tests**

Run: `moon test -f invariant_wbtest.mbt`
Expected: PASS

- [ ] **Step 3: Commit**

```bash
git add -A && git commit -m "test: add B-tree invariant whitebox tests"
```

---

### Task 10: QuickCheck property tests

**Files:**
- Create: `order-tree/src/properties_wbtest.mbt` (whitebox — needs access to `check_invariants` from Task 9)

- [ ] **Step 1: Write property tests**

```moonbit
///|
test "property: insert then get roundtrip" {
  // Generate random (position, value) pairs, insert, verify get_at returns value
}

///|
test "property: delete reduces span by 1" {
  // Build tree from random array, delete random position, check span decreased
}

///|
test "property: from_array then to_array roundtrips" {
  // Generate random array, build tree, verify to_array matches input
}

///|
test "property: random insert/delete sequence maintains invariants" {
  // Generate sequence of insert_at and delete_at operations
  // After each operation, verify check_invariants returns true
}
```

Use `@qc.run()` with appropriate generators. Each property should run ~100 iterations.

- [ ] **Step 2: Run tests**

Run: `moon test -f properties_wbtest.mbt`
Expected: PASS

- [ ] **Step 3: Commit**

```bash
git add -A && git commit -m "test: add QuickCheck property tests"
```

---

### Task 11: Benchmarks

**Files:**
- Create: `order-tree/src/order_tree_benchmark.mbt`

- [ ] **Step 1: Write benchmarks**

Include concrete benchmarks for:

1. **Sequential insert** (1000, 10000): insert items at end
2. **Random insert** (1000): pre-compute random positions, insert at each
3. **Random get** (1000): build tree, look up random positions
4. **Sequential delete** (1000): build tree, delete from position 0 repeatedly
5. **Random delete** (1000): build tree, delete at random positions
6. **delete_range** (1000): build tree, remove range [250, 750)
7. **from_array** (1000, 10000): bulk build
8. **iter** (1000, 10000): full traversal
9. **min_degree tuning**: insert+get+delete 1000 items at min_degree = 2, 5, 10, 16, 32

For random positions, use a simple LCG or pre-computed array to avoid measuring RNG overhead. Example:

```moonbit
///|
fn pseudo_random_positions(n : Int, max : Int) -> Array[Int] {
  let positions : Array[Int] = []
  let mut seed = 12345
  for i = 0; i < n; i = i + 1 {
    seed = (seed * 1103515245 + 12345) % 2147483648
    let bound = if max - i > 0 { max - i } else { 1 }
    positions.push(seed % bound)
  }
  positions
}
```

- [ ] **Step 2: Run benchmarks**

Run: `moon bench --release`
Record results. Compare against tree_structure_zoo BTree for same workloads.

- [ ] **Step 3: Commit**

```bash
git add -A && git commit -m "bench: add OrderTree performance benchmarks with random access and min_degree tuning"
```

---

### Task 12: Format, interfaces, and final cleanup

**Files:**
- All files in `order-tree/src/`

- [ ] **Step 1: Run full test suite**

Run: `moon test`
Expected: All pass

- [ ] **Step 2: Update interfaces and format**

Run: `moon info && moon fmt`

- [ ] **Step 3: Verify .mbti API surface**

Run: `cat src/pkg.generated.mbti`
Expected: All public methods listed

- [ ] **Step 4: Final commit**

```bash
git add -A && git commit -m "chore: moon info + moon fmt, finalize API"
```

---

## Verification Checklist

- [ ] `moon check` — 0 errors
- [ ] `moon test` — all tests pass
- [ ] `moon bench --release` — benchmarks recorded
- [ ] `moon info && moon fmt` — interfaces and formatting clean
- [ ] B-tree invariants hold for all test cases
- [ ] Property tests pass (100+ random sequences)
- [ ] Performance comparable to tree_structure_zoo B-tree
