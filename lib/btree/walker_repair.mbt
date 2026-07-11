// Top-down border repair for underfull boundary subtrees after delete_range.
//
// After rebuild_boundary_chain_optional constructs a boundary subtree,
// nodes along the boundary path may be underfull (< min_degree children).
// These nodes form a chain with no siblings to borrow from in isolation.
//
// The fix runs top-down: at each level, stock the border child from its
// interior sibling via merge-or-bulk-steal, then recurse into it. Stocking
// to min_degree+1 (not just min_degree) ensures the node can survive a
// merge one level below.
//
// This follows Rust BTreeMap's fix_left_border / fix_right_border pattern
// from fix.rs.

///|
/// Shallow-copy an Internal node's children/counts arrays.
/// Prevents borrow/merge from mutating original tree nodes via shared refs.
fn[T] BTreeNode::shallow_copy(self : BTreeNode[T]) -> BTreeNode[T] {
  match self {
    Leaf(..) => self
    Internal(children~, counts~, total~) =>
      Internal(children=children.copy(), counts=counts.copy(), total~)
  }
}

///|
/// Number of children for Internal nodes, 0 for Leaves.
fn[T] BTreeNode::child_count(self : BTreeNode[T]) -> Int {
  match self {
    Leaf(..) => 0
    Internal(children~, ..) => children.length()
  }
}

///|
/// Move the last `k` children from the left sibling into the front of the
/// target node. Both must be Internal. Updates counts and totals.
fn[T] bulk_steal_from_left(
  children : Array[BTreeNode[T]],
  counts : Array[Int],
  idx : Int,
  k : Int,
) -> Unit {
  match (children[idx - 1], children[idx]) {
    (
      Internal(children=left_ch, counts=left_cn, total=left_total),
      Internal(children=target_ch, counts=target_cn, total=target_total),
    ) => {
      let mut transferred = 0
      for _ in 0..<k {
        let last = left_ch.length() - 1
        let child = left_ch.remove(last)
        let count = left_cn.remove(last)
        target_ch.insert(0, child)
        target_cn.insert(0, count)
        transferred += count
      }
      children[idx - 1] = Internal(
        children=left_ch,
        counts=left_cn,
        total=left_total - transferred,
      )
      children[idx] = Internal(
        children=target_ch,
        counts=target_cn,
        total=target_total + transferred,
      )
      counts[idx - 1] = left_total - transferred
      counts[idx] = target_total + transferred
    }
    _ => abort("bulk_steal_from_left: expected internal nodes")
  }
}

///|
/// Move the first `k` children from the right sibling into the end of the
/// target node. Both must be Internal. Updates counts and totals.
fn[T] bulk_steal_from_right(
  children : Array[BTreeNode[T]],
  counts : Array[Int],
  idx : Int,
  k : Int,
) -> Unit {
  match (children[idx], children[idx + 1]) {
    (
      Internal(children=target_ch, counts=target_cn, total=target_total),
      Internal(children=right_ch, counts=right_cn, total=right_total),
    ) => {
      let mut transferred = 0
      for _ in 0..<k {
        let child = right_ch.remove(0)
        let count = right_cn.remove(0)
        target_ch.push(child)
        target_cn.push(count)
        transferred += count
      }
      children[idx] = Internal(
        children=target_ch,
        counts=target_cn,
        total=target_total + transferred,
      )
      children[idx + 1] = Internal(
        children=right_ch,
        counts=right_cn,
        total=right_total - transferred,
      )
      counts[idx] = target_total + transferred
      counts[idx + 1] = right_total - transferred
    }
    _ => abort("bulk_steal_from_right: expected internal nodes")
  }
}

///|
/// Fix underfull nodes along the right border of a left boundary subtree.
/// The border child is the rightmost at each level (the deletion boundary).
///
/// Top-down: at each level, if the border child is underfull, stock it from
/// its left sibling via merge-or-bulk-steal, then recurse into it.
fn[T] fix_left_border(node : BTreeNode[T], min_degree : Int) -> BTreeNode[T] {
  match node {
    Leaf(..) => node
    Internal(children~, counts~, ..) => {
      guard children.length() > 1 else { return node }
      let children = children.copy()
      let counts = counts.copy()
      let border_idx = children.length() - 1
      // Stock the border child if underfull, THEN recurse (top-down order).
      // After stocking, the border child has siblings from the steal/merge,
      // so deeper levels can also be fixed.
      if children[border_idx].is_underfull(min_degree) {
        let sibling_idx = border_idx - 1
        children[sibling_idx] = children[sibling_idx].shallow_copy()
        children[border_idx] = children[border_idx].shallow_copy()
        let r = children[border_idx].child_count()
        let s = children[sibling_idx].child_count()
        if r + s <= 2 * min_degree {
          merge_children(children, counts, sibling_idx)
          // After merge, the merged node is the new rightmost
          let new_border = children.length() - 1
          let fixed = fix_left_border(children[new_border], min_degree)
          children[new_border] = fixed
          counts[new_border] = fixed.total()
        } else {
          let steal_count = min_degree + 1 - r
          bulk_steal_from_left(children, counts, border_idx, steal_count)
          let fixed = fix_left_border(children[border_idx], min_degree)
          children[border_idx] = fixed
          counts[border_idx] = fixed.total()
        }
      } else {
        // Border child is valid at this level; recurse for deeper levels
        let fixed = fix_left_border(children[border_idx], min_degree)
        children[border_idx] = fixed
        counts[border_idx] = fixed.total()
      }
      Internal(children~, counts~, total=counts.sum())
    }
  }
}

///|
/// Fix any underfull child in a merged boundary chain subtree.
/// Unlike fix_left/right_border which only walk one edge, this scans
/// all children at each level. Used for merge_boundary_chain output
/// where the underfull node can be at an interior position.
///
/// Top-down: at each level, find any underfull child, stock it via
/// merge-or-bulk-steal, then recurse into the result.
/// Scan children for underfull nodes and fix via merge-or-bulk-steal.
fn[T] repair_underfull_children(
  children : Array[BTreeNode[T]],
  counts : Array[Int],
  min_degree : Int,
) -> Unit {
  let mut i = 0
  while i < children.length() {
    if children[i].is_underfull(min_degree) && children.length() > 1 {
      let sibling_idx = if i > 0 { i - 1 } else { i + 1 }
      children[sibling_idx] = children[sibling_idx].shallow_copy()
      children[i] = children[i].shallow_copy()
      let r = children[i].child_count()
      let s = children[sibling_idx].child_count()
      if r + s <= 2 * min_degree {
        let merge_idx = if i > 0 { i - 1 } else { 0 }
        merge_children(children, counts, merge_idx)
        i = merge_idx
      } else {
        let steal_count = min_degree + 1 - r
        if i > 0 {
          bulk_steal_from_left(children, counts, i, steal_count)
        } else {
          bulk_steal_from_right(children, counts, i, steal_count)
        }
        i += 1
      }
    } else {
      i += 1
    }
  }
}

///|
fn[T] fix_merged_chain(node : BTreeNode[T], min_degree : Int) -> BTreeNode[T] {
  match node {
    Leaf(..) => node
    Internal(children~, counts~, ..) => {
      guard children.length() > 1 else { return node }
      let children = children.copy()
      let counts = counts.copy()
      repair_underfull_children(children, counts, min_degree)
      // Recurse into all children to fix deeper levels.
      for j in 0..<children.length() {
        let fixed = fix_merged_chain(children[j], min_degree)
        children[j] = fixed
        counts[j] = fixed.total()
      }
      // Post-recursion repair: a child merge at depth D+1 can leave
      // a child at depth D with fewer than min_degree children.
      repair_underfull_children(children, counts, min_degree)
      Internal(children~, counts~, total=counts.sum())
    }
  }
}

///|
/// Fix underfull nodes along the left border of a right boundary subtree.
/// The border child is the leftmost at each level (the deletion boundary).
///
/// Top-down: at each level, if the border child is underfull, stock it from
/// its right sibling via merge-or-bulk-steal, then recurse into it.
fn[T] fix_right_border(node : BTreeNode[T], min_degree : Int) -> BTreeNode[T] {
  match node {
    Leaf(..) => node
    Internal(children~, counts~, ..) => {
      guard children.length() > 1 else { return node }
      let children = children.copy()
      let counts = counts.copy()
      let border_idx = 0
      if children[border_idx].is_underfull(min_degree) {
        let sibling_idx = 1
        children[sibling_idx] = children[sibling_idx].shallow_copy()
        children[border_idx] = children[border_idx].shallow_copy()
        let r = children[border_idx].child_count()
        let s = children[sibling_idx].child_count()
        if r + s <= 2 * min_degree {
          merge_children(children, counts, 0)
          // After merge, the merged node is at index 0
          let fixed = fix_right_border(children[0], min_degree)
          children[0] = fixed
          counts[0] = fixed.total()
        } else {
          let steal_count = min_degree + 1 - r
          bulk_steal_from_right(children, counts, border_idx, steal_count)
          let fixed = fix_right_border(children[0], min_degree)
          children[0] = fixed
          counts[0] = fixed.total()
        }
      } else {
        let fixed = fix_right_border(children[0], min_degree)
        children[0] = fixed
        counts[0] = fixed.total()
      }
      Internal(children~, counts~, total=counts.sum())
    }
  }
}
