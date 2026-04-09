# Phase 2c: Range Delete Extraction to lib/btree

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move `walker_range_delete.mbt` from order-tree to lib/btree, add `descend_rightmost`, and fill whitebox test debt from Phase 2b.

**Architecture:** The 584-line `walker_range_delete.mbt` in order-tree contains generic B-tree range-delete machinery that belongs in lib/btree. 20 functions move; 3 duplicates (`AncestorRange`, `shared_prefix_length`, `lowest_common_ancestor_range`) already exist in lib/btree and are simply deleted from order-tree. Only `delete_range_needs_merge_rebuild` (already in `order_tree.mbt`) stays in order-tree. `descend_rightmost` is added alongside `descend_leftmost` in lib/btree. 15 whitebox tests move from order-tree to lib/btree, plus 4 new test-debt tests are added.

**Tech Stack:** MoonBit, dowdiness/btree, dowdiness/rle

---

## File Structure

### Created
- `lib/btree/walker_range_delete.mbt` — all range-delete functions (20 functions, ~530 lines)

### Modified
- `lib/btree/walker_descend.mbt` — add `descend_rightmost` (~24 lines)
- `lib/btree/btree_wbtest.mbt` — add 15 migrated tests + 4 test-debt tests
- `order-tree/src/order_tree.mbt` — change `plan_delete_range(...)` → `@btree.plan_delete_range(...)`
- `order-tree/src/walker_wbtest.mbt` — remove 15 range-delete tests (keep 1 order-tree test)

### Deleted
- `order-tree/src/walker_range_delete.mbt` — entire file (replaced by lib/btree version)

### Unchanged (verified)
- `order-tree/src/utils.mbt` — `must_slice` still used by `walker_insert.mbt`/`walker_delete.mbt`; `Array::sum` still used by `bulk_build.mbt`

---

## Task 1: Add `descend_rightmost` to lib/btree

**Files:**
- Modify: `lib/btree/walker_descend.mbt` (after `descend_leftmost` at ~line 325)
- Modify: `lib/btree/btree_wbtest.mbt` (add test)

- [ ] **Step 1: Write the failing test**

Add to the end of `lib/btree/btree_wbtest.mbt`:

```moonbit
///|
test "descend_rightmost returns rightmost leaf with end offset" {
  let t = build_tree([(1, 3), (2, 2), (3, 4)])
  let root = t.root.unwrap()
  let cursor = descend_rightmost(root, [])
  // Should be at the rightmost leaf (id=3, span=4) with offset=span
  inspect(cursor.leaf_elem, content="{ id: 3, span: 4 }")
  inspect(cursor.offset, content="4")
  inspect(cursor.leaf_span, content="4")
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd lib/btree && moon test 2>&1 | grep "descend_rightmost"`
Expected: compilation error — `descend_rightmost` not defined

- [ ] **Step 3: Implement `descend_rightmost`**

Add to `lib/btree/walker_descend.mbt` after the `descend_leftmost` function (around line 325):

```moonbit
///|
/// Descend to the rightmost leaf, recording frames in the path.
/// The returned cursor has offset == span (positioned at end of last leaf).
pub fn[T] descend_rightmost(
  node : BTreeNode[T],
  prefix : Array[PathFrame[T]],
) -> Cursor[T] {
  let path = copy_path(prefix, prefix.length())
  fn step(current : BTreeNode[T]) -> Cursor[T] {
    match current {
      Leaf(elem~, span~) => {
        let child_idx = if path.length() == 0 {
          0
        } else {
          path[path.length() - 1].child_idx
        }
        { path, leaf_elem: elem, leaf_span: span, offset: span, child_idx }
      }
      Internal(children~, counts~, ..) => {
        let child_idx = children.length() - 1
        path.push({ children, counts, child_idx })
        step(children[child_idx])
      }
    }
  }
  step(node)
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd lib/btree && moon test 2>&1 | tail -5`
Expected: all tests pass

- [ ] **Step 5: Commit**

```bash
git add lib/btree/walker_descend.mbt lib/btree/btree_wbtest.mbt
git commit -m "feat(btree): add descend_rightmost alongside descend_leftmost"
```

---

## Task 2: Create `walker_range_delete.mbt` in lib/btree

**Files:**
- Create: `lib/btree/walker_range_delete.mbt`

**Transformation rules from order-tree → lib/btree:**
1. Remove `using @btree {type BTreeNode}` import
2. Remove `@btree.` prefix from all types (`PathFrame`, `LeafCursor`, `Cursor`, `NodeSplice`, `BTreeNode`)
3. Replace `BTreeNode::Internal(...)` / `BTreeNode::Leaf(...)` with `Internal(...)` / `Leaf(...)`
4. Replace `@btree.copy_path(...)` with `copy_path(...)`
5. Replace `@btree.descend_leaf_at(...)` with `descend_leaf_at(...)`
6. Replace `@btree.descend_leaf_at_end_boundary(...)` with `descend_leaf_at_end_boundary(...)`
7. Replace `@btree.descend_leftmost(...)` with `descend_leftmost(...)`
8. Delete the 3 duplicates: `AncestorRange[T]`, `shared_prefix_length`, `lowest_common_ancestor_range` — they already exist in lib/btree
9. Use local `descend_rightmost` (added in Task 1) instead of the local copy
10. Make `plan_delete_range` pub (order-tree calls it)
11. Replace `@btree.BTreeElem` with `BTreeElem` in trait bounds

- [ ] **Step 1: Create the file**

Create `lib/btree/walker_range_delete.mbt` with the following content:

```moonbit
///|
fn[T] path_suffix_after_target(
  path : Array[PathFrame[T]],
  target_depth : Int,
) -> Array[PathFrame[T]] {
  let suffix : Array[PathFrame[T]] = []
  for i in (target_depth + 1)..<path.length() {
    suffix.push(path[i])
  }
  suffix
}

///|
fn[T] rebuild_boundary_chain(
  path_suffix : Array[PathFrame[T]],
  leaf : BTreeNode[T],
  keep_left : Bool,
) -> BTreeNode[T] {
  let mut current = leaf
  for i in (path_suffix.length() - 1)>=..0 {
    let frame = path_suffix[i]
    let children : Array[BTreeNode[T]] = []
    let counts : Array[Int] = []
    if keep_left {
      for j in 0..<frame.child_idx {
        children.push(frame.children[j])
        counts.push(frame.counts[j])
      }
      children.push(current)
      counts.push(current.total())
    } else {
      children.push(current)
      counts.push(current.total())
      for j in (frame.child_idx + 1)..<frame.children.length() {
        children.push(frame.children[j])
        counts.push(frame.counts[j])
      }
    }
    current = Internal(children~, counts~, total=counts.sum())
  }
  current
}

///|
fn[T : BTreeElem] left_boundary_keep(start : LeafCursor[T]) -> T? {
  if start.offset == 0 {
    return None
  }
  Some(must_slice(start.elem, start=0, end=start.offset))
}

///|
fn[T : BTreeElem] right_boundary_keep(end_ : LeafCursor[T]) -> T? {
  if end_.offset == end_.span {
    return None
  }
  Some(must_slice(end_.elem, start=end_.offset, end=end_.span))
}

///|
fn[T] merge_boundary_chain(
  left_path_suffix : Array[PathFrame[T]],
  right_path_suffix : Array[PathFrame[T]],
  leaf : BTreeNode[T],
) -> BTreeNode[T] {
  if left_path_suffix.length() != right_path_suffix.length() {
    abort("merge_boundary_chain: mismatched suffix heights")
  }
  let mut current = leaf
  for i in (left_path_suffix.length() - 1)>=..0 {
    let left_frame = left_path_suffix[i]
    let right_frame = right_path_suffix[i]
    let children : Array[BTreeNode[T]] = []
    let counts : Array[Int] = []
    for j in 0..<left_frame.child_idx {
      children.push(left_frame.children[j])
      counts.push(left_frame.counts[j])
    }
    children.push(current)
    counts.push(current.total())
    for j in (right_frame.child_idx + 1)..<right_frame.children.length() {
      children.push(right_frame.children[j])
      counts.push(right_frame.counts[j])
    }
    current = Internal(children~, counts~, total=counts.sum())
  }
  current
}

///|
fn[T] leftmost_leaf_in_subtree(node : BTreeNode[T]) -> LeafCursor[T] {
  LeafCursor::from_cursor(descend_leftmost(node, []))
}

///|
fn[T] rightmost_leaf_in_subtree(node : BTreeNode[T]) -> LeafCursor[T] {
  LeafCursor::from_cursor(descend_rightmost(node, []))
}

///|
fn[T : BTreeElem] left_boundary_subtree(
  lca : AncestorRange[T],
  start : LeafCursor[T],
) -> BTreeNode[T]? {
  match left_boundary_keep(start) {
    None => None
    Some(kept) => {
      let kept_leaf = Leaf(elem=kept, span=@rle.Spanning::span(kept))
      let target_depth = lca.prefix.length()
      let suffix = path_suffix_after_target(start.path, target_depth)
      Some(rebuild_boundary_chain(suffix, kept_leaf, true))
    }
  }
}

///|
fn[T : BTreeElem] right_boundary_subtree(
  lca : AncestorRange[T],
  end_ : LeafCursor[T],
) -> BTreeNode[T]? {
  match right_boundary_keep(end_) {
    None => None
    Some(kept) => {
      let kept_leaf = Leaf(elem=kept, span=@rle.Spanning::span(kept))
      let target_depth = lca.prefix.length()
      let suffix = path_suffix_after_target(end_.path, target_depth)
      Some(rebuild_boundary_chain(suffix, kept_leaf, false))
    }
  }
}

///|
fn[T : BTreeElem] merged_boundary_subtree(
  lca : AncestorRange[T],
  start : LeafCursor[T],
  end_ : LeafCursor[T],
) -> BTreeNode[T]? {
  match (left_boundary_keep(start), right_boundary_keep(end_)) {
    (Some(left), Some(right)) => {
      if !@rle.Mergeable::can_merge(left, right) {
        return None
      }
      let merged = @rle.Mergeable::merge(left, right)
      let merged_leaf = Leaf(
        elem=merged,
        span=@rle.Spanning::span(merged),
      )
      let target_depth = lca.prefix.length()
      let left_suffix = path_suffix_after_target(start.path, target_depth)
      let right_suffix = path_suffix_after_target(end_.path, target_depth)
      Some(merge_boundary_chain(left_suffix, right_suffix, merged_leaf))
    }
    _ => None
  }
}

///|
fn[T] BTreeNode::leaf_count(self : BTreeNode[T]) -> Int {
  match self {
    Leaf(..) => 1
    Internal(children~, ..) => {
      let mut total = 0
      for child in children {
        total = total + child.leaf_count()
      }
      total
    }
  }
}

///|
fn[T : BTreeElem] compute_single_leaf_delete_range(
  leaf : LeafCursor[T],
  start_offset : Int,
  end_offset : Int,
) -> Array[(T, Int)] {
  let new_leaves : Array[(T, Int)] = []
  let left_keep : T? = if start_offset == 0 {
    None
  } else {
    Some(must_slice(leaf.elem, start=0, end=start_offset))
  }
  let right_keep : T? = if end_offset == leaf.span {
    None
  } else {
    Some(must_slice(leaf.elem, start=end_offset, end=leaf.span))
  }
  match (left_keep, right_keep) {
    (None, None) => ()
    (Some(left), None) => new_leaves.push((left, @rle.Spanning::span(left)))
    (None, Some(right)) => new_leaves.push((right, @rle.Spanning::span(right)))
    (Some(left), Some(right)) =>
      if @rle.Mergeable::can_merge(left, right) {
        let merged = @rle.Mergeable::merge(left, right)
        new_leaves.push((merged, @rle.Spanning::span(merged)))
      } else {
        new_leaves.push((left, @rle.Spanning::span(left)))
        new_leaves.push((right, @rle.Spanning::span(right)))
      }
  }
  new_leaves
}

///|
fn[T] leaf_count_of_children(
  children : Array[BTreeNode[T]],
  start_idx : Int,
  end_idx : Int,
) -> Int {
  let mut total = 0
  for i in start_idx..<end_idx {
    total = total + children[i].leaf_count()
  }
  total
}

///|
fn[T] leaf_count_of_array(children : Array[BTreeNode[T]]) -> Int {
  leaf_count_of_children(children, 0, children.length())
}

///|
fn[T : BTreeElem] merge_leaf_nodes(
  left : BTreeNode[T],
  right : BTreeNode[T],
) -> BTreeNode[T]? {
  match (left, right) {
    (Leaf(elem=left_elem, ..), Leaf(elem=right_elem, ..)) =>
      if @rle.Mergeable::can_merge(left_elem, right_elem) {
        let merged = @rle.Mergeable::merge(left_elem, right_elem)
        Some(Leaf(elem=merged, span=@rle.Spanning::span(merged)))
      } else {
        None
      }
    _ => None
  }
}

///|
fn[T : BTreeElem] absorb_leaf_level_gap_merge(
  lca : AncestorRange[T],
  start : LeafCursor[T],
  end_ : LeafCursor[T],
  new_children : Array[BTreeNode[T]],
  start_idx : Int,
  end_idx : Int,
) -> (Array[BTreeNode[T]], Int, Int, Bool) {
  if lca.child_height != 0 {
    return (new_children, start_idx, end_idx, false)
  }
  let mut merged_children = new_children
  let mut merged_start_idx = start_idx
  let mut merged_end_idx = end_idx
  let mut absorbed = false
  if start.offset == 0 &&
    end_.offset == end_.span &&
    start_idx > 0 &&
    end_idx < lca.children.length() &&
    merged_children.length() == 0 {
    match merge_leaf_nodes(lca.children[start_idx - 1], lca.children[end_idx]) {
      Some(merged) => {
        merged_children.push(merged)
        merged_start_idx = start_idx - 1
        merged_end_idx = end_idx + 1
        absorbed = true
      }
      None => ()
    }
  }
  if start.offset == 0 && merged_children.length() > 0 && merged_start_idx > 0 {
    match
      merge_leaf_nodes(lca.children[merged_start_idx - 1], merged_children[0]) {
      Some(merged) => {
        merged_children[0] = merged
        merged_start_idx = merged_start_idx - 1
        absorbed = true
      }
      None => ()
    }
  }
  if end_.offset == end_.span &&
    merged_children.length() > 0 &&
    merged_end_idx < lca.children.length() {
    let last_idx = merged_children.length() - 1
    match
      merge_leaf_nodes(merged_children[last_idx], lca.children[merged_end_idx]) {
      Some(merged) => {
        merged_children[last_idx] = merged
        merged_end_idx = merged_end_idx + 1
        absorbed = true
      }
      None => ()
    }
  }
  (merged_children, merged_start_idx, merged_end_idx, absorbed)
}

///|
fn[T : BTreeElem] absorb_subtree_gap_merge(
  lca : AncestorRange[T],
  start : LeafCursor[T],
  end_ : LeafCursor[T],
  new_children : Array[BTreeNode[T]],
  start_idx : Int,
  end_idx : Int,
) -> (Array[BTreeNode[T]], Int, Int, Bool) {
  if !(start.offset == 0 &&
    end_.offset == end_.span &&
    new_children.length() == 0 &&
    start_idx > 0 &&
    end_idx < lca.children.length()) {
    return (new_children, start_idx, end_idx, false)
  }
  let left_edge = rightmost_leaf_in_subtree(lca.children[start_idx - 1])
  let right_edge = leftmost_leaf_in_subtree(lca.children[end_idx])
  if !@rle.Mergeable::can_merge(left_edge.elem, right_edge.elem) {
    return (new_children, start_idx, end_idx, false)
  }
  let merged = @rle.Mergeable::merge(left_edge.elem, right_edge.elem)
  let merged_leaf = Leaf(
    elem=merged,
    span=@rle.Spanning::span(merged),
  )
  let merged_subtree = merge_boundary_chain(
    left_edge.path,
    right_edge.path,
    merged_leaf,
  )
  ([merged_subtree], start_idx - 1, end_idx + 1, true)
}

///|
fn[T : BTreeElem] promote_empty_child_gap_merge(
  lca : AncestorRange[T],
) -> NodeSplice[T]? {
  if lca.prefix.length() == 0 ||
    lca.start_idx != 0 ||
    lca.end_idx != lca.children.length() {
    return None
  }
  let parent = lca.prefix[lca.prefix.length() - 1]
  let child_idx = parent.child_idx
  if child_idx == 0 || child_idx + 1 >= parent.children.length() {
    return None
  }
  let left_edge = rightmost_leaf_in_subtree(parent.children[child_idx - 1])
  let right_edge = leftmost_leaf_in_subtree(parent.children[child_idx + 1])
  if !@rle.Mergeable::can_merge(left_edge.elem, right_edge.elem) {
    return None
  }
  let merged = @rle.Mergeable::merge(left_edge.elem, right_edge.elem)
  let merged_leaf = Leaf(
    elem=merged,
    span=@rle.Spanning::span(merged),
  )
  let merged_subtree = merge_boundary_chain(
    left_edge.path,
    right_edge.path,
    merged_leaf,
  )
  let new_children : Array[BTreeNode[T]] = [merged_subtree]
  let removed_leaf_count = leaf_count_of_children(
    parent.children,
    child_idx - 1,
    child_idx + 2,
  )
  Some({
    prefix: copy_path(lca.prefix, lca.prefix.length() - 1),
    children: parent.children,
    counts: parent.counts,
    start_idx: child_idx - 1,
    end_idx: child_idx + 2,
    new_children,
    original_child_count: parent.children.length(),
    leaf_delta: leaf_count_of_array(new_children) - removed_leaf_count,
  })
}

///|
/// Plan a range delete over [start, end_) on a B-tree.
/// Returns a NodeSplice describing the structural changes, or None if
/// the range is invalid or empty. The caller is responsible for
/// propagating the splice and handling root lifecycle.
pub fn[T : BTreeElem] plan_delete_range(
  root : BTreeNode[T],
  start : Int,
  end_ : Int,
  min_degree : Int,
) -> NodeSplice[T]? {
  let total = root.total()
  if start < 0 || start >= end_ || start >= total {
    return None
  }
  let clamped_end = if end_ > total { total } else { end_ }
  let start_cursor = descend_leaf_at(root, start, min_degree)
  let end_cursor = descend_leaf_at_end_boundary(
    root, clamped_end, min_degree,
  )
  match (start_cursor, end_cursor) {
    (Some(start_leaf), Some(end_leaf)) => {
      let lca = lowest_common_ancestor_range(start_leaf, end_leaf)
      if start_leaf.path.length() == end_leaf.path.length() &&
        shared_prefix_length(start_leaf.path, end_leaf.path) ==
        start_leaf.path.length() {
        let replacement = compute_single_leaf_delete_range(
          start_leaf,
          start_leaf.offset,
          end_leaf.offset,
        )
        let new_children : Array[BTreeNode[T]] = []
        for pair in replacement {
          let (elem, span) = pair
          new_children.push(Leaf(elem~, span~))
        }
        let (normalized_children, normalized_start_idx, normalized_end_idx, _) = absorb_subtree_gap_merge(
          lca,
          start_leaf,
          end_leaf,
          new_children,
          lca.start_idx,
          lca.end_idx,
        )
        let (normalized_children, normalized_start_idx, normalized_end_idx, _) = absorb_leaf_level_gap_merge(
          lca, start_leaf, end_leaf, normalized_children, normalized_start_idx, normalized_end_idx,
        )
        let removed_leaf_count = leaf_count_of_children(
          lca.children,
          normalized_start_idx,
          normalized_end_idx,
        )
        if normalized_children.length() == 0 {
          match promote_empty_child_gap_merge(lca) {
            Some(promoted) => return Some(promoted)
            None => ()
          }
        }
        return Some({
          prefix: lca.prefix,
          children: lca.children,
          counts: lca.counts,
          start_idx: normalized_start_idx,
          end_idx: normalized_end_idx,
          new_children: normalized_children,
          original_child_count: lca.children.length(),
          leaf_delta: leaf_count_of_array(normalized_children) -
          removed_leaf_count,
        })
      }
      let new_children : Array[BTreeNode[T]] = []
      match merged_boundary_subtree(lca, start_leaf, end_leaf) {
        Some(merged) => new_children.push(merged)
        None => {
          match left_boundary_subtree(lca, start_leaf) {
            Some(left) => new_children.push(left)
            None => ()
          }
          match right_boundary_subtree(lca, end_leaf) {
            Some(right) => new_children.push(right)
            None => ()
          }
        }
      }
      let (normalized_children, normalized_start_idx, normalized_end_idx, _) = absorb_subtree_gap_merge(
        lca,
        start_leaf,
        end_leaf,
        new_children,
        lca.start_idx,
        lca.end_idx,
      )
      let (normalized_children, normalized_start_idx, normalized_end_idx, _) = absorb_leaf_level_gap_merge(
        lca, start_leaf, end_leaf, normalized_children, normalized_start_idx, normalized_end_idx,
      )
      let removed_leaf_count = leaf_count_of_children(
        lca.children,
        normalized_start_idx,
        normalized_end_idx,
      )
      Some({
        prefix: lca.prefix,
        children: lca.children,
        counts: lca.counts,
        start_idx: normalized_start_idx,
        end_idx: normalized_end_idx,
        new_children: normalized_children,
        original_child_count: lca.children.length(),
        leaf_delta: leaf_count_of_array(normalized_children) -
        removed_leaf_count,
      })
    }
    _ => None
  }
}
```

- [ ] **Step 2: Run `moon check` in lib/btree**

Run: `cd lib/btree && moon check 2>&1`
Expected: passes (the new functions compile against existing lib/btree types)

**⚠️ Compilation break point:** If `Array::sum` is not found, lib/btree's `utils.mbt` already defines it. If `must_slice` is not found, it's already in `utils.mbt`. Both should resolve. If `AncestorRange` causes a duplicate symbol error, verify you did NOT copy the `AncestorRange` struct definition (it already exists in `walker_types.mbt`).

- [ ] **Step 3: Commit**

```bash
git add lib/btree/walker_range_delete.mbt
git commit -m "feat(btree): add range delete functions (moved from order-tree)"
```

---

## Task 3: Move range delete tests from order-tree to lib/btree

**Files:**
- Modify: `lib/btree/btree_wbtest.mbt` (add 15 tests)

**Adaptation rules from order-tree tests → lib/btree tests:**
1. Replace `Run` test type with existing `TItem` (both use identity-based merging)
2. Map: `run("a", N)` → `make_item(1, N)`, `run("b", N)` → `make_item(2, N)`, `run("c", N)` → `make_item(3, N)`, `run("d", N)` → `make_item(4, N)`, `run("x", N)` → `make_item(5, N)`, `run("y", N)` → `make_item(6, N)`
3. Replace `BTreeNode[Run]` → `BTreeNode[TItem]`
4. Remove `@btree.` prefix from all function calls (`descend_leaf_at`, `descend_leaf_at_end_boundary`, `LeafCursor::from_cursor`, `copy_path`)
5. All `inspect` content values are structural (lengths, totals, indices) — unchanged by type swap

- [ ] **Step 1: Add the 15 migrated tests**

Append to `lib/btree/btree_wbtest.mbt`:

```moonbit
// === Range delete tests (migrated from order-tree) ===

///|
test "shared_prefix_length handles same leaf and divergence" {
  let root : BTreeNode[TItem] = Internal(
    children=[Leaf(elem=make_item(1, 1), span=1), Leaf(elem=make_item(2, 1), span=1)],
    counts=[1, 1],
    total=2,
  )
  let left = descend_leaf_at(root, 0, 2).unwrap()
  let right = descend_leaf_at(root, 1, 2).unwrap()
  inspect(shared_prefix_length(left.path, left.path), content="1")
  inspect(shared_prefix_length(left.path, right.path), content="0")
}

///|
test "lowest_common_ancestor_range handles same leaf" {
  let root : BTreeNode[TItem] = Internal(
    children=[Leaf(elem=make_item(1, 3), span=3), Leaf(elem=make_item(2, 2), span=2)],
    counts=[3, 2],
    total=5,
  )
  let start = descend_leaf_at(root, 1, 2).unwrap()
  let end_ = descend_leaf_at_end_boundary(root, 2, 2).unwrap()
  let range = lowest_common_ancestor_range(start, end_)
  inspect(range.prefix.length(), content="0")
  inspect(range.start_idx, content="0")
  inspect(range.end_idx, content="1")
  inspect(range.child_height, content="0")
}

///|
test "lowest_common_ancestor_range handles same parent different children" {
  let root : BTreeNode[TItem] = Internal(
    children=[
      Leaf(elem=make_item(1, 2), span=2),
      Leaf(elem=make_item(2, 2), span=2),
      Leaf(elem=make_item(3, 2), span=2),
    ],
    counts=[2, 2, 2],
    total=6,
  )
  let start = descend_leaf_at(root, 1, 2).unwrap()
  let end_ = descend_leaf_at_end_boundary(root, 5, 2).unwrap()
  let range = lowest_common_ancestor_range(start, end_)
  inspect(range.prefix.length(), content="0")
  inspect(range.start_idx, content="0")
  inspect(range.end_idx, content="3")
  inspect(range.child_height, content="0")
}

///|
test "lowest_common_ancestor_range handles higher level divergence" {
  let left_child : BTreeNode[TItem] = Internal(
    children=[Leaf(elem=make_item(1, 1), span=1), Leaf(elem=make_item(2, 1), span=1)],
    counts=[1, 1],
    total=2,
  )
  let right_child : BTreeNode[TItem] = Internal(
    children=[Leaf(elem=make_item(3, 1), span=1), Leaf(elem=make_item(4, 1), span=1)],
    counts=[1, 1],
    total=2,
  )
  let root : BTreeNode[TItem] = Internal(
    children=[left_child, right_child],
    counts=[2, 2],
    total=4,
  )
  let start = descend_leaf_at(root, 1, 2).unwrap()
  let end_ = descend_leaf_at_end_boundary(root, 3, 2).unwrap()
  let range = lowest_common_ancestor_range(start, end_)
  inspect(range.prefix.length(), content="0")
  inspect(range.start_idx, content="0")
  inspect(range.end_idx, content="2")
  inspect(range.child_height, content="1")
}

///|
test "left_boundary_subtree returns none when start is on leaf boundary" {
  let root : BTreeNode[TItem] = Internal(
    children=[Leaf(elem=make_item(1, 2), span=2), Leaf(elem=make_item(2, 2), span=2)],
    counts=[2, 2],
    total=4,
  )
  let start = descend_leaf_at(root, 2, 2).unwrap()
  let end_ = descend_leaf_at_end_boundary(root, 4, 2).unwrap()
  let lca = lowest_common_ancestor_range(start, end_)
  inspect(left_boundary_subtree(lca, start) is None, content="true")
}

///|
test "right_boundary_subtree returns none when end is on leaf boundary" {
  let root : BTreeNode[TItem] = Internal(
    children=[Leaf(elem=make_item(1, 2), span=2), Leaf(elem=make_item(2, 2), span=2)],
    counts=[2, 2],
    total=4,
  )
  let start = descend_leaf_at(root, 1, 2).unwrap()
  let end_ = descend_leaf_at_end_boundary(root, 2, 2).unwrap()
  let lca = lowest_common_ancestor_range(start, end_)
  inspect(right_boundary_subtree(lca, end_) is None, content="true")
}

///|
test "left_boundary_subtree rebuilds to lca child height" {
  let left_child : BTreeNode[TItem] = Internal(
    children=[Leaf(elem=make_item(1, 2), span=2), Leaf(elem=make_item(2, 1), span=1)],
    counts=[2, 1],
    total=3,
  )
  let right_child : BTreeNode[TItem] = Internal(
    children=[Leaf(elem=make_item(3, 2), span=2)],
    counts=[2],
    total=2,
  )
  let root : BTreeNode[TItem] = Internal(
    children=[left_child, right_child],
    counts=[3, 2],
    total=5,
  )
  let start = descend_leaf_at(root, 1, 2).unwrap()
  let end_ = descend_leaf_at_end_boundary(root, 4, 2).unwrap()
  let lca = lowest_common_ancestor_range(start, end_)
  let rebuilt = left_boundary_subtree(lca, start).unwrap()
  inspect(rebuilt.height(), content="1")
  inspect(rebuilt.total(), content="1")
}

///|
test "right_boundary_subtree rebuilds to lca child height" {
  let left_child : BTreeNode[TItem] = Internal(
    children=[Leaf(elem=make_item(1, 2), span=2)],
    counts=[2],
    total=2,
  )
  let right_child : BTreeNode[TItem] = Internal(
    children=[Leaf(elem=make_item(2, 1), span=1), Leaf(elem=make_item(3, 2), span=2)],
    counts=[1, 2],
    total=3,
  )
  let root : BTreeNode[TItem] = Internal(
    children=[left_child, right_child],
    counts=[2, 3],
    total=5,
  )
  let start = descend_leaf_at(root, 0, 2).unwrap()
  let end_ = descend_leaf_at_end_boundary(root, 4, 2).unwrap()
  let lca = lowest_common_ancestor_range(start, end_)
  let rebuilt = right_boundary_subtree(lca, end_).unwrap()
  inspect(rebuilt.height(), content="1")
  inspect(rebuilt.total(), content="1")
}

///|
test "plan_delete_range handles same leaf splice" {
  let root : BTreeNode[TItem] = Internal(
    children=[Leaf(elem=make_item(1, 5), span=5), Leaf(elem=make_item(2, 2), span=2)],
    counts=[5, 2],
    total=7,
  )
  let splice = plan_delete_range(root, 1, 4, 2).unwrap()
  inspect(splice.prefix.length(), content="0")
  inspect(splice.start_idx, content="0")
  inspect(splice.end_idx, content="1")
  inspect(splice.new_children.length(), content="1")
  inspect(splice.new_children[0].total(), content="2")
  inspect(splice.leaf_delta, content="0")
}

///|
test "plan_delete_range handles multi child lca splice" {
  let root : BTreeNode[TItem] = Internal(
    children=[
      Leaf(elem=make_item(1, 2), span=2),
      Leaf(elem=make_item(2, 2), span=2),
      Leaf(elem=make_item(3, 2), span=2),
    ],
    counts=[2, 2, 2],
    total=6,
  )
  let splice = plan_delete_range(root, 1, 5, 2).unwrap()
  inspect(splice.prefix.length(), content="0")
  inspect(splice.start_idx, content="0")
  inspect(splice.end_idx, content="3")
  inspect(splice.new_children.length(), content="2")
  inspect(splice.new_children[0].height(), content="0")
  inspect(splice.new_children[0].total(), content="1")
  inspect(splice.new_children[1].height(), content="0")
  inspect(splice.new_children[1].total(), content="1")
  inspect(splice.leaf_delta, content="-1")
}

///|
test "plan_delete_range merges partial kept boundaries in same parent" {
  let root : BTreeNode[TItem] = Internal(
    children=[
      Leaf(elem=make_item(1, 3), span=3),
      Leaf(elem=make_item(2, 2), span=2),
      Leaf(elem=make_item(1, 2), span=2),
    ],
    counts=[3, 2, 2],
    total=7,
  )
  let splice = plan_delete_range(root, 1, 6, 2).unwrap()
  inspect(splice.new_children.length(), content="1")
  inspect(splice.new_children[0].height(), content="0")
  inspect(splice.new_children[0].total(), content="2")
  inspect(splice.leaf_delta, content="-2")
}

///|
test "plan_delete_range merges partial kept boundaries across higher lca" {
  let left_child : BTreeNode[TItem] = Internal(
    children=[Leaf(elem=make_item(1, 3), span=3), Leaf(elem=make_item(2, 2), span=2)],
    counts=[3, 2],
    total=5,
  )
  let right_child : BTreeNode[TItem] = Internal(
    children=[Leaf(elem=make_item(3, 2), span=2), Leaf(elem=make_item(1, 2), span=2)],
    counts=[2, 2],
    total=4,
  )
  let root : BTreeNode[TItem] = Internal(
    children=[left_child, right_child],
    counts=[5, 4],
    total=9,
  )
  let splice = plan_delete_range(root, 1, 8, 2).unwrap()
  inspect(splice.prefix.length(), content="0")
  inspect(splice.start_idx, content="0")
  inspect(splice.end_idx, content="2")
  inspect(splice.new_children.length(), content="1")
  inspect(splice.new_children[0].height(), content="1")
  inspect(splice.new_children[0].total(), content="2")
  inspect(splice.leaf_delta, content="-3")
}

///|
test "plan_delete_range keeps split partial boundaries when not mergeable" {
  let root : BTreeNode[TItem] = Internal(
    children=[
      Leaf(elem=make_item(1, 3), span=3),
      Leaf(elem=make_item(2, 2), span=2),
      Leaf(elem=make_item(3, 2), span=2),
    ],
    counts=[3, 2, 2],
    total=7,
  )
  let splice = plan_delete_range(root, 1, 6, 2).unwrap()
  inspect(splice.new_children.length(), content="2")
  inspect(splice.new_children[0].total(), content="1")
  inspect(splice.new_children[1].total(), content="1")
}

///|
test "plan_delete_range absorbs exact leaf-level gap merge" {
  let root : BTreeNode[TItem] = Internal(
    children=[
      Leaf(elem=make_item(1, 3), span=3),
      Leaf(elem=make_item(2, 2), span=2),
      Leaf(elem=make_item(1, 2), span=2),
    ],
    counts=[3, 2, 2],
    total=7,
  )
  let splice = plan_delete_range(root, 3, 5, 2).unwrap()
  inspect(splice.start_idx, content="0")
  inspect(splice.end_idx, content="3")
  inspect(splice.new_children.length(), content="1")
  inspect(splice.new_children[0].total(), content="5")
  inspect(splice.leaf_delta, content="-2")
}

///|
test "plan_delete_range absorbs exact higher-level gap merge" {
  let left_child : BTreeNode[TItem] = Internal(
    children=[Leaf(elem=make_item(5, 1), span=1), Leaf(elem=make_item(1, 2), span=2)],
    counts=[1, 2],
    total=3,
  )
  let middle_child : BTreeNode[TItem] = Internal(
    children=[Leaf(elem=make_item(2, 2), span=2)],
    counts=[2],
    total=2,
  )
  let right_child : BTreeNode[TItem] = Internal(
    children=[Leaf(elem=make_item(1, 3), span=3), Leaf(elem=make_item(6, 1), span=1)],
    counts=[3, 1],
    total=4,
  )
  let root : BTreeNode[TItem] = Internal(
    children=[left_child, middle_child, right_child],
    counts=[3, 2, 4],
    total=9,
  )
  let splice = plan_delete_range(root, 3, 5, 2).unwrap()
  inspect(splice.start_idx, content="0")
  inspect(splice.end_idx, content="3")
  inspect(splice.new_children.length(), content="1")
  inspect(splice.new_children[0].height(), content="1")
  inspect(splice.new_children[0].total(), content="7")
  inspect(splice.leaf_delta, content="-2")
}
```

- [ ] **Step 2: Run tests to verify they pass**

Run: `cd lib/btree && moon test 2>&1 | tail -5`
Expected: all tests pass (existing + 15 migrated + 1 from Task 1 = total passes)

- [ ] **Step 3: Commit**

```bash
git add lib/btree/btree_wbtest.mbt
git commit -m "test(btree): migrate 15 range delete whitebox tests from order-tree"
```

---

## Task 4: Switch order-tree to lib/btree's `plan_delete_range` and delete old code

**Files:**
- Modify: `order-tree/src/order_tree.mbt:137` — change call site
- Delete: `order-tree/src/walker_range_delete.mbt` — entire file
- Modify: `order-tree/src/walker_wbtest.mbt` — remove 15 tests, keep 1

**⚠️ Compilation break point:** All four changes must happen together. The file deletion removes functions that both `order_tree.mbt` and `walker_wbtest.mbt` reference. It also removes the package-wide `using @btree {type BTreeNode}` import — without it, `bulk_build.mbt`, `invariant_wbtest.mbt`, and `walker_wbtest.mbt` lose access to unqualified `BTreeNode[T]` type annotations.

- [ ] **Step 0: Add `using @btree {type BTreeNode}` to `bulk_build.mbt`**

The `using @btree {type BTreeNode}` declaration in `walker_range_delete.mbt` is the only one in the order-tree package. MoonBit `using` is package-wide, so deleting that file removes the import for ALL order-tree files. Add it to `bulk_build.mbt` (which uses `BTreeNode[T]` in 5 type annotations):

Add at the top of `order-tree/src/bulk_build.mbt`, before the first `///|`:

```moonbit
///|
using @btree {type BTreeNode}
```

- [ ] **Step 1: Update the call site in `order_tree.mbt`**

In `order-tree/src/order_tree.mbt`, change line 137:

```moonbit
// Before:
      match plan_delete_range(root, start, end_, self.tree.min_degree) {

// After:
      match @btree.plan_delete_range(root, start, end_, self.tree.min_degree) {
```

- [ ] **Step 2: Delete `walker_range_delete.mbt`**

```bash
rm order-tree/src/walker_range_delete.mbt
```

- [ ] **Step 3: Remove 15 range-delete tests from `walker_wbtest.mbt`**

Replace the entire file content of `order-tree/src/walker_wbtest.mbt` with only the `Run` type definition and the 1 remaining test:

```moonbit
///|
priv struct Run {
  ch : String
  span : Int
} derive(Debug)

///|
impl Show for Run with output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
fn run(ch : String, span : Int) -> Run {
  { ch, span }
}

///|
impl @rle.HasLength for Run with length(self : Run) -> Int {
  self.span
}

///|
impl @rle.Spanning for Run with span(self : Run) -> Int {
  self.span
}

///|
impl @rle.Mergeable for Run with can_merge(self : Run, other : Run) -> Bool {
  self.ch == other.ch
}

///|
impl @rle.Mergeable for Run with merge(self : Run, other : Run) -> Run {
  { ch: self.ch, span: self.span + other.span }
}

///|
impl @rle.Sliceable for Run with slice(self : Run, start~ : Int, end~ : Int) -> Result[
  Run,
  @rle.RleError,
] {
  if start < 0 || end < start || end > self.span {
    return Err(
      @rle.RleError::InvalidSlice(reason=@rle.SliceError::InvalidIndex),
    )
  }
  Ok({ ch: self.ch, span: end - start })
}

///|
impl @btree.BTreeElem for Run

// === Tests for order-tree-specific behavior ===

///|
test "delete_at collapses root after propagated child removal" {
  let tree : OrderTree[Run] = OrderTree::new(min_degree=2)
  for i = 0; i < 5; i = i + 1 {
    tree.insert_at(i, run((i + 1).to_string(), 1))
  }
  ignore(tree.delete_at(0))
  ignore(tree.delete_at(0))
  ignore(tree.delete_at(0))
  inspect(tree.span(), content="2")
  inspect(
    tree.find(0).map(fn(fr) { fr.elem }),
    content=(
      #|Some({ ch: "4", span: 1 })
    ),
  )
  inspect(
    tree.find(1).map(fn(fr) { fr.elem }),
    content=(
      #|Some({ ch: "5", span: 1 })
    ),
  )
  match tree.tree.root {
    Some(Internal(children~, ..)) => inspect(children.length(), content="2")
    _ => inspect("bad root", content="\"unexpected\"")
  }
}
```

- [ ] **Step 4: Run `moon check` then `moon test` in order-tree**

Run: `cd order-tree && moon check 2>&1 && moon test 2>&1 | tail -10`
Expected: compiles and all remaining tests pass

- [ ] **Step 5: Run full test suite**

Run: `moon test 2>&1 | tail -5`
Expected: all tests pass across all packages

- [ ] **Step 6: Commit**

```bash
git add order-tree/src/order_tree.mbt order-tree/src/walker_wbtest.mbt order-tree/src/bulk_build.mbt
git rm order-tree/src/walker_range_delete.mbt
git commit -m "refactor(order-tree): delegate plan_delete_range to @btree, remove 584-line duplicate"
```

---

## Task 5: Add test-debt whitebox tests to lib/btree

**Files:**
- Modify: `lib/btree/btree_wbtest.mbt` (add 4 test groups)

These tests cover lib/btree internals that had no direct whitebox coverage after Phase 2b.

- [ ] **Step 1: Add LeafContext tests**

Append to `lib/btree/btree_wbtest.mbt`:

```moonbit
// === Test debt: LeafContext ===

///|
test "LeafContext::from_cursor extracts leaf info" {
  let root : BTreeNode[TItem] = Internal(
    children=[
      Leaf(elem=make_item(1, 3), span=3),
      Leaf(elem=make_item(2, 2), span=2),
    ],
    counts=[3, 2],
    total=5,
  )
  let cursor = descend(root, 0, 2, prepare_noop, find_slot, false).unwrap()
  let ctx = LeafContext::from_cursor(cursor)
  inspect(ctx.elem, content="{ id: 1, span: 3 }")
  inspect(ctx.span, content="3")
  inspect(ctx.child_idx, content="0")
}

///|
test "LeafContext neighbors return adjacent siblings" {
  let root : BTreeNode[TItem] = Internal(
    children=[
      Leaf(elem=make_item(1, 3), span=3),
      Leaf(elem=make_item(2, 2), span=2),
      Leaf(elem=make_item(3, 4), span=4),
    ],
    counts=[3, 2, 4],
    total=9,
  )
  // Middle leaf at position 3
  let cursor = descend(root, 3, 2, prepare_noop, find_slot, false).unwrap()
  let ctx = LeafContext::from_cursor(cursor)
  inspect(ctx.left_neighbor(), content="Some({ id: 1, span: 3 })")
  inspect(ctx.right_neighbor(), content="Some({ id: 3, span: 4 })")
}

///|
test "LeafContext boundary neighbors are None" {
  let root : BTreeNode[TItem] = Internal(
    children=[
      Leaf(elem=make_item(1, 3), span=3),
      Leaf(elem=make_item(2, 2), span=2),
    ],
    counts=[3, 2],
    total=5,
  )
  // First leaf — no left neighbor
  let left_cursor = descend(root, 0, 2, prepare_noop, find_slot, false).unwrap()
  let left_ctx = LeafContext::from_cursor(left_cursor)
  inspect(left_ctx.left_neighbor() is None, content="true")
  inspect(left_ctx.right_neighbor(), content="Some({ id: 2, span: 2 })")
  // Last leaf — no right neighbor
  let right_cursor = descend(root, 3, 2, prepare_noop, find_slot, false).unwrap()
  let right_ctx = LeafContext::from_cursor(right_cursor)
  inspect(right_ctx.left_neighbor(), content="Some({ id: 1, span: 3 })")
  inspect(right_ctx.right_neighbor() is None, content="true")
}
```

- [ ] **Step 2: Add descend_leaf_at boundary semantics tests**

```moonbit
// === Test debt: descend_leaf_at boundary semantics ===

///|
test "descend_leaf_at returns leaf containing position" {
  let root : BTreeNode[TItem] = Internal(
    children=[
      Leaf(elem=make_item(1, 3), span=3),
      Leaf(elem=make_item(2, 2), span=2),
    ],
    counts=[3, 2],
    total=5,
  )
  // Position 0 → first leaf, offset 0
  let leaf0 = descend_leaf_at(root, 0, 2).unwrap()
  inspect(leaf0.elem, content="{ id: 1, span: 3 }")
  inspect(leaf0.offset, content="0")
  // Position 2 → still first leaf, offset 2
  let leaf2 = descend_leaf_at(root, 2, 2).unwrap()
  inspect(leaf2.elem, content="{ id: 1, span: 3 }")
  inspect(leaf2.offset, content="2")
  // Position 3 → second leaf (at boundary, goes to next leaf)
  let leaf3 = descend_leaf_at(root, 3, 2).unwrap()
  inspect(leaf3.elem, content="{ id: 2, span: 2 }")
  inspect(leaf3.offset, content="0")
}

///|
test "descend_leaf_at_end_boundary stays at current leaf at boundary" {
  let root : BTreeNode[TItem] = Internal(
    children=[
      Leaf(elem=make_item(1, 3), span=3),
      Leaf(elem=make_item(2, 2), span=2),
    ],
    counts=[3, 2],
    total=5,
  )
  // End position 3 → first leaf (stays at current, offset=span=3)
  let leaf3 = descend_leaf_at_end_boundary(root, 3, 2).unwrap()
  inspect(leaf3.elem, content="{ id: 1, span: 3 }")
  inspect(leaf3.offset, content="3")
  inspect(leaf3.span, content="3")
  // End position 5 → second leaf (at end, offset=span=2)
  let leaf5 = descend_leaf_at_end_boundary(root, 5, 2).unwrap()
  inspect(leaf5.elem, content="{ id: 2, span: 2 }")
  inspect(leaf5.offset, content="2")
}
```

- [ ] **Step 3: Add ensure_min_children test**

```moonbit
// === Test debt: ensure_min_children rebalancing ===

///|
test "ensure_min_children borrows from right sibling" {
  // min_degree=2: need at least 2 children
  let underfull : BTreeNode[TItem] = Internal(
    children=[Leaf(elem=make_item(1, 1), span=1)],
    counts=[1],
    total=1,
  )
  let donor : BTreeNode[TItem] = Internal(
    children=[
      Leaf(elem=make_item(2, 1), span=1),
      Leaf(elem=make_item(3, 1), span=1),
      Leaf(elem=make_item(4, 1), span=1),
    ],
    counts=[1, 1, 1],
    total=3,
  )
  let children : Array[BTreeNode[TItem]] = [underfull, donor]
  let counts : Array[Int] = [1, 3]
  ensure_min_children(children, counts, 0, 2)
  // After borrow: underfull gets 2 children, donor keeps 2
  match children[0] {
    Internal(children=c, ..) => inspect(c.length(), content="2")
    _ => abort("expected internal node")
  }
  match children[1] {
    Internal(children=c, ..) => inspect(c.length(), content="2")
    _ => abort("expected internal node")
  }
  // Counts updated
  inspect(counts[0], content="2")
  inspect(counts[1], content="2")
}
```

- [ ] **Step 4: Add propagate_node_splice test**

```moonbit
// === Test debt: propagate_node_splice ===

///|
test "propagate_node_splice updates ancestor counts after removal" {
  // Build a 3-leaf tree: [a(2), b(3), c(4)] total=9
  let root : BTreeNode[TItem] = Internal(
    children=[
      Leaf(elem=make_item(1, 2), span=2),
      Leaf(elem=make_item(2, 3), span=3),
      Leaf(elem=make_item(3, 4), span=4),
    ],
    counts=[2, 3, 4],
    total=9,
  )
  // Splice that removes the middle child (index 1)
  let splice : NodeSplice[TItem] = {
    prefix: [],
    children: match root {
      Internal(children~, ..) => children
      _ => abort("expected internal")
    },
    counts: match root {
      Internal(counts~, ..) => counts
      _ => abort("expected internal")
    },
    start_idx: 1,
    end_idx: 2,
    new_children: [],
    original_child_count: 3,
    leaf_delta: -1,
  }
  let result = propagate_node_splice(splice, 2)
  inspect(result.leaf_delta, content="-1")
  // Resulting node should have total = 2 + 4 = 6
  inspect(result.node.total(), content="6")
}
```

- [ ] **Step 5: Run tests**

Run: `cd lib/btree && moon test 2>&1 | tail -5`
Expected: all tests pass

**⚠️ Note:** Some `inspect` content values may need updating via `moon test --update` if the actual output format differs slightly. Run `moon test --update` only if the logic is correct but the formatting differs.

- [ ] **Step 6: Commit**

```bash
git add lib/btree/btree_wbtest.mbt
git commit -m "test(btree): add whitebox tests for LeafContext, descent boundary, ensure_min, propagate_node_splice"
```

---

## Task 6: Cleanup and verify

**Files:**
- Modify: `docs/TODO.md`
- Run: formatting and interface checks

- [ ] **Step 1: Run formatting and interface generation**

```bash
moon info && moon fmt
```

- [ ] **Step 2: Check for API changes**

```bash
git diff *.mbti
```

Expected: `lib/btree/pkg.generated.mbti` adds `descend_rightmost` and `plan_delete_range` as pub functions. No unintended trait bound widening.

- [ ] **Step 3: Run full test suite**

```bash
moon test
cd order-tree && moon test
cd event-graph-walker && moon test
```

Expected: all tests pass everywhere

- [ ] **Step 4: Update `docs/TODO.md`**

Mark Phase 2c as done. Update Phase 2d with any newly discovered items.

- [ ] **Step 5: Final commit**

```bash
git add -A
git commit -m "chore: Phase 2c cleanup — moon info, fmt, TODO update"
```

---

## Validation

```bash
cd lib/btree && moon test                # lib/btree tests (existing + 16 new)
cd order-tree && moon test               # order-tree tests (1 remaining walker test)
cd event-graph-walker && moon test       # CRDT integration
moon test                                # Full module
moon check && moon fmt && moon info      # Lint
```

## Summary

| Metric | Before | After |
|--------|--------|-------|
| order-tree/src/walker_range_delete.mbt | 584 lines | deleted |
| order-tree/src/walker_wbtest.mbt tests | 16 tests | 1 test |
| lib/btree/walker_range_delete.mbt | — | ~530 lines |
| lib/btree/btree_wbtest.mbt tests | existing | +16 migrated + 4 test debt |
| lib/btree pub API | — | +descend_rightmost, +plan_delete_range |
