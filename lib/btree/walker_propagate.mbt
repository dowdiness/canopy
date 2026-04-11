// Propagation: after a leaf splice, rebuild ancestors bottom-up,
// splitting any node that exceeds 2*min_degree children.

///|
/// Split a full internal node at its midpoint, producing two balanced halves.
/// Maintains the B-tree invariant: each half has >= min_degree children.
fn[T] split_internal(
  children : Array[BTreeNode[T]],
  counts : Array[Int],
) -> (BTreeNode[T], BTreeNode[T]) {
  let mid = children.length() / 2
  let left_children : Array[BTreeNode[T]] = Array::new(capacity=mid)
  let left_counts : Array[Int] = Array::new(capacity=mid)
  let mut left_total = 0
  for i in 0..<mid {
    left_children.push(children[i])
    left_counts.push(counts[i])
    left_total = left_total + counts[i]
  }
  let right_children : Array[BTreeNode[T]] = Array::new(
    capacity=children.length() - mid,
  )
  let right_counts : Array[Int] = Array::new(capacity=children.length() - mid)
  let mut right_total = 0
  for i in mid..<children.length() {
    right_children.push(children[i])
    right_counts.push(counts[i])
    right_total = right_total + counts[i]
  }
  (
    Internal(children=left_children, counts=left_counts, total=left_total),
    Internal(children=right_children, counts=right_counts, total=right_total),
  )
}

///|
fn[T] apply_splice(
  children : Array[BTreeNode[T]],
  counts : Array[Int],
  splice : Splice[T],
) -> Unit {
  let remove_count = splice.end_idx - splice.start_idx
  for _ in 0..<remove_count {
    let _ = children.remove(splice.start_idx)
    let _ = counts.remove(splice.start_idx)
  }
  if splice.new_leaves.length() == 0 {
    return
  }
  // Insert in reverse so each goes to start_idx in correct final order
  for i in (splice.new_leaves.length() - 1)>=..0 {
    let (elem, span) = splice.new_leaves[i]
    children.insert(splice.start_idx, Leaf(elem~, span~))
    counts.insert(splice.start_idx, span)
  }
}

///|
fn[T] apply_node_splice(
  children : Array[BTreeNode[T]],
  counts : Array[Int],
  start_idx : Int,
  end_idx : Int,
  new_children : Array[BTreeNode[T]],
) -> Unit {
  let remove_count = end_idx - start_idx
  for _ in 0..<remove_count {
    let _ = children.remove(start_idx)
    let _ = counts.remove(start_idx)
  }
  if new_children.length() == 0 {
    return
  }
  for i in (new_children.length() - 1)>=..0 {
    let child = new_children[i]
    children.insert(start_idx, child)
    counts.insert(start_idx, child.total())
  }
}

///|
fn[T] maybe_split(
  children : Array[BTreeNode[T]],
  counts : Array[Int],
  min_degree : Int,
) -> (BTreeNode[T], BTreeNode[T]?) {
  let total = counts.sum()
  if children.length() > 2 * min_degree {
    let (left, right) = split_internal(children, counts)
    (left, Some(right))
  } else {
    (Internal(children~, counts~, total~), None)
  }
}

///|
/// Repair an underfull node after a range splice. Uses < min_degree threshold
/// (reactive) unlike ensure_min_children which uses <= min_degree (proactive).
fn[T] ensure_min_after_splice(
  children : Array[BTreeNode[T]],
  counts : Array[Int],
  idx : Int,
  min_degree : Int,
) -> Unit {
  guard children[idx].is_underfull(min_degree) else { return }
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
    if current_node.is_underfull(min_degree) && frame.children.length() > 1 {
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

///|
/// Rebuild ancestors after a leaf-level splice. Walks bottom-up from
/// the leaf's parent, applying the splice then propagating splits upward.
/// Leaf delta is derived from the splice (new_leaves added - old range removed).
fn[T] propagate(
  path : Array[PathFrame[T]],
  splice : Splice[T],
  min_degree : Int,
) -> PropagateResult[T] {
  guard path.length() > 0 else { abort("propagate: empty path") }
  let leaf_delta = splice.new_leaves.length() -
    (splice.end_idx - splice.start_idx)
  let leaf_parent = path[path.length() - 1]
  apply_splice(leaf_parent.children, leaf_parent.counts, splice)
  let (initial_node, initial_overflow) = maybe_split(
    leaf_parent.children,
    leaf_parent.counts,
    min_degree,
  )
  let (node, overflow) = walk_up_ancestors(
    path,
    path.length() - 2,
    initial_node,
    initial_overflow,
    min_degree,
  )
  { node, overflow, leaf_delta }
}

///|
/// Rebuild ancestors after a subtree-level splice (used by range delete).
fn[T] propagate_node_splice(
  splice : NodeSplice[T],
  min_degree : Int,
) -> PropagateResult[T] {
  let insert_count = splice.new_children.length()
  let insert_start = splice.start_idx
  apply_node_splice(
    splice.children,
    splice.counts,
    splice.start_idx,
    splice.end_idx,
    splice.new_children,
  )
  // Repair underfull boundary subtree roots at their insertion positions.
  // Chain repair fixes internal underfull descendants, but the root itself
  // may still be underfull and needs material from adjacent LCA children.
  // Only triggers for range-delete boundary subtrees — leaves and valid
  // internals pass the is_underfull check as no-ops.
  let mut pos = insert_start
  for _ in 0..<insert_count {
    // Loop: one borrow isn't enough for min_degree > 2 when boundary
    // root is heavily underfull. Keep repairing until valid or merged.
    while pos < splice.children.length() &&
      splice.children[pos].is_underfull(min_degree) &&
      splice.children.length() > 1 {
      let len_before = splice.children.length()
      ensure_min_after_splice(splice.children, splice.counts, pos, min_degree)
      if splice.children.length() < len_before {
        // Merge removed a sibling — break inner loop, re-check in outer
        break
      }
    }
    pos += 1
  }
  let (initial_node, initial_overflow) = maybe_split(
    splice.children,
    splice.counts,
    min_degree,
  )
  let (node, overflow) = walk_up_ancestors(
    splice.prefix,
    splice.prefix.length() - 1,
    initial_node,
    initial_overflow,
    min_degree,
  )
  { node, overflow, leaf_delta: splice.leaf_delta }
}
