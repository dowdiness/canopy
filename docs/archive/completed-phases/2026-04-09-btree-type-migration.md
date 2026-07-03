# B-tree Type Migration (Phase 2b) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate ~1,100 lines of duplicate B-tree code in order-tree by wrapping `@btree.BTree[T]` internally and delegating to its API.

**Architecture:** `OrderTree[T]` gains a single `tree : @btree.BTree[T]` field instead of duplicating `root`, `min_degree`, `size`. Public API methods delegate to `BTree`'s high-level operations (`mutate_for_insert`, `mutate_for_delete`, `view`, `seek`, etc.). RLE-specific leaf computation functions stay in order-tree and become callbacks to `BTree`'s mutation API. Duplicate walker files (types, descend, propagate, range, navigate) are deleted.

**Tech Stack:** MoonBit, dowdiness/btree, dowdiness/rle

---

## Key Design Decisions

### OrderTree wraps BTree (not just type substitution)

`OrderTree[T]` holds `tree : @btree.BTree[T]` rather than changing field types in-place. This lets `insert_at`/`delete_at` delegate to `BTree::mutate_for_insert`/`mutate_for_delete` with RLE callbacks, eliminating the need to call raw `descend`/`propagate` functions.

### RLE leaf functions become BTree callbacks

`compute_insert_splice` returns `@btree.Splice[T]` (matching `mutate_for_insert`'s callback signature). `compute_delete_splice` returns `(@btree.Splice[T], T)` (matching `mutate_for_delete`'s callback signature). The old `InsertLeafResult`/`DeleteLeafResult` wrapper types are eliminated.

### propagate leaf_delta derivation

lib/btree's `propagate` derives `leaf_delta` from the splice (`new_leaves.length() - (end_idx - start_idx)`). This produces identical values to order-tree's explicit `leaf_delta` parameter for all RLE splice computations. Verified by checking every return path in `compute_insert_splice` and `compute_delete_splice`.

### delete_range stays partially manual

`OrderTree::delete_range` still accesses `self.tree.root` and `self.tree.size` directly because `plan_delete_range` (order-tree-local, moves to lib/btree in Phase 2c) needs the raw root node. This is acceptable — Phase 2c will provide a proper `BTree::delete_range` API.

### Type constructors via `using`

Files with heavy pattern matching on `BTreeNode` use `using @btree { type BTreeNode }` to bring `Leaf(...)` and `Internal(...)` constructors into scope. Files with lighter usage use `@btree.` prefix.

---

## File Map

### Files to CREATE

None.

### Files to MODIFY

| File | Change |
|------|--------|
| `order-tree/moon.mod.json` | Add `dowdiness/btree` dependency |
| `order-tree/src/moon.pkg` | Add `@btree` import |
| `order-tree/src/types.mbt` | Replace `OrderTree[T]` struct (wrap `BTree[T]`), delete `OrderNode[T]`, `FindResult[T]` |
| `order-tree/src/walker_insert.mbt` | Use `@btree` types, return `@btree.Splice[T]` instead of `InsertLeafResult` |
| `order-tree/src/walker_delete.mbt` | Use `@btree` types, return `(@btree.Splice[T], T)` instead of `DeleteLeafResult` |
| `order-tree/src/insert.mbt` | Delegate to `self.tree.mutate_for_insert` |
| `order-tree/src/delete.mbt` | Delegate to `self.tree.mutate_for_delete`, delete `normalize_root_after_delete` |
| `order-tree/src/order_tree.mbt` | Delegate to `self.tree.*`, use `@btree.BTreeElem` bounds |
| `order-tree/src/bulk_build.mbt` | Use `@btree` types, return `OrderTree` wrapping a `BTree` |
| `order-tree/src/iter.mbt` | Delegate to `self.tree.each`/`to_array`/`iter` |
| `order-tree/src/utils.mbt` | Delete `OrderNode::total/is_full`, `Array::remove_at/insert_at`; keep `Array::sum`, `must_slice`, slot finders |
| `order-tree/src/walker_range_delete.mbt` | Use `@btree` types/functions, absorb `shared_prefix_length`+`lowest_common_ancestor_range` from deleted walker_range.mbt |
| `order-tree/src/invariant_wbtest.mbt` | Use `@btree.BTreeNode[T]` |
| `order-tree/src/properties_wbtest.mbt` | Use updated `OrderTree` API |
| `order-tree/src/walker_wbtest.mbt` | Use `@btree` types and functions |
| `order-tree/src/order_tree_test.mbt` | Use updated `OrderTree` API |
| `order-tree/src/order_tree_benchmark.mbt` | Use updated `OrderTree` API |

### Files to DELETE

| File | Reason |
|------|--------|
| `order-tree/src/walker_types.mbt` | All types now from `@btree` |
| `order-tree/src/walker_descend.mbt` | All functions now from `@btree` (slot finders kept in utils.mbt) |
| `order-tree/src/walker_propagate.mbt` | All functions now from `@btree` |
| `order-tree/src/walker_range.mbt` | Helpers moved to `walker_range_delete.mbt` |
| `order-tree/src/navigate.mbt` | Callers (`OrderTree::find`/`get_at`) now delegate to `BTree::find`/`get_at` which call `@btree`'s internal `navigate` |

---

## Task 0: Widen lib/btree struct visibility for cross-package construction

**Files:**
- Modify: `lib/btree/types.mbt`
- Modify: `lib/btree/walker_types.mbt`

**Why:** MoonBit's `pub struct` fields are read-only from outside the defining package. Order-tree needs to construct `Splice`, `NodeSplice`, `PathFrame`, `Cursor` as struct literals and write to `BTree`'s `mut root`/`mut size` fields. Without `pub(all)`, these operations fail at compile time.

- [ ] **Step 1: Change types.mbt structs to pub(all)**

In `lib/btree/types.mbt`, change `BTree[T]` and `FindResult[T]`:

```moonbit
pub(all) struct BTree[T] {
  mut root : BTreeNode[T]?
  min_degree : Int
  mut size : Int
} derive(Debug, Eq)

pub(all) struct FindResult[T] {
  elem : T
  offset : Int
} derive(Debug, Eq)
```

- [ ] **Step 2: Change walker_types.mbt structs to pub(all)**

In `lib/btree/walker_types.mbt`, change the following structs from `pub struct` to `pub(all) struct`:

- `PathFrame[T]`
- `Cursor[T]`
- `LeafCursor[T]`
- `NodeSplice[T]`
- `LeafContext[T]`
- `Splice[T]`
- `PropagateResult[T]`

Leave `AncestorRange[T]` as `priv struct` (order-tree will define its own copy).

- [ ] **Step 3: Run moon check and moon test in lib/btree**

```bash
cd lib/btree && moon check && moon test
```

Expected: PASS — widening visibility is backward-compatible.

- [ ] **Step 4: Update interfaces and commit**

```bash
cd lib/btree && moon info && moon fmt
git add -A
git commit -m "refactor: widen lib/btree struct visibility to pub(all)

Enables cross-package construction by order-tree during type migration.
Prerequisite for Phase 2b."
```

---

## Task 1: Add btree dependency

**Files:**
- Modify: `order-tree/moon.mod.json`
- Modify: `order-tree/src/moon.pkg`

- [ ] **Step 1: Add btree to moon.mod.json**

In `order-tree/moon.mod.json`, add the btree dependency:

```json
{
  "name": "dowdiness/order-tree",
  "version": "0.1.0",
  "source": "src",
  "deps": {
    "dowdiness/rle": { "path": "../rle" },
    "dowdiness/btree": { "path": "../lib/btree" },
    "moonbitlang/quickcheck": "0.11.2"
  },
  "readme": "README.md",
  "license": "Apache-2.0",
  "keywords": ["btree", "order-statistic", "data-structure"],
  "description": "Order-statistic B-tree with O(log n) position-indexed operations"
}
```

- [ ] **Step 2: Add btree import to moon.pkg**

In `order-tree/src/moon.pkg`, add the btree import:

```
import {
  "dowdiness/btree" @btree,
  "dowdiness/rle" @rle,
  "moonbitlang/core/bench" @bench,
  "moonbitlang/core/debug" @debug,
}

import {
  "moonbitlang/core/quickcheck",
} for "test"

warnings = "-15-2"
```

- [ ] **Step 3: Verify compilation**

Run: `cd order-tree && moon check`
Expected: PASS (new import is unused but `-15` suppresses warnings)

- [ ] **Step 4: Commit**

```bash
cd order-tree && git add moon.mod.json src/moon.pkg
git commit -m "chore: add dowdiness/btree dependency to order-tree"
```

---

## Task 2: Restructure OrderTree to wrap BTree

**Files:**
- Modify: `order-tree/src/types.mbt`

This task changes the `OrderTree[T]` struct to hold a `BTree[T]` internally. Everything else breaks — subsequent tasks fix the breakage.

- [ ] **Step 1: Rewrite types.mbt**

Replace the entire content of `order-tree/src/types.mbt` with:

```moonbit
///|
/// Order-statistic B-tree: a position-indexed sequence with O(log n) operations.
/// Items are ordered by insertion position, not by key comparison.
/// Wraps a generic `@btree.BTree[T]` and adds RLE-specific merge semantics.
pub struct OrderTree[T] {
  tree : @btree.BTree[T]
} derive(Debug, Eq)
```

This removes:
- `FindResult[T]` — use `@btree.FindResult[T]`
- `OrderNode[T]` — use `@btree.BTreeNode[T]`
- `DEFAULT_MIN_DEGREE` — use `@btree.BTree::new()` which has its own default
- `Show for FindResult` — `@btree` provides this

- [ ] **Step 2: Run moon check (expect failures)**

Run: `cd order-tree && moon check 2>&1 | head -30`
Expected: Many compilation errors. This is expected — the next tasks fix them.

---

## Task 3: Migrate RLE leaf computations

**Files:**
- Modify: `order-tree/src/walker_insert.mbt`
- Modify: `order-tree/src/walker_delete.mbt`

These files contain RLE-specific logic that stays in order-tree but needs to use `@btree` types. The return types change to match `BTree`'s callback signatures.

- [ ] **Step 1: Rewrite walker_insert.mbt**

The function changes:
- Takes `@btree.LeafContext[T]` (was local `LeafContext[T]`)
- Returns `@btree.Splice[T]` (was `InsertLeafResult[T]` with `splice` + `leaf_delta`)
- Calls `@btree.LeafContext::left_neighbor`/`right_neighbor` (was local methods)
- Calls `must_slice` (stays local in utils.mbt)
- `leaf_delta` field is eliminated — `BTree::propagate` derives it from the splice

```moonbit
///|
fn[T : @btree.BTreeElem] compute_insert_splice(
  ctx : @btree.LeafContext[T],
  elem : T,
) -> @btree.Splice[T] {
  let elem_span = @rle.Spanning::span(elem)
  if ctx.offset == 0 {
    match ctx.left_neighbor() {
      Some(left_elem) =>
        if @rle.Mergeable::can_merge(left_elem, elem) {
          let merged_left = @rle.Mergeable::merge(left_elem, elem)
          let merged_left_span = @rle.Spanning::span(merged_left)
          let new_leaves : Array[(T, Int)] = [
            (merged_left, merged_left_span),
          ]
          match @rle.Mergeable::can_merge(merged_left, ctx.elem) {
            true => {
              let merged = @rle.Mergeable::merge(merged_left, ctx.elem)
              return {
                start_idx: ctx.child_idx - 1,
                end_idx: ctx.child_idx + 1,
                new_leaves: [(merged, @rle.Spanning::span(merged))],
              }
            }
            false => {
              new_leaves.push((ctx.elem, ctx.span))
              return {
                start_idx: ctx.child_idx - 1,
                end_idx: ctx.child_idx + 1,
                new_leaves,
              }
            }
          }
        }
      None => ()
    }
    if @rle.Mergeable::can_merge(elem, ctx.elem) {
      let merged = @rle.Mergeable::merge(elem, ctx.elem)
      return {
        start_idx: ctx.child_idx,
        end_idx: ctx.child_idx + 1,
        new_leaves: [(merged, @rle.Spanning::span(merged))],
      }
    }
    return {
      start_idx: ctx.child_idx,
      end_idx: ctx.child_idx,
      new_leaves: [(elem, elem_span)],
    }
  }
  if ctx.offset == ctx.span {
    if @rle.Mergeable::can_merge(ctx.elem, elem) {
      let merged_current = @rle.Mergeable::merge(ctx.elem, elem)
      match ctx.right_neighbor() {
        Some(right_elem) =>
          if @rle.Mergeable::can_merge(merged_current, right_elem) {
            let merged = @rle.Mergeable::merge(merged_current, right_elem)
            return {
              start_idx: ctx.child_idx,
              end_idx: ctx.child_idx + 2,
              new_leaves: [(merged, @rle.Spanning::span(merged))],
            }
          }
        None => ()
      }
      return {
        start_idx: ctx.child_idx,
        end_idx: ctx.child_idx + 1,
        new_leaves: [(merged_current, @rle.Spanning::span(merged_current))],
      }
    }
    match ctx.right_neighbor() {
      Some(right_elem) =>
        if @rle.Mergeable::can_merge(elem, right_elem) {
          let merged = @rle.Mergeable::merge(elem, right_elem)
          return {
            start_idx: ctx.child_idx + 1,
            end_idx: ctx.child_idx + 2,
            new_leaves: [(merged, @rle.Spanning::span(merged))],
          }
        }
      None => ()
    }
    return {
      start_idx: ctx.child_idx + 1,
      end_idx: ctx.child_idx + 1,
      new_leaves: [(elem, elem_span)],
    }
  }

  let left_part = must_slice(ctx.elem, start=0, end=ctx.offset)
  let right_part = must_slice(ctx.elem, start=ctx.offset, end=ctx.span)
  let right_span = @rle.Spanning::span(right_part)
  let new_leaves : Array[(T, Int)] = []
  let mut current = left_part
  let mut current_span = @rle.Spanning::span(current)
  if @rle.Mergeable::can_merge(current, elem) {
    current = @rle.Mergeable::merge(current, elem)
    current_span = @rle.Spanning::span(current)
  } else {
    new_leaves.push((current, current_span))
    current = elem
    current_span = elem_span
  }
  if @rle.Mergeable::can_merge(current, right_part) {
    current = @rle.Mergeable::merge(current, right_part)
    current_span = @rle.Spanning::span(current)
    new_leaves.push((current, current_span))
  } else {
    new_leaves.push((current, current_span))
    new_leaves.push((right_part, right_span))
  }
  { start_idx: ctx.child_idx, end_idx: ctx.child_idx + 1, new_leaves }
}
```

- [ ] **Step 2: Rewrite walker_delete.mbt**

The function changes:
- Takes `@btree.LeafContext[T]`
- Returns `(@btree.Splice[T], T)` — tuple of splice and deleted element (matching `mutate_for_delete`'s callback signature)
- `DeleteLeafResult[T]` is eliminated

```moonbit
///|
fn[T : @btree.BTreeElem] compute_delete_splice(
  ctx : @btree.LeafContext[T],
) -> (@btree.Splice[T], T) {
  if ctx.span == 1 {
    match (ctx.left_neighbor(), ctx.right_neighbor()) {
      (Some(left_elem), Some(right_elem)) =>
        if @rle.Mergeable::can_merge(left_elem, right_elem) {
          let merged = @rle.Mergeable::merge(left_elem, right_elem)
          return (
            {
              start_idx: ctx.child_idx - 1,
              end_idx: ctx.child_idx + 2,
              new_leaves: [(merged, @rle.Spanning::span(merged))],
            },
            ctx.elem,
          )
        }
      _ => ()
    }
    return (
      {
        start_idx: ctx.child_idx,
        end_idx: ctx.child_idx + 1,
        new_leaves: [],
      },
      ctx.elem,
    )
  }
  if ctx.offset == 0 {
    let deleted = must_slice(ctx.elem, start=0, end=1)
    let rest = must_slice(ctx.elem, start=1, end=ctx.span)
    match ctx.left_neighbor() {
      Some(left_elem) =>
        if @rle.Mergeable::can_merge(left_elem, rest) {
          let merged = @rle.Mergeable::merge(left_elem, rest)
          return (
            {
              start_idx: ctx.child_idx - 1,
              end_idx: ctx.child_idx + 1,
              new_leaves: [(merged, @rle.Spanning::span(merged))],
            },
            deleted,
          )
        }
      None => ()
    }
    return (
      {
        start_idx: ctx.child_idx,
        end_idx: ctx.child_idx + 1,
        new_leaves: [(rest, @rle.Spanning::span(rest))],
      },
      deleted,
    )
  }
  if ctx.offset == ctx.span - 1 {
    let deleted = must_slice(ctx.elem, start=ctx.span - 1, end=ctx.span)
    let rest = must_slice(ctx.elem, start=0, end=ctx.span - 1)
    match ctx.right_neighbor() {
      Some(right_elem) =>
        if @rle.Mergeable::can_merge(rest, right_elem) {
          let merged = @rle.Mergeable::merge(rest, right_elem)
          return (
            {
              start_idx: ctx.child_idx,
              end_idx: ctx.child_idx + 2,
              new_leaves: [(merged, @rle.Spanning::span(merged))],
            },
            deleted,
          )
        }
      None => ()
    }
    return (
      {
        start_idx: ctx.child_idx,
        end_idx: ctx.child_idx + 1,
        new_leaves: [(rest, @rle.Spanning::span(rest))],
      },
      deleted,
    )
  }

  let deleted = must_slice(ctx.elem, start=ctx.offset, end=ctx.offset + 1)
  let left_part = must_slice(ctx.elem, start=0, end=ctx.offset)
  let right_part = must_slice(ctx.elem, start=ctx.offset + 1, end=ctx.span)
  if @rle.Mergeable::can_merge(left_part, right_part) {
    let merged = @rle.Mergeable::merge(left_part, right_part)
    return (
      {
        start_idx: ctx.child_idx,
        end_idx: ctx.child_idx + 1,
        new_leaves: [(merged, @rle.Spanning::span(merged))],
      },
      deleted,
    )
  }
  (
    {
      start_idx: ctx.child_idx,
      end_idx: ctx.child_idx + 1,
      new_leaves: [
        (left_part, @rle.Spanning::span(left_part)),
        (right_part, @rle.Spanning::span(right_part)),
      ],
    },
    deleted,
  )
}
```

- [ ] **Step 3: Run moon check (expect fewer failures)**

Run: `cd order-tree && moon check 2>&1 | head -30`
Expected: Remaining failures from files not yet migrated.

---

## Task 4: Migrate insert and delete API

**Files:**
- Modify: `order-tree/src/insert.mbt`
- Modify: `order-tree/src/delete.mbt`

These methods now delegate to `BTree::mutate_for_insert`/`mutate_for_delete` with RLE callbacks.

- [ ] **Step 1: Rewrite insert.mbt**

```moonbit
///|
/// Insert an element at the given position in the tree.
/// Position is clamped to [0, span()]. Element must have span > 0.
pub fn[T : @btree.BTreeElem] OrderTree::insert_at(
  self : OrderTree[T],
  pos : Int,
  elem : T,
) -> Unit {
  let elem_span = @rle.Spanning::span(elem)
  guard elem_span > 0 else { return }
  let span = self.tree.span()
  let clamped_pos = if pos < 0 {
    0
  } else if pos > span {
    span
  } else {
    pos
  }
  if self.tree.is_empty() {
    self.tree.init_root(elem, elem_span)
  } else {
    self.tree.mutate_for_insert(clamped_pos, fn(ctx) {
      compute_insert_splice(ctx, elem)
    })
  }
}
```

- [ ] **Step 2: Rewrite delete.mbt**

Delete the `normalize_root_after_delete` function — `@btree` provides it.

```moonbit
///|
/// Delete the element at the given span position from the tree.
/// Returns a single-unit slice of the deleted element.
pub fn[T : @btree.BTreeElem] OrderTree::delete_at(
  self : OrderTree[T],
  pos : Int,
) -> T? {
  self.tree.mutate_for_delete(pos, fn(ctx) { compute_delete_splice(ctx) })
}
```

- [ ] **Step 3: Run moon check**

Run: `cd order-tree && moon check 2>&1 | head -30`
Expected: Remaining failures from order_tree.mbt and other unmigrated files.

---

## Task 5: Migrate public API and iteration

**Files:**
- Modify: `order-tree/src/order_tree.mbt`
- Modify: `order-tree/src/iter.mbt`

- [ ] **Step 1: Rewrite order_tree.mbt**

Most methods delegate to `self.tree.*`. `delete_range` and `delete_range_needs_merge_rebuild` still access `self.tree.root` directly (cleaned up in Phase 2c). Trait bounds change from `T : @rle.Spanning + @rle.Mergeable + @rle.Sliceable` to `T : @btree.BTreeElem`.

```moonbit
///|
pub fn[T] OrderTree::new(
  min_degree? : Int,
) -> OrderTree[T] {
  { tree: @btree.BTree::new(min_degree?) }
}

///|
/// Total leaf entries (number of runs).
pub fn[T] OrderTree::size(self : OrderTree[T]) -> Int {
  self.tree.size()
}

///|
pub impl[T] @rle.HasLength for OrderTree[T] with is_empty(self : OrderTree[T]) -> Bool {
  self.tree.is_empty()
}

///|
/// HasLength: number of leaf entries (same as size).
pub impl[T] @rle.HasLength for OrderTree[T] with length(self) -> Int {
  self.tree.size()
}

///|
/// Spanning: total span across all elements. O(1) via cached root total.
pub impl[T] @rle.Spanning for OrderTree[T] with span(self) -> Int {
  self.tree.span()
}

///|
/// Spanning: logical_length defaults to span for now.
pub impl[T] @rle.Spanning for OrderTree[T] with logical_length(self) -> Int {
  self.tree.span()
}

///|
/// Get the element at span position. Aliased as `tree[pos]`.
#alias("_[_]")
pub fn[T] OrderTree::get_at(self : OrderTree[T], pos : Int) -> T? {
  self.tree.get_at(pos)
}

///|
pub fn[T] OrderTree::find(
  self : OrderTree[T],
  pos : Int,
) -> @btree.FindResult[T]? {
  self.tree.find(pos)
}

///|
/// Replace the element at the given span position.
/// Returns the old single-unit slice, or None if out of bounds.
/// Implemented as delete_at + insert_at to ensure neighbor merging.
pub fn[T : @btree.BTreeElem] OrderTree::set_at(
  self : OrderTree[T],
  pos : Int,
  elem : T,
) -> T? {
  if pos < 0 {
    return None
  }
  let deleted = self.delete_at(pos)
  match deleted {
    Some(_) => {
      self.insert_at(pos, elem)
      deleted
    }
    None => None
  }
}

///|
/// Index setter: `tree[pos] = elem`. Discards the old value.
pub fn[T : @btree.BTreeElem] OrderTree::op_set(
  self : OrderTree[T],
  pos : Int,
  elem : T,
) -> Unit {
  ignore(self.set_at(pos, elem))
}

///|
/// View operator: `tree[start:end]` returns elements in span range [start, end).
/// Slices at boundaries. Uses one descent, then walks leaves in order.
#alias("_[_:_]")
pub fn[T : @btree.BTreeElem] OrderTree::view(
  self : OrderTree[T],
  start? : Int = 0,
  end? : Int,
) -> Array[T] {
  self.tree.view(start?, end?)
}

///|
fn[T : @btree.BTreeElem] delete_range_needs_merge_rebuild(
  root : @btree.BTreeNode[T],
  start : Int,
  end_ : Int,
) -> Bool {
  let mut left_kept : T? = None
  let mut right_kept : T? = None
  root.each_slice_in_range(0, start, fn(elem) { left_kept = Some(elem) })
  root.each_slice_in_range(end_, root.total(), fn(elem) {
    if right_kept is None {
      right_kept = Some(elem)
    }
  })
  match (left_kept, right_kept) {
    (Some(left), Some(right)) => @rle.Mergeable::can_merge(left, right)
    _ => false
  }
}

///|
/// Delete all elements in the span range [start, end_).
pub fn[T : @btree.BTreeElem] OrderTree::delete_range(
  self : OrderTree[T],
  start : Int,
  end_ : Int,
) -> Unit {
  match self.tree.root {
    None => ()
    Some(root) => {
      let total = root.total()
      if start < 0 || start >= end_ || start >= total {
        return
      }
      let rebuild = fn() {
        let end = if end_ > total { total } else { end_ }
        let kept : Array[T] = []
        root.each_slice_in_range(0, start, fn(elem) { kept.push(elem) })
        root.each_slice_in_range(end, total, fn(elem) { kept.push(elem) })
        let rebuilt = OrderTree::from_array(kept, min_degree=self.tree.min_degree)
        self.tree.root = rebuilt.tree.root
        self.tree.size = rebuilt.tree.size
      }
      match plan_delete_range(root, start, end_, self.tree.min_degree) {
        None => rebuild()
        Some(splice) => {
          let new_child_count = splice.original_child_count -
            (splice.end_idx - splice.start_idx) +
            splice.new_children.length()
          if (splice.prefix.length() > 0 &&
            new_child_count < self.tree.min_degree) ||
            delete_range_needs_merge_rebuild(root, start, end_) {
            rebuild()
          } else {
            let propagated = @btree.propagate_node_splice(
              splice,
              self.tree.min_degree,
            )
            match propagated.overflow {
              None =>
                self.tree.root = @btree.normalize_root_after_delete(
                  propagated.node,
                )
              Some(sibling) => {
                let left_total = propagated.node.total()
                let right_total = sibling.total()
                self.tree.root = Some(
                  @btree.BTreeNode::Internal(
                    children=[propagated.node, sibling],
                    counts=[left_total, right_total],
                    total=left_total + right_total,
                  ),
                )
              }
            }
            self.tree.size = self.tree.size + propagated.leaf_delta
          }
        }
      }
    }
  }
}
```

- [ ] **Step 2: Rewrite iter.mbt**

```moonbit
///|
/// Call f for each element in the tree in order.
pub fn[T] OrderTree::each(self : OrderTree[T], f : (T) -> Unit) -> Unit {
  self.tree.each(f)
}

///|
/// Collect all elements into an array in order.
pub fn[T] OrderTree::to_array(self : OrderTree[T]) -> Array[T] {
  self.tree.to_array()
}

///|
/// Return a lazy iterator over elements in order.
pub fn[T] OrderTree::iter(self : OrderTree[T]) -> Iter[T] {
  self.tree.iter()
}
```

- [ ] **Step 3: Run moon check**

Run: `cd order-tree && moon check 2>&1 | head -30`
Expected: Remaining failures from bulk_build.mbt, walker_range_delete.mbt, utils.mbt, tests, and the deleted-but-still-present duplicate files.

---

## Task 6: Migrate bulk build

**Files:**
- Modify: `order-tree/src/bulk_build.mbt`

- [ ] **Step 1: Rewrite bulk_build.mbt**

Uses `@btree.BTreeNode[T]` for the bottom-up build, then wraps in an `OrderTree`. The `using` import brings `BTreeNode` constructors into scope.

```moonbit
///|
using @btree { type BTreeNode }

///|
/// Build an OrderTree from an array of elements in O(n) time.
/// Filters zero-span items, pre-merges adjacent mergeable elements,
/// then builds bottom-up.
pub fn[T : @btree.BTreeElem] OrderTree::from_array(
  items : Array[T],
  min_degree? : Int,
) -> OrderTree[T] {
  let t = match min_degree {
    Some(d) => if d < 2 { 2 } else { d }
    None => 10
  }
  if items.is_empty() {
    return OrderTree::new(min_degree=t)
  }
  // Filter zero-span and pre-merge adjacent elements
  let merged : Array[T] = []
  for item in items {
    if @rle.Spanning::span(item) <= 0 {
      continue
    }
    match merged.last() {
      Some(last) =>
        if @rle.Mergeable::can_merge(last, item) {
          merged[merged.length() - 1] = @rle.Mergeable::merge(last, item)
        } else {
          merged.push(item)
        }
      None => merged.push(item)
    }
  }
  if merged.is_empty() {
    return OrderTree::new(min_degree=t)
  }
  // Create one leaf per merged element
  let mut current_layer : Array[BTreeNode[T]] = Array::new(
    capacity=merged.length(),
  )
  for elem in merged {
    let span = @rle.Spanning::span(elem)
    current_layer.push(Leaf(elem~, span~))
  }
  let leaf_count = current_layer.length()
  // Build internal layers bottom-up
  let max_children = 2 * t
  let min_children = t
  while current_layer.length() > 1 {
    let node_count = current_layer.length()
    let child_groups : Array[Array[BTreeNode[T]]] = []
    let mut cstart = 0
    while cstart < node_count {
      let cend = if cstart + max_children >= node_count {
        node_count
      } else {
        cstart + max_children
      }
      let cgroup : Array[BTreeNode[T]] = Array::new(capacity=cend - cstart)
      for i in cstart..<cend {
        cgroup.push(current_layer[i])
      }
      child_groups.push(cgroup)
      cstart = cend
    }
    // Fix last group if too small
    if child_groups.length() >= 2 {
      let last_idx = child_groups.length() - 1
      let last = child_groups[last_idx]
      if last.length() < min_children {
        let prev = child_groups[last_idx - 1]
        let total = prev.length() + last.length()
        let new_prev_count = (total + 1) / 2
        let new_last_count = total - new_prev_count
        let new_last : Array[BTreeNode[T]] = Array::new(
          capacity=new_last_count,
        )
        for i in new_prev_count..<(new_prev_count + new_last_count) {
          if i < prev.length() {
            new_last.push(prev[i])
          } else {
            new_last.push(last[i - prev.length()])
          }
        }
        while prev.length() > new_prev_count {
          ignore(prev.pop())
        }
        child_groups[last_idx] = new_last
      }
    }
    // Create internal nodes
    let next_layer : Array[BTreeNode[T]] = Array::new(
      capacity=child_groups.length(),
    )
    for cgroup in child_groups {
      let counts : Array[Int] = Array::new(capacity=cgroup.length())
      for node in cgroup {
        counts.push(node.total())
      }
      let total = counts.sum()
      next_layer.push(Internal(children=cgroup, counts~, total~))
    }
    current_layer = next_layer
  }
  let mut root_node = current_layer[0]
  // Ensure root is always Internal
  match root_node {
    Leaf(..) => {
      let span = root_node.total()
      root_node = Internal(children=[root_node], counts=[span], total=span)
    }
    Internal(..) => ()
  }
  let btree : @btree.BTree[T] = @btree.BTree::new(min_degree=t)
  btree.root = Some(root_node)
  btree.size = leaf_count
  { tree: btree }
}
```

- [ ] **Step 2: Run moon check**

Run: `cd order-tree && moon check 2>&1 | head -30`

---

## Task 7: Migrate walker_range_delete and clean up utils

**Files:**
- Modify: `order-tree/src/walker_range_delete.mbt`
- Modify: `order-tree/src/utils.mbt`

walker_range_delete.mbt absorbs `shared_prefix_length` and `lowest_common_ancestor_range` from the soon-to-be-deleted walker_range.mbt, and switches all types/functions to `@btree.*`.

- [ ] **Step 1: Rewrite utils.mbt**

Keep only `Array::sum`, `must_slice`, and the slot-finding functions. Delete everything else (now in `@btree`). Add `prepare_noop` for tests that need it.

```moonbit
///|
/// Sum all elements of an Int array.
fn Array::sum(self : Array[Int]) -> Int {
  self.iter().fold(init=0, fn(acc, x) { acc + x })
}

///|
/// Unwrap a Sliceable::slice result, aborting on failure.
fn[T : @rle.Sliceable] must_slice(elem : T, start~ : Int, end~ : Int) -> T {
  match @rle.Sliceable::slice(elem, start~, end~) {
    Ok(result) => result
    Err(_) => abort("OrderTree internal error: slice failed")
  }
}

// === Slot-finding functions for descend callbacks ===
// These are passed to @btree.descend as the find_slot_fn parameter.
// They use order-tree's local ArrayView::find_by_sum helpers.

///|
fn[R] ArrayView::find_by_sum(
  self : ArrayView[Int],
  pos : Int,
  f : (Int, Int) -> R?,
) -> R? {
  for view = self, remaining = pos, i = 0 {
    match (view, remaining, i) {
      ([], _, _) => break None
      ([count, ..], remaining, i) if remaining < count => break f(i, remaining)
      ([count, .. rest], remaining, i) =>
        continue rest, remaining - count, i + 1
    }
  }
}

///|
fn[R] ArrayView::find_by_sum_inclusive(
  self : ArrayView[Int],
  pos : Int,
  f : (Int, Int) -> R?,
) -> R? {
  for view = self, remaining = pos, i = 0 {
    match (view, remaining, i) {
      ([], _, _) => break None
      ([count, ..], remaining, i) if remaining <= count => break f(i, remaining)
      ([count, .. rest], remaining, i) =>
        continue rest, remaining - count, i + 1
    }
  }
}

///|
fn find_slot(counts : Array[Int], pos : Int, _total : Int) -> (Int, Int) {
  if counts.length() == 0 {
    abort("find_slot: empty counts")
  }
  match
    counts[:counts.length() - 1].find_by_sum(pos, fn(i, remaining) {
      Some((i, remaining))
    }) {
    Some(pair) => pair
    None => {
      let last = counts.length() - 1
      (last, pos - (_total - counts[last]))
    }
  }
}

///|
fn find_slot_inclusive(
  counts : Array[Int],
  pos : Int,
  _total : Int,
) -> (Int, Int) {
  if counts.length() == 0 {
    abort("find_slot_inclusive: empty counts")
  }
  match
    counts[:counts.length() - 1].find_by_sum_inclusive(pos, fn(i, remaining) {
      Some((i, remaining))
    }) {
    Some(pair) => pair
    None => {
      let last = counts.length() - 1
      (last, pos - (_total - counts[last]))
    }
  }
}

///|
fn[T] prepare_noop(
  _children : Array[@btree.BTreeNode[T]],
  _counts : Array[Int],
  _idx : Int,
  _min_degree : Int,
) -> Unit {

}
```

- [ ] **Step 2: Rewrite walker_range_delete.mbt**

This file is large (510 lines). The changes are mechanical:
- Replace `OrderNode[T]` → `@btree.BTreeNode[T]` (use `using @btree { type BTreeNode }`)
- Replace `PathFrame[T]` → `@btree.PathFrame[T]`
- Replace `Cursor[T]` → `@btree.Cursor[T]`
- Replace `LeafCursor[T]` → `@btree.LeafCursor[T]`
- Replace `AncestorRange[T]` → use directly (it's `priv` in @btree — need to define locally)
- Replace `NodeSplice[T]` → `@btree.NodeSplice[T]`
- Replace `copy_path` → `@btree.copy_path`
- Replace `descend_leaf_at` → `@btree.descend_leaf_at`
- Replace `descend_leaf_at_end_boundary` → `@btree.descend_leaf_at_end_boundary`
- Replace `descend_leftmost` → `@btree.descend_leftmost`
- Replace `cursor_as_leaf(x).unwrap()` → `@btree.LeafCursor::from_cursor(x)`
- Absorb `shared_prefix_length` and `lowest_common_ancestor_range` from walker_range.mbt
- Add `using @btree { type BTreeNode }` at the top for pattern matching
- Trait bounds change to `T : @btree.BTreeElem`

**Important:** `AncestorRange[T]` is `priv` in lib/btree, so order-tree must keep its own definition. Copy it into this file:

```moonbit
priv struct AncestorRange[T] {
  prefix : Array[@btree.PathFrame[T]]
  children : Array[@btree.BTreeNode[T]]
  counts : Array[Int]
  start_idx : Int
  end_idx : Int
  child_height : Int
}
```

The full rewrite is mechanical find-and-replace plus absorbing the two functions from walker_range.mbt. Due to the file's size, the executing agent should perform the replacement rather than having the full 510-line file listed here. The key patterns are:

| Find | Replace |
|------|---------|
| `OrderNode[T]` | `BTreeNode[T]` (with `using @btree { type BTreeNode }`) |
| `PathFrame[T]` (struct construction/type) | `@btree.PathFrame[T]` |
| `LeafCursor[T]` (type) | `@btree.LeafCursor[T]` |
| `NodeSplice[T]` (type) | `@btree.NodeSplice[T]` |
| `Cursor[T]` (type) | `@btree.Cursor[T]` |
| `copy_path(` | `@btree.copy_path(` |
| `descend_leaf_at(` | `@btree.descend_leaf_at(` |
| `descend_leaf_at_end_boundary(` | `@btree.descend_leaf_at_end_boundary(` |
| `descend_leftmost(` | `@btree.descend_leftmost(` |
| `cursor_as_leaf(x).unwrap()` | `@btree.LeafCursor::from_cursor(x)` |
| `T : @rle.Spanning + @rle.Mergeable + @rle.Sliceable` | `T : @btree.BTreeElem` |
| `T : @rle.Spanning + @rle.Sliceable` | `T : @btree.BTreeElem` |
| `T : @rle.Spanning + @rle.Mergeable` | `T : @btree.BTreeElem` |
| `T : @rle.Sliceable` | `T : @btree.BTreeElem` |

Also:
- Add the `shared_prefix_length` and `lowest_common_ancestor_range` functions (copied from walker_range.mbt with types updated).
- `descend_rightmost` stays in this file — it constructs `@btree.Cursor[T]` struct literals, which works because Task 0 made `Cursor` `pub(all)`.

- [ ] **Step 3: Run moon check**

Run: `cd order-tree && moon check 2>&1 | head -30`

---

## Task 8: Migrate tests

Tests must be migrated BEFORE deleting the duplicate walker files, because tests reference both old local types and functions. After this task, all test files compile against `@btree` types and the old local files become dead code.

**Files:**
- Modify: `order-tree/src/walker_wbtest.mbt`
- Modify: `order-tree/src/invariant_wbtest.mbt`
- Modify: `order-tree/src/properties_wbtest.mbt`
- Modify: `order-tree/src/order_tree_test.mbt`
- Modify: `order-tree/src/order_tree_benchmark.mbt`

- [ ] **Step 1: Migrate walker_wbtest.mbt**

This is the largest test file (660 lines). The changes are:

1. Add `using @btree { type BTreeNode }` at the top
2. `Run` type: Add `impl @btree.BTreeElem for Run` (empty body — existing rle impls satisfy the super trait)
3. Replace `OrderNode[T]` → `BTreeNode[T]` in all tree construction
4. Replace `Cursor[T]` → `@btree.Cursor[T]` in cursor construction
5. Replace `PathFrame[T]` → `@btree.PathFrame[T]` in path construction
6. Replace `LeafContext::from_cursor` → `@btree.LeafContext::from_cursor`
7. Replace `find_slot(` → local (stays in utils.mbt)
8. Replace `find_slot_inclusive(` → local (stays in utils.mbt)
9. Replace `cursor_as_leaf(x).unwrap()` → `@btree.LeafCursor::from_cursor(x)` (cursor_as_leaf always returns Some, so unwrap is identity)
10. Replace `descend(` → `@btree.descend(`
11. Replace `prepare_noop` → local (stays in utils.mbt)
12. Replace `prepare_ensure_min(` → `@btree.prepare_ensure_min(`
13. Replace `descend_leaf_at(` → `@btree.descend_leaf_at(`
14. Replace `descend_leaf_at_end_boundary(` → `@btree.descend_leaf_at_end_boundary(`
15. Replace `propagate(` → `@btree.propagate(`
16. Replace `propagate_node_splice(` → `@btree.propagate_node_splice(`
17. For `propagate` calls: remove the `leaf_delta` argument (4th param), since `@btree.propagate` takes 3 args
18. **`height()` semantic difference:** `@btree.BTreeNode::height` returns `0` for empty internal nodes (transient state), while the old `OrderNode::height` returned `1`. This only matters during range splicing. Verify the white-box tests at `walker_wbtest.mbt:315` and `:339` (boundary subtree height tests) still pass — if not, adjust expected values or keep a local `height` helper.

- [ ] **Step 2: Migrate invariant_wbtest.mbt**

1. Add `using @btree { type BTreeNode }` at the top
2. `TI` type: Add `impl @btree.BTreeElem for TI` (empty body)
3. Replace `OrderNode[T]` → `BTreeNode[T]` in `leaf_depth`, `check_occupancy`, `check_totals`, `count_leaf_items`, `check_no_adjacent_mergeable`
4. In `check_invariants`: change `tree : OrderTree[T]` to access `tree.tree.root`, `tree.tree.size`, `tree.tree.min_degree`
5. Trait bounds: `T : @rle.Spanning + @rle.Mergeable` → `T : @btree.BTreeElem`

- [ ] **Step 3: Migrate properties_wbtest.mbt**

Minimal changes — `TI` already has `BTreeElem` impl from invariant_wbtest.mbt (same package).

- [ ] **Step 4: Migrate order_tree_test.mbt**

Read the file first. This file defines 4 test types. The primary breakage is that `insert_at`, `delete_at`, `view`, `from_array`, `set_at` now require `T : @btree.BTreeElem` instead of the old `T : @rle.Spanning + @rle.Mergeable + @rle.Sliceable`. All 4 test types already impl all 3 rle traits, so adding the `BTreeElem` impl is an empty body.

Required changes:
1. Add `impl @btree.BTreeElem for TItem` (empty body — `TItem` already impls `Spanning`, `Mergeable`, `Sliceable`)
2. Add `impl @btree.BTreeElem for MItem` (empty body — `MItem` already impls all 3 rle traits)
3. Any direct `tree.root` access → `tree.tree.root`
4. Any direct `tree.size` access → `tree.tree.size`
5. `FindResult` → `@btree.FindResult`
6. Any `OrderNode` references → `@btree.BTreeNode` (add `using @btree { type BTreeNode }` if needed)

- [ ] **Step 5: Migrate order_tree_benchmark.mbt**

Read the file first. Same pattern as order_tree_test.mbt:
1. Add `impl @btree.BTreeElem for BItem` (empty body)
2. Add `impl @btree.BTreeElem for BMItem` (empty body)
3. Any direct struct field access → through `tree.tree.*`

- [ ] **Step 6: Run moon check**

Run: `cd order-tree && moon check 2>&1 | head -30`
Expected: PASS — all files compile against `@btree` types. The old duplicate files are still present but now dead code.

- [ ] **Step 7: Run full test suite**

Run: `cd order-tree && moon test`
Expected: ALL tests pass. The behavior should be identical.

- [ ] **Step 8: Commit**

```bash
cd order-tree && git add -A src/
git commit -m "test: migrate order-tree tests to @btree types

Add BTreeElem impls for Run, TI, TItem, MItem, BItem, BMItem.
Update type references and struct field access paths."
```

---

## Task 9: Delete duplicate files

Now that all source and test files compile against `@btree`, the old duplicate files are dead code. Delete them.

**Files:**
- Delete: `order-tree/src/walker_types.mbt`
- Delete: `order-tree/src/walker_descend.mbt`
- Delete: `order-tree/src/walker_propagate.mbt`
- Delete: `order-tree/src/walker_range.mbt`
- Delete: `order-tree/src/navigate.mbt`

- [ ] **Step 1: Delete all five duplicate files**

```bash
cd order-tree/src
rm walker_types.mbt walker_descend.mbt walker_propagate.mbt walker_range.mbt navigate.mbt
```

- [ ] **Step 2: Run moon check**

Run: `cd order-tree && moon check 2>&1 | head -30`
Expected: PASS. If any references remain (stale calls to now-deleted local functions), fix them by replacing with `@btree.*` equivalents.

- [ ] **Step 3: Run full test suite**

Run: `cd order-tree && moon test`
Expected: ALL tests pass.

- [ ] **Step 4: Commit**

```bash
cd order-tree && git add -A src/
git commit -m "refactor: delete duplicate walker files from order-tree

Removes walker_types.mbt, walker_descend.mbt, walker_propagate.mbt,
walker_range.mbt, navigate.mbt. All functionality now provided by
@btree. OrderTree wraps BTree[T] internally with RLE callbacks."
```

---

## Task 10: Final verification and format

**Files:**
- Modify: `order-tree/src/pkg.generated.mbti` (auto-generated)

- [ ] **Step 1: Run moon info and moon fmt**

```bash
cd order-tree && moon info && moon fmt
```

- [ ] **Step 2: Check API changes**

```bash
cd order-tree && git diff src/pkg.generated.mbti
```

Expected changes:
- `OrderNode[T]` disappears from the API
- `FindResult[T]` disappears (use `@btree.FindResult[T]`)
- `OrderTree[T]` struct shape changes (single `tree` field)
- Trait bounds change to `@btree.BTreeElem`

- [ ] **Step 3: Run order-tree benchmarks**

```bash
cd order-tree && moon bench --release
```

Compare with prior results. No performance regression expected — the code paths are identical, just called through one extra indirection (`BTree` wrapper) which MoonBit should inline.

- [ ] **Step 4: Run parent module tests**

```bash
cd /home/antisatori/ghq/github.com/dowdiness/canopy
git submodule update --init --recursive
moon test
```

If the parent module imports `@order_tree.OrderNode[T]` or `@order_tree.FindResult[T]`, those references need updating. Check for failures and fix.

- [ ] **Step 5: Run event-graph-walker tests**

```bash
cd event-graph-walker && moon test
```

If egw references order-tree types that changed, fix. The `impl @btree.BTreeElem for VisibleRun` should already exist (PR #23 in egw).

- [ ] **Step 6: Format and commit**

```bash
cd order-tree && moon info && moon fmt
git add -A
git commit -m "refactor: format and update interfaces after type migration"
```

---

## Acceptance Criteria

- [ ] `order-tree/src/` has no `OrderNode[T]` enum definition — uses `@btree.BTreeNode[T]`
- [ ] `OrderTree[T]` wraps `@btree.BTree[T]` with a single `tree` field
- [ ] `insert_at` delegates to `BTree::mutate_for_insert` with RLE callback
- [ ] `delete_at` delegates to `BTree::mutate_for_delete` with RLE callback
- [ ] `InsertLeafResult[T]` and `DeleteLeafResult[T]` are eliminated
- [ ] 5 duplicate files deleted: `walker_types`, `walker_descend`, `walker_propagate`, `walker_range`, `navigate`
- [ ] `cd order-tree && moon test` — all existing tests pass
- [ ] `moon test` (parent module) — passes
- [ ] `cd event-graph-walker && moon test` — passes
- [ ] No performance regression in `moon bench --release`

## Line Count Estimate

| Category | Before | After | Delta |
|----------|--------|-------|-------|
| types.mbt | 33 | ~5 | -28 |
| walker_types.mbt | 139 | 0 (deleted) | -139 |
| walker_descend.mbt | 400 | 0 (deleted) | -400 |
| walker_propagate.mbt | 173 | 0 (deleted) | -173 |
| walker_range.mbt | 76 | 0 (deleted) | -76 |
| navigate.mbt | 9 | 0 (deleted) | -9 |
| utils.mbt | 94 | ~70 | -24 |
| insert.mbt | 64 | ~25 | -39 |
| delete.mbt | 58 | ~10 | -48 |
| order_tree.mbt | 221 | ~170 | -51 |
| iter.mbt | 42 | ~15 | -27 |
| walker_range_delete.mbt | 510 | ~530 (absorbs 2 functions) | +20 |
| **Total (source only)** | **1819** | **~825** | **~-994** |

## Risks

- **`pub(all)` prerequisite (Task 0)**: lib/btree structs must be `pub(all)` before order-tree can construct them cross-package. If this is missed, `compute_insert_splice`, `plan_delete_range`, `from_array`, and `delete_range` all fail at compile time. This is the single most critical prerequisite.

- **`pub type OrderNode[T] = @btree.BTreeNode[T]`**: If MoonBit doesn't support parameterized type aliases, consumers referencing `@order_tree.OrderNode[T]` need manual updating. Mitigation: check compilation after types.mbt change.

- **Struct field accessibility**: `BTree[T]` has `pub struct` with `mut root` and `mut size` — order-tree's `delete_range` accesses these directly. If BTree makes fields private in Phase 2d, `delete_range` must be refactored first (Phase 2c).

- **`AncestorRange[T]`**: This type is `priv` in lib/btree. Order-tree must define its own copy until Phase 2c moves `walker_range_delete.mbt` to lib/btree.

- **`height()` empty-internal semantics**: `@btree.BTreeNode::height` returns `0` for `Internal(children=[], ...)` (transient state during range splicing), while order-tree's old `OrderNode::height` returned `1`. This affects `child_height` in `lowest_common_ancestor_range` and boundary subtree height tests. Verify walker_wbtest height assertions still hold. If not, either preserve the old helper locally or update test expectations.

- **Submodule coordination**: Event-graph-walker's `impl BTreeElem for VisibleRun` must be available. Verify the submodule points to the right commit.
