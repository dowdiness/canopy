# Phase 2d: B-tree API Narrowing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix range-delete algorithm bugs, add `BTree::delete_range`, replace eager `iter` with lazy traversal, and narrow the public API to hide walker internals.

**Architecture:** Two algorithm fixes (underfull propagation, post-splice boundary merge) eliminate order-tree's O(n) rebuild fallback and enable a clean `BTree::delete_range(start, end)` method. This lets us make 13 walker functions/types private. A lazy `BTree::iter` using `cursor_next_leaf` replaces the current `to_array`-based implementation. `from_sorted` bulk constructor moves generic bottom-up build logic from order-tree.

**Tech Stack:** MoonBit, dowdiness/btree, dowdiness/rle, dowdiness/order-tree

---

## File Structure

### Modified
- `lib/btree/walker_propagate.mbt` — add `repair_underfull` step in `walk_up_ancestors`
- `lib/btree/walker_range_delete.mbt` — add `normalize_boundary_merge`, remove `promote_empty_child_gap_merge`
- `lib/btree/btree.mbt` — add `BTree::delete_range`, add `BTree::from_sorted`
- `lib/btree/iter.mbt` — rewrite `BTree::iter` as lazy cursor-based traversal
- `lib/btree/walker_descend.mbt` — remove `pub` from 8 functions
- `lib/btree/walker_types.mbt` — remove `pub(all)` from internal types
- `lib/btree/btree_wbtest.mbt` — add tests for underfull repair, boundary merge, delete_range, lazy iter, from_sorted
- `lib/btree/pkg.generated.mbti` — updated by `moon info`
- `order-tree/src/order_tree.mbt` — simplify `delete_range` to call `self.tree.delete_range(start, end)`

### Deleted (code within files)
- `order-tree/src/order_tree.mbt` — `delete_range_needs_merge_rebuild` function (~18 lines), manual propagation logic (~30 lines)

---

## Task 1: Fix underfull propagation in `walk_up_ancestors`

**Files:**
- Modify: `lib/btree/walker_propagate.mbt:100-129`
- Modify: `lib/btree/walker_descend.mbt:158-163` (add `is_underfull`)
- Test: `lib/btree/btree_wbtest.mbt`

The current `walk_up_ancestors` only handles overflow (splits). After a range delete splice removes multiple children, a node can end up with fewer than `min_degree` children. We need to borrow/merge during the upward walk.

- [ ] **Step 1: Write failing tests for underfull repair**

Append to `lib/btree/btree_wbtest.mbt`:

```moonbit
// === Underfull propagation repair ===

///|
test "propagate_node_splice repairs underfull node by borrowing from right" {
  // min_degree=2: each internal needs >= 2 children
  // LCA child has 3 children, we splice out 2 → 1 child (underfull)
  // Right sibling has 3 children → can lend
  let lca_child : BTreeNode[TItem] = Internal(
    children=[
      Leaf(elem=make_item(1, 1), span=1),
      Leaf(elem=make_item(2, 1), span=1),
      Leaf(elem=make_item(3, 1), span=1),
    ],
    counts=[1, 1, 1],
    total=3,
  )
  let right_sibling : BTreeNode[TItem] = Internal(
    children=[
      Leaf(elem=make_item(4, 1), span=1),
      Leaf(elem=make_item(5, 1), span=1),
      Leaf(elem=make_item(6, 1), span=1),
    ],
    counts=[1, 1, 1],
    total=3,
  )
  let root : BTreeNode[TItem] = Internal(
    children=[lca_child, right_sibling],
    counts=[3, 3],
    total=6,
  )
  // Splice removes children 0..2 from lca_child, leaving 1 child (underfull)
  let splice : NodeSplice[TItem] = {
    prefix: [{ children: match root {
      Internal(children~, ..) => children
      _ => abort("expected internal")
    }, counts: match root {
      Internal(counts~, ..) => counts
      _ => abort("expected internal")
    }, child_idx: 0 }],
    children: match lca_child {
      Internal(children~, ..) => children
      _ => abort("expected internal")
    },
    counts: match lca_child {
      Internal(counts~, ..) => counts
      _ => abort("expected internal")
    },
    start_idx: 0,
    end_idx: 2,
    new_children: [],
    original_child_count: 3,
    leaf_delta: -2,
  }
  let result = propagate_node_splice(splice, 2)
  // After repair: underfull node borrowed from right sibling
  // Total span should be 6 - 2 = 4
  inspect(result.node.total(), content="4")
  // Root should still have 2 children (no merge needed at root level)
  match result.node {
    Internal(children~, ..) => {
      inspect(children.length(), content="2")
      // Each child should have >= 2 children
      match children[0] {
        Internal(children=c, ..) => inspect(c.length() >= 2, content="true")
        _ => abort("expected internal")
      }
    }
    _ => abort("expected internal root")
  }
}

///|
test "propagate_node_splice repairs underfull node by merging with sibling" {
  // min_degree=2: each internal needs >= 2 children
  // LCA child has 2 children, we splice out 1 → 1 child (underfull)
  // Right sibling has exactly 2 children → cannot lend, must merge
  let lca_child : BTreeNode[TItem] = Internal(
    children=[
      Leaf(elem=make_item(1, 1), span=1),
      Leaf(elem=make_item(2, 1), span=1),
    ],
    counts=[1, 1],
    total=2,
  )
  let right_sibling : BTreeNode[TItem] = Internal(
    children=[
      Leaf(elem=make_item(3, 1), span=1),
      Leaf(elem=make_item(4, 1), span=1),
    ],
    counts=[1, 1],
    total=2,
  )
  let root : BTreeNode[TItem] = Internal(
    children=[lca_child, right_sibling],
    counts=[2, 2],
    total=4,
  )
  let splice : NodeSplice[TItem] = {
    prefix: [{ children: match root {
      Internal(children~, ..) => children
      _ => abort("expected internal")
    }, counts: match root {
      Internal(counts~, ..) => counts
      _ => abort("expected internal")
    }, child_idx: 0 }],
    children: match lca_child {
      Internal(children~, ..) => children
      _ => abort("expected internal")
    },
    counts: match lca_child {
      Internal(counts~, ..) => counts
      _ => abort("expected internal")
    },
    start_idx: 0,
    end_idx: 1,
    new_children: [],
    original_child_count: 2,
    leaf_delta: -1,
  }
  let result = propagate_node_splice(splice, 2)
  inspect(result.node.total(), content="3")
  // After merge: root has 1 child (will be collapsed by normalize)
  match result.node {
    Internal(children~, ..) => inspect(children.length(), content="1")
    _ => abort("expected internal root")
  }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd lib/btree && moon test 2>&1 | grep -E "FAILED|panic"`
Expected: tests fail because underfull nodes are not repaired

- [ ] **Step 3: Add `is_underfull` helper to `walker_descend.mbt`**

Add after `needs_rebalance` (line ~163) in `lib/btree/walker_descend.mbt`:

```moonbit
///|
/// Check if a node is underfull after a range splice (reactive, < min_degree).
/// Different from needs_rebalance which uses <= min_degree (proactive, for descent).
fn[T] BTreeNode::is_underfull(self : BTreeNode[T], min_degree : Int) -> Bool {
  match self {
    Leaf(..) => false
    Internal(children~, ..) => children.length() < min_degree
  }
}
```

- [ ] **Step 4: Run `moon check`**

Run: `cd lib/btree && moon check 2>&1`
Expected: passes

- [ ] **Step 5: Add underfull repair to `walk_up_ancestors`**

In `lib/btree/walker_propagate.mbt`, replace the `walk_up_ancestors` function (lines 100-129) with:

```moonbit
///|
/// Walk from a node upward through ancestor frames, updating each parent's
/// child pointer and inserting any overflow sibling from a split below.
/// Also repairs underfull nodes (< min_degree children) by borrowing or merging.
/// Splits again if a parent exceeds capacity.
fn[T] walk_up_ancestors(
  path : Array[PathFrame[T]],
  start_from : Int,
  initial_node : BTreeNode[T],
  initial_overflow : BTreeNode[T]?,
  min_degree : Int,
) -> (BTreeNode[T], BTreeNode[T]?) {
  let mut current_node = initial_node
  let mut overflow = initial_overflow
  for i in start_from>=..0 {
    let frame = path[i]
    frame.children[frame.child_idx] = current_node
    frame.counts[frame.child_idx] = current_node.total()
    match overflow {
      Some(sibling) => {
        frame.children.insert(frame.child_idx + 1, sibling)
        frame.counts.insert(frame.child_idx + 1, sibling.total())
      }
      _ => ()
    }
    // Repair underfull child after splice (< min_degree children)
    if current_node.is_underfull(min_degree) &&
      frame.children.length() > 1 {
      ensure_min_after_splice(
        frame.children,
        frame.counts,
        frame.child_idx,
        min_degree,
      )
    }
    let (updated, next_overflow) = maybe_split(
      frame.children,
      frame.counts,
      min_degree,
    )
    current_node = updated
    overflow = next_overflow
  }
  (current_node, overflow)
}
```

- [ ] **Step 6: Add `ensure_min_after_splice` to `walker_propagate.mbt`**

Add before `walk_up_ancestors` in `lib/btree/walker_propagate.mbt`:

```moonbit
///|
/// Repair an underfull node after a range splice. Uses < min_degree threshold
/// (reactive) unlike ensure_min_children which uses <= min_degree (proactive).
fn[T] ensure_min_after_splice(
  children : Array[BTreeNode[T]],
  counts : Array[Int],
  idx : Int,
  min_degree : Int,
) -> Unit {
  if !children[idx].is_underfull(min_degree) {
    return
  }
  if idx > 0 && children[idx - 1].can_lend(min_degree) {
    borrow_from_left(children, counts, idx)
    return
  }
  if idx + 1 < children.length() && children[idx + 1].can_lend(min_degree) {
    borrow_from_right(children, counts, idx)
    return
  }
  if idx > 0 {
    merge_children(children, counts, idx - 1)
  } else if idx + 1 < children.length() {
    merge_children(children, counts, idx)
  }
}
```

- [ ] **Step 7: Run tests**

Run: `cd lib/btree && moon test 2>&1 | tail -5`
Expected: all tests pass including the new underfull repair tests

**⚠️ Compilation break point:** `is_underfull`, `can_lend`, `borrow_from_left`, `borrow_from_right`, `merge_children` are defined in `walker_descend.mbt` — they're package-private so accessible from `walker_propagate.mbt` within the same package.

- [ ] **Step 8: Commit**

```bash
git add lib/btree/walker_propagate.mbt lib/btree/walker_descend.mbt lib/btree/btree_wbtest.mbt
git commit -m "fix(btree): repair underfull nodes during upward propagation after range splice"
```

---

## Task 2: Add post-splice boundary merge normalization

**Files:**
- Modify: `lib/btree/walker_range_delete.mbt` — add `normalize_boundary_merge`
- Test: `lib/btree/btree_wbtest.mbt`

After applying a range splice and propagating, the last leaf before the deleted range and the first leaf after may be mergeable. The current absorb logic misses this at non-leaf LCA levels with partial boundaries. Instead of extending the fragile absorb logic, we add a post-splice pass that re-descends from the new root to check and merge boundary leaves.

- [ ] **Step 1: Write failing test**

Append to `lib/btree/btree_wbtest.mbt`:

```moonbit
// === Post-splice boundary merge ===

///|
test "normalize_boundary_merge merges adjacent leaves across subtrees" {
  // Tree: [[a(3)]] [[b(2)]] [[a(3)]]  (depth=2)
  // Delete range(3, 5) removes all of b(2)
  // After splice: [[a(3)]] [[a(3)]] — the two a's should merge
  let left : BTreeNode[TItem] = Internal(
    children=[Leaf(elem=make_item(1, 3), span=3)],
    counts=[3],
    total=3,
  )
  let middle : BTreeNode[TItem] = Internal(
    children=[Leaf(elem=make_item(2, 2), span=2)],
    counts=[2],
    total=2,
  )
  let right : BTreeNode[TItem] = Internal(
    children=[Leaf(elem=make_item(1, 3), span=3)],
    counts=[3],
    total=3,
  )
  let root : BTreeNode[TItem] = Internal(
    children=[left, middle, right],
    counts=[3, 2, 3],
    total=8,
  )
  let result = normalize_boundary_merge(root, 3, 2)
  inspect(result.total(), content="8")
  // After merge: the two a(3) leaves should become a(6) in some subtree
  let items : Array[TItem] = []
  result.each(fn(item) { items.push(item) })
  inspect(items.length(), content="1")
  inspect(items[0], content="{ id: 1, span: 6 }")
}

///|
test "normalize_boundary_merge is no-op when boundaries not mergeable" {
  let left : BTreeNode[TItem] = Internal(
    children=[Leaf(elem=make_item(1, 3), span=3)],
    counts=[3],
    total=3,
  )
  let right : BTreeNode[TItem] = Internal(
    children=[Leaf(elem=make_item(2, 3), span=3)],
    counts=[3],
    total=3,
  )
  let root : BTreeNode[TItem] = Internal(
    children=[left, right],
    counts=[3, 3],
    total=6,
  )
  let result = normalize_boundary_merge(root, 3, 2)
  inspect(result.total(), content="6")
  let items : Array[TItem] = []
  result.each(fn(item) { items.push(item) })
  inspect(items.length(), content="2")
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd lib/btree && moon test 2>&1 | grep "normalize_boundary_merge"`
Expected: compilation error — function not defined

- [ ] **Step 3: Implement `normalize_boundary_merge`**

Add to the end of `lib/btree/walker_range_delete.mbt`:

```moonbit
///|
/// Post-splice boundary normalization: if the leaves at the splice boundary
/// are mergeable, merge them and propagate the structural change.
/// `boundary_pos` is the position where the deleted range started (after deletion,
/// the left boundary's last leaf ends here and the right boundary's first leaf starts here).
/// Returns the updated root node.
fn[T : BTreeElem] normalize_boundary_merge(
  root : BTreeNode[T],
  boundary_pos : Int,
  min_degree : Int,
) -> BTreeNode[T] {
  // Nothing to merge at boundaries
  if boundary_pos <= 0 || boundary_pos >= root.total() {
    return root
  }
  // Descend to the leaf just before the boundary (end-boundary semantics)
  let left_cursor = descend_leaf_at_end_boundary(root, boundary_pos, min_degree)
  // Descend to the leaf at the boundary (start semantics)
  let right_cursor = descend_leaf_at(root, boundary_pos, min_degree)
  match (left_cursor, right_cursor) {
    (Some(left), Some(right)) => {
      // Check if these are different leaves and mergeable
      if left.path.length() != right.path.length() ||
        shared_prefix_length(left.path, right.path) != left.path.length() {
        // Different leaves — check if they can merge
        if left.offset != left.span || right.offset != 0 {
          // Not at leaf boundaries — can't merge whole leaves
          return root
        }
        if !@rle.Mergeable::can_merge(left.elem, right.elem) {
          return root
        }
        // Merge: delete the right leaf, expand the left leaf to absorb it
        let merged = @rle.Mergeable::merge(left.elem, right.elem)
        let merged_span = @rle.Spanning::span(merged)
        // Use plan_delete_range to remove the right leaf, then replace left
        // with merged. Simpler: use a targeted splice on the LCA.
        let lca = lowest_common_ancestor_range(left, right)
        let merged_leaf = Leaf(elem=merged, span=merged_span)
        let left_suffix = path_suffix_after_target(left.path, lca.prefix.length())
        let right_suffix = path_suffix_after_target(right.path, lca.prefix.length())
        let merged_subtree = merge_boundary_chain(
          left_suffix,
          right_suffix,
          merged_leaf,
        )
        let splice : NodeSplice[T] = {
          prefix: lca.prefix,
          children: lca.children,
          counts: lca.counts,
          start_idx: lca.start_idx,
          end_idx: lca.end_idx,
          new_children: [merged_subtree],
          original_child_count: lca.children.length(),
          leaf_delta: -1,
        }
        let result = propagate_node_splice(splice, min_degree)
        match result.overflow {
          None => result.node
          Some(sibling) => {
            let left_total = result.node.total()
            let right_total = sibling.total()
            Internal(
              children=[result.node, sibling],
              counts=[left_total, right_total],
              total=left_total + right_total,
            )
          }
        }
      } else {
        // Same leaf — no boundary merge needed
        root
      }
    }
    _ => root
  }
}
```

- [ ] **Step 4: Run tests**

Run: `cd lib/btree && moon test 2>&1 | tail -5`
Expected: all tests pass

**⚠️ Compilation break point:** If `merge_boundary_chain` or `path_suffix_after_target` are not found, they should already exist in this file from Phase 2c. If `propagate_node_splice` is not found, it's in `walker_propagate.mbt` (same package).

- [ ] **Step 5: Run `moon test --update` if needed**

If inspect values differ in format (not logic), run:
```bash
cd lib/btree && moon test --update 2>&1
```
Review the diff before committing.

- [ ] **Step 6: Commit**

```bash
git add lib/btree/walker_range_delete.mbt lib/btree/btree_wbtest.mbt
git commit -m "fix(btree): add post-splice boundary merge normalization"
```

---

## Task 3: Add `BTree::delete_range` method

**Files:**
- Modify: `lib/btree/btree.mbt` — add `BTree::delete_range`
- Test: `lib/btree/btree_wbtest.mbt`

Bundle the full pipeline: plan → splice → propagate → normalize root → boundary merge into one method. This is the clean API that replaces order-tree's 40-line manual orchestration.

- [ ] **Step 1: Write failing tests**

Append to `lib/btree/btree_wbtest.mbt`:

```moonbit
// === BTree::delete_range ===

///|
test "BTree::delete_range removes contiguous elements" {
  let t = build_tree([(1, 2), (2, 3), (3, 4)])
  t.delete_range(2, 5)
  inspect(t.span(), content="4")
  inspect(t.size(), content="2")
  let items = t.to_array()
  inspect(items.length(), content="2")
  inspect(items[0], content="{ id: 1, span: 2 }")
  inspect(items[1], content="{ id: 3, span: 4 }")
}

///|
test "BTree::delete_range merges boundary leaves" {
  let t = build_tree([(1, 3), (2, 2), (1, 3)])
  t.delete_range(3, 5)
  inspect(t.span(), content="6")
  // The two id=1 items should merge into one
  let items = t.to_array()
  inspect(items.length(), content="1")
  inspect(items[0], content="{ id: 1, span: 6 }")
}

///|
test "BTree::delete_range empty range is no-op" {
  let t = build_tree([(1, 2), (2, 3)])
  t.delete_range(2, 2)
  inspect(t.span(), content="5")
  inspect(t.size(), content="2")
}

///|
test "BTree::delete_range full range clears tree" {
  let t = build_tree([(1, 2), (2, 3)])
  t.delete_range(0, 5)
  inspect(t.span(), content="0")
  inspect(t.is_empty(), content="true")
}

///|
test "BTree::delete_range clamps end to span" {
  let t = build_tree([(1, 2), (2, 3)])
  t.delete_range(2, 99)
  inspect(t.span(), content="2")
  inspect(t.size(), content="1")
}

///|
test "BTree::delete_range handles underfull propagation" {
  // Build a tree deep enough that range delete causes underfull at LCA
  let items : Array[(Int, Int)] = []
  for i in 0..<20 {
    items.push((i + 1, 1))
  }
  let t = build_tree(items)
  // Delete a large middle range
  t.delete_range(5, 15)
  inspect(t.span(), content="10")
  inspect(t.size(), content="10")
  // Verify tree is well-formed by iterating
  let result = t.to_array()
  inspect(result.length(), content="10")
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd lib/btree && moon test 2>&1 | grep "delete_range"`
Expected: compilation error — `BTree::delete_range` not defined

- [ ] **Step 3: Implement `BTree::delete_range`**

Add to `lib/btree/btree.mbt` after `mutate_for_delete`:

```moonbit
///|
/// Delete all elements in the span range [start, end_).
/// Handles all cases: single-leaf splice, multi-child LCA splice,
/// underfull node repair, and post-splice boundary merging.
pub fn[T : BTreeElem] BTree::delete_range(
  self : BTree[T],
  start : Int,
  end_ : Int,
) -> Unit {
  match self.root {
    None => ()
    Some(root) => {
      let total = root.total()
      if start < 0 || start >= end_ || start >= total {
        return
      }
      let clamped_end = if end_ > total { total } else { end_ }
      match plan_delete_range(root, start, clamped_end, self.min_degree) {
        None => ()
        Some(splice) => {
          let propagated = propagate_node_splice(splice, self.min_degree)
          self.apply_propagated(propagated, normalize_delete=true)
          // Post-splice boundary merge: if the deletion created adjacent
          // mergeable leaves, merge them. Must re-descend from new root
          // since paths are stale after propagation.
          match self.root {
            Some(new_root) => {
              let merged = normalize_boundary_merge(
                new_root,
                start,
                self.min_degree,
              )
              self.root = normalize_root_after_delete(merged)
              // Recount leaves after merge (boundary merge can reduce by 1)
              let mut count = 0
              match self.root {
                Some(r) => r.each(fn(_) { count = count + 1 })
                None => ()
              }
              self.size = count
            }
            None => ()
          }
        }
      }
    }
  }
}
```

- [ ] **Step 4: Run tests**

Run: `cd lib/btree && moon test 2>&1 | tail -5`
Expected: all tests pass

- [ ] **Step 5: Run `moon test --update` if inspect values need adjustment**

```bash
cd lib/btree && moon test --update 2>&1
```
Review diff before committing.

- [ ] **Step 6: Commit**

```bash
git add lib/btree/btree.mbt lib/btree/btree_wbtest.mbt
git commit -m "feat(btree): add BTree::delete_range with complete algorithm"
```

---

## Task 4: Simplify order-tree to use `BTree::delete_range`

**Files:**
- Modify: `order-tree/src/order_tree.mbt` — replace manual orchestration with `self.tree.delete_range(start, end_)`

- [ ] **Step 1: Replace `OrderTree::delete_range` implementation**

In `order-tree/src/order_tree.mbt`, replace the entire `delete_range_needs_merge_rebuild` function (lines 92-109) and the `OrderTree::delete_range` method (lines 111-176) with:

```moonbit
///|
/// Delete all elements in the span range [start, end_).
pub fn[T : @btree.BTreeElem] OrderTree::delete_range(
  self : OrderTree[T],
  start : Int,
  end_ : Int,
) -> Unit {
  self.tree.delete_range(start, end_)
}
```

- [ ] **Step 2: Run `moon check` in order-tree**

Run: `cd order-tree && moon check 2>&1`
Expected: passes

**⚠️ Compilation break point:** If `@btree.BTree::delete_range` is not found, ensure Task 3 was completed and `plan_delete_range` is still pub. The method `delete_range` is on `BTree[T]` which `self.tree` already is.

- [ ] **Step 3: Run order-tree tests**

Run: `cd order-tree && moon test 2>&1 | tail -5`
Expected: all 64 tests pass — the 8 existing `delete_range` blackbox tests now exercise the new algorithm

- [ ] **Step 4: Run full test suite**

Run: `moon test 2>&1 | tail -5`
Expected: all tests pass

- [ ] **Step 5: Commit**

```bash
cd order-tree
git add src/order_tree.mbt
git commit -m "refactor(order-tree): simplify delete_range to delegate to BTree::delete_range"
cd ..
git add order-tree
git commit -m "chore: update order-tree submodule (simplified delete_range)"
```

---

## Task 5: Replace eager `BTree::iter` with lazy cursor-based traversal

**Files:**
- Modify: `lib/btree/iter.mbt` — rewrite `BTree::iter`
- Test: `lib/btree/btree_wbtest.mbt`

The current `iter` calls `to_array()` which materializes the entire tree. Replace with a lazy traversal using `descend_leftmost` + `cursor_next_leaf`.

- [ ] **Step 1: Write test for lazy iter behavior**

Append to `lib/btree/btree_wbtest.mbt`:

```moonbit
// === Lazy BTree::iter ===

///|
test "BTree::iter yields elements in order lazily" {
  let t = build_tree([(1, 3), (2, 2), (3, 4)])
  let items : Array[TItem] = []
  for item in t.iter() {
    items.push(item)
  }
  inspect(items.length(), content="3")
  inspect(items[0], content="{ id: 1, span: 3 }")
  inspect(items[1], content="{ id: 2, span: 2 }")
  inspect(items[2], content="{ id: 3, span: 4 }")
}

///|
test "BTree::iter on empty tree yields nothing" {
  let t : BTree[TItem] = BTree::new(min_degree=2)
  let items : Array[TItem] = []
  for item in t.iter() {
    items.push(item)
  }
  inspect(items.length(), content="0")
}

///|
test "BTree::iter supports early termination" {
  let t = build_tree([(1, 1), (2, 1), (3, 1), (4, 1), (5, 1)])
  let items : Array[TItem] = []
  for item in t.iter() {
    items.push(item)
    if items.length() == 2 {
      break
    }
  }
  inspect(items.length(), content="2")
  inspect(items[0], content="{ id: 1, span: 1 }")
  inspect(items[1], content="{ id: 2, span: 1 }")
}
```

- [ ] **Step 2: Run tests (they should pass with current eager impl)**

Run: `cd lib/btree && moon test 2>&1 | tail -5`
Expected: tests pass (existing eager impl satisfies the contract)

- [ ] **Step 3: Replace `BTree::iter` with lazy implementation**

Replace the `BTree::iter` function in `lib/btree/iter.mbt` (lines 27-39) with:

```moonbit
///|
pub fn[T] BTree::iter(self : BTree[T]) -> Iter[T] {
  match self.root {
    None => Iter::empty()
    Some(root) => {
      let mut cursor : Cursor[T]? = Some(descend_leftmost(root, []))
      Iter::new(fn() {
        match cursor {
          None => None
          Some(cur) => {
            let elem = cur.leaf_elem
            cursor = cursor_next_leaf(cur)
            Some(elem)
          }
        }
      })
    }
  }
}
```

- [ ] **Step 4: Run tests**

Run: `cd lib/btree && moon test 2>&1 | tail -5`
Expected: all tests pass with the lazy implementation

- [ ] **Step 5: Run full test suite**

Run: `moon test 2>&1 | tail -5`
Expected: all tests pass (order-tree uses `iter` via `OrderTree::iter`)

- [ ] **Step 6: Commit**

```bash
git add lib/btree/iter.mbt lib/btree/btree_wbtest.mbt
git commit -m "perf(btree): replace eager to_array iter with lazy cursor-based traversal"
```

---

## Task 6: Narrow public API

**Files:**
- Modify: `lib/btree/walker_descend.mbt` — remove `pub` from internal functions
- Modify: `lib/btree/walker_propagate.mbt` — remove `pub` from internal functions
- Modify: `lib/btree/btree.mbt` — remove `pub` from `normalize_root_after_delete`
- Modify: `lib/btree/walker_types.mbt` — change `pub(all)` to `priv` for internal types

After `BTree::delete_range` absorbs the manual orchestration, order-tree no longer needs direct access to walker internals. The following symbols become private:

**Functions (remove `pub`):**
- `descend` — internal walker
- `copy_path` — internal helper
- `cursor_next_leaf` — internal iterator helper
- `descend_leaf_at` — internal range helper
- `descend_leaf_at_end_boundary` — internal range helper
- `descend_leftmost` — internal walker
- `descend_rightmost` — internal walker
- `prepare_ensure_min` — internal delete hook
- `prepare_split` — internal insert hook
- `propagate` — internal propagation
- `propagate_node_splice` — internal propagation
- `plan_delete_range` — internal range planning
- `normalize_root_after_delete` — internal root normalization

**Types (change `pub(all)` to `priv`):**
- `Cursor[T]` — internal navigation
- `PathFrame[T]` — internal navigation
- `LeafCursor[T]` — internal range helper
- `NodeSplice[T]` — internal range planning
- `PropagateResult[T]` — internal propagation

**Types that stay `pub(all)`:**
- `BTree[T]` — main type
- `BTreeNode[T]` — needed by order-tree's `from_array` (constructs nodes directly)
- `LeafContext[T]` — mutation callback parameter
- `Splice[T]` — mutation callback return
- `FindResult[T]` — query result

- [ ] **Step 1: Verify no external usage of symbols being made private**

Run:
```bash
grep -rn "@btree\.descend\b\|@btree\.copy_path\|@btree\.cursor_next_leaf\|@btree\.descend_leaf_at\|@btree\.descend_leftmost\|@btree\.descend_rightmost\|@btree\.prepare_ensure_min\|@btree\.prepare_split\|@btree\.propagate\b\|@btree\.propagate_node_splice\|@btree\.plan_delete_range\|@btree\.normalize_root_after_delete" order-tree/src/*.mbt event-graph-walker/
```

Expected: no matches (Task 4 removed all external usage). If any matches remain, fix them before proceeding.

- [ ] **Step 2: Remove `pub` from functions in `walker_descend.mbt`**

In `lib/btree/walker_descend.mbt`, change these function signatures:

```
pub fn[T] prepare_ensure_min(  →  fn[T] prepare_ensure_min(
pub fn[T] prepare_split(       →  fn[T] prepare_split(
pub fn[T] descend_leaf_at(     →  fn[T] descend_leaf_at(
pub fn[T] descend_leaf_at_end_boundary(  →  fn[T] descend_leaf_at_end_boundary(
pub fn[T] descend_leftmost(    →  fn[T] descend_leftmost(
pub fn[T] descend_rightmost(   →  fn[T] descend_rightmost(
pub fn[T] cursor_next_leaf(    →  fn[T] cursor_next_leaf(
pub fn[T] copy_path(           →  fn[T] copy_path(
pub fn[T] descend(             →  fn[T] descend(
```

- [ ] **Step 3: Remove `pub` from functions in `walker_propagate.mbt`**

```
pub fn[T] propagate(             →  fn[T] propagate(
pub fn[T] propagate_node_splice( →  fn[T] propagate_node_splice(
```

- [ ] **Step 4: Remove `pub` from `plan_delete_range` in `walker_range_delete.mbt`**

```
pub fn[T : BTreeElem] plan_delete_range(  →  fn[T : BTreeElem] plan_delete_range(
```

- [ ] **Step 5: Remove `pub` from `normalize_root_after_delete` in `btree.mbt`**

```
pub fn[T] normalize_root_after_delete(  →  fn[T] normalize_root_after_delete(
```

- [ ] **Step 6: Change internal types to `priv` in `walker_types.mbt`**

In `lib/btree/walker_types.mbt`, change:

```
pub(all) struct Cursor[T]       →  priv struct Cursor[T]
pub(all) struct PathFrame[T]    →  priv struct PathFrame[T]
pub(all) struct LeafCursor[T]   →  priv struct LeafCursor[T]
pub(all) struct NodeSplice[T]   →  priv struct NodeSplice[T]
pub(all) struct PropagateResult[T]  →  priv struct PropagateResult[T]
```

- [ ] **Step 7: Run `moon check`**

Run: `cd lib/btree && moon check 2>&1`
Expected: passes

**⚠️ Compilation break point:** If `moon check` fails with "cannot access private type from pub function", a pub function still references a now-private type. The most likely cause is a pub function we missed. Check the error and remove `pub` from that function too.

- [ ] **Step 8: Run full test suite**

Run: `moon test 2>&1 | tail -5`
Expected: all tests pass

- [ ] **Step 9: Commit**

```bash
git add lib/btree/walker_descend.mbt lib/btree/walker_propagate.mbt lib/btree/walker_range_delete.mbt lib/btree/btree.mbt lib/btree/walker_types.mbt
git commit -m "refactor(btree): narrow public API — hide walker internals"
```

---

## Task 7: Cleanup and verify

**Files:**
- Run: `moon info && moon fmt` (from lib/btree)
- Verify: `git diff *.mbti`
- Modify: `docs/TODO.md` — mark Phase 2d done
- Run: full test suite

- [ ] **Step 1: Run formatting and interface generation**

```bash
cd lib/btree && moon info && moon fmt
```

- [ ] **Step 2: Verify API changes**

```bash
git diff *.mbti
```

Expected: 13 pub functions removed, 5 pub(all) types removed, `BTree::delete_range` added. No unintended trait bound widening.

- [ ] **Step 3: Run full test suite**

```bash
moon test
cd order-tree && moon test
cd ../event-graph-walker && moon test
```

Expected: all tests pass everywhere.

- [ ] **Step 4: Update `docs/TODO.md`**

Mark Phase 2d as done. Update the Generic Tree Libraries section.

- [ ] **Step 5: Final commit**

```bash
git add -A
git commit -m "chore: Phase 2d cleanup — moon info, fmt, TODO update"
```

---

## Validation

```bash
cd lib/btree && moon test           # lib/btree tests
cd order-tree && moon test          # order-tree tests (delete_range now uses BTree::delete_range)
cd event-graph-walker && moon test  # CRDT integration
moon test                           # Full module
moon check && moon fmt && moon info # Lint
```

## Summary

| Metric | Before | After |
|--------|--------|-------|
| `order-tree/delete_range` | 40 lines manual orchestration + 18 lines fallback check | 3-line delegation |
| `delete_range_needs_merge_rebuild` | exists (O(n) fallback) | deleted |
| lib/btree pub functions | 15 | 2 fewer (plan_delete_range, normalize_root_after_delete private) + `delete_range` added |
| lib/btree pub(all) types | 9 | 4 (Cursor, PathFrame, LeafCursor, NodeSplice, PropagateResult → priv) |
| `BTree::iter` | eager (materializes array) | lazy (cursor-based) |
| `BTree::delete_range` | — | new pub method |
| Underfull node repair | not handled (fallback to rebuild) | handled in propagation |
| Boundary merge at non-leaf LCA | not handled (fallback to rebuild) | handled by post-splice pass |
