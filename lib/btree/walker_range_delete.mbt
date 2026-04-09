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
      let merged_leaf = Leaf(elem=merged, span=@rle.Spanning::span(merged))
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
  let merged_children = new_children
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
  let merged_leaf = Leaf(elem=merged, span=@rle.Spanning::span(merged))
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
  let merged_leaf = Leaf(elem=merged, span=@rle.Spanning::span(merged))
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
  let end_cursor = descend_leaf_at_end_boundary(root, clamped_end, min_degree)
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
