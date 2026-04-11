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
/// Rebuild a boundary chain from the path suffix below the LCA.
/// When seed is None, the bottom frame contributes only its kept siblings.
fn[T] rebuild_boundary_chain_optional(
  path_suffix : Array[PathFrame[T]],
  leaf : BTreeNode[T]?,
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
    }
    if current is Some(node) {
      children.push(node)
      counts.push(node.total())
    }
    if !keep_left {
      for j in (frame.child_idx + 1)..<frame.children.length() {
        children.push(frame.children[j])
        counts.push(frame.counts[j])
      }
    }
    // Skip empty levels — don't create Internal(children=[], ...) nodes.
    // Ancestor frames will collect their siblings at a higher level.
    if children.length() > 0 {
      current = Some(Internal(children~, counts~, total=counts.sum()))
    }
  }
  current.unwrap()
}

///|
fn[T : BTreeElem] left_boundary_keep(start : LeafCursor[T]) -> T? {
  guard start.offset != 0 else { return None }
  Some(must_slice(start.elem, start=0, end=start.offset))
}

///|
fn[T : BTreeElem] right_boundary_keep(end_ : LeafCursor[T]) -> T? {
  guard end_.offset != end_.span else { return None }
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
/// Rebuild the left boundary subtree, keeping all siblings before the
/// start leaf plus the sliced fragment of the start leaf (if any).
/// Returns None only when there is truly nothing to keep on the left.
fn[T : BTreeElem] left_boundary_subtree(
  lca : AncestorRange[T],
  start : LeafCursor[T],
) -> BTreeNode[T]? {
  let kept_leaf = left_boundary_keep(start).map(fn(kept) {
    Leaf(elem=kept, span=@rle.Spanning::span(kept))
  })
  let suffix = path_suffix_after_target(start.path, lca.prefix.length())
  // Check ANY frame for left siblings, not just the deepest — ancestors
  // may have siblings even when the leaf-parent doesn't.
  let has_siblings = suffix.iter().any(fn(frame) { frame.child_idx > 0 })
  guard kept_leaf is Some(_) || has_siblings else { return None }
  Some(rebuild_boundary_chain_optional(suffix, kept_leaf, true))
}

///|
/// Rebuild the right boundary subtree, keeping the sliced fragment of the
/// end leaf (if any) plus all siblings after the end leaf.
/// Returns None only when there is truly nothing to keep on the right.
fn[T : BTreeElem] right_boundary_subtree(
  lca : AncestorRange[T],
  end_ : LeafCursor[T],
) -> BTreeNode[T]? {
  let kept_leaf = right_boundary_keep(end_).map(fn(kept) {
    Leaf(elem=kept, span=@rle.Spanning::span(kept))
  })
  let suffix = path_suffix_after_target(end_.path, lca.prefix.length())
  // Check ANY frame for right siblings, not just the deepest.
  let has_siblings = suffix
    .iter()
    .any(fn(frame) { frame.child_idx + 1 < frame.children.length() })
  guard kept_leaf is Some(_) || has_siblings else { return None }
  Some(rebuild_boundary_chain_optional(suffix, kept_leaf, false))
}

///|
fn[T] BTreeNode::leaf_count(self : BTreeNode[T]) -> Int {
  match self {
    Leaf(..) => 1
    Internal(children~, ..) =>
      for child in children; total = 0 {
        continue total + child.leaf_count()
      } nobreak {
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
  min_degree : Int,
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
  let merged_subtree = fix_merged_chain(
    merge_boundary_chain(left_edge.path, right_edge.path, merged_leaf),
    min_degree,
  )
  ([merged_subtree], start_idx - 1, end_idx + 1, true)
}

///|
fn[T : BTreeElem] promote_empty_child_gap_merge(
  lca : AncestorRange[T],
  min_degree : Int,
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
  let merged_subtree = fix_merged_chain(
    merge_boundary_chain(left_edge.path, right_edge.path, merged_leaf),
    min_degree,
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
    leaf_delta: leaf_count_of_array(new_children) - removed_leaf_count,
  })
}

///|
/// Plan a range delete over [start, end_) on a B-tree.
/// Returns a NodeSplice describing the structural changes, or None if
/// the range is invalid or empty. The caller is responsible for
/// propagating the splice and handling root lifecycle.
fn[T : BTreeElem] plan_delete_range(
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
          min_degree,
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
          match promote_empty_child_gap_merge(lca, min_degree) {
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
          leaf_delta: leaf_count_of_array(normalized_children) -
          removed_leaf_count,
        })
      }
      let new_children : Array[BTreeNode[T]] = []
      match left_boundary_subtree(lca, start_leaf) {
        Some(left) =>
          new_children.push(fix_left_border(left, min_degree))
        None => ()
      }
      match right_boundary_subtree(lca, end_leaf) {
        Some(right) =>
          new_children.push(fix_right_border(right, min_degree))
        None => ()
      }
      let (normalized_children, normalized_start_idx, normalized_end_idx, _) = absorb_subtree_gap_merge(
        lca,
        start_leaf,
        end_leaf,
        new_children,
        lca.start_idx,
        lca.end_idx,
        min_degree,
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
        leaf_delta: leaf_count_of_array(normalized_children) -
        removed_leaf_count,
      })
    }
    _ => None
  }
}

///|
/// Post-splice boundary normalization: if the leaves at the splice boundary
/// are mergeable, merge them and propagate the structural change.
/// `boundary_pos` is the position where the deleted range started (after deletion,
/// the left boundary's last leaf ends here and the right boundary's first leaf starts here).
/// Returns the updated root node and whether a merge occurred (for leaf_delta tracking).
fn[T : BTreeElem] normalize_boundary_merge(
  root : BTreeNode[T],
  boundary_pos : Int,
  min_degree : Int,
) -> (BTreeNode[T], Bool) {
  // Nothing to merge at boundaries
  guard boundary_pos > 0 && boundary_pos < root.total() else {
    return (root, false)
  }
  // Descend to the leaf just before the boundary (end-boundary semantics)
  let left_cursor = descend_leaf_at_end_boundary(root, boundary_pos, min_degree)
  // Descend to the leaf at the boundary (start semantics)
  let right_cursor = descend_leaf_at(root, boundary_pos, min_degree)
  match (left_cursor, right_cursor) {
    (Some(left), Some(right)) => {
      // Check if these are different leaves
      if left.path.length() == right.path.length() &&
        shared_prefix_length(left.path, right.path) == left.path.length() {
        // Same leaf — no boundary merge needed
        return (root, false)
      }
      // Not at leaf boundaries — can't merge whole leaves
      guard left.offset == left.span && right.offset == 0 else {
        return (root, false)
      }
      // Check if mergeable
      guard @rle.Mergeable::can_merge(left.elem, right.elem) else {
        return (root, false)
      }
      // Merge: delete the right leaf, expand the left leaf to absorb it
      let merged = @rle.Mergeable::merge(left.elem, right.elem)
      let merged_span = @rle.Spanning::span(merged)
      let merged_leaf : BTreeNode[T] = Leaf(elem=merged, span=merged_span)
      let lca = lowest_common_ancestor_range(left, right)
      let left_suffix = path_suffix_after_target(left.path, lca.prefix.length())
      let right_suffix = path_suffix_after_target(
        right.path,
        lca.prefix.length(),
      )
      let merged_subtree = fix_merged_chain(
        merge_boundary_chain(left_suffix, right_suffix, merged_leaf),
        min_degree,
      )
      let removed_leaf_count = leaf_count_of_children(
        lca.children,
        lca.start_idx,
        lca.end_idx,
      )
      let splice : NodeSplice[T] = {
        prefix: lca.prefix,
        children: lca.children,
        counts: lca.counts,
        start_idx: lca.start_idx,
        end_idx: lca.end_idx,
        new_children: [merged_subtree],
        leaf_delta: merged_subtree.leaf_count() - removed_leaf_count,
      }
      let result = propagate_node_splice(splice, min_degree)
      let new_root = match result.overflow {
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
      (new_root, true)
    }
    _ => (root, false)
  }
}
