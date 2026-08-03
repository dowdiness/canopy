// Propagation: after a splice, rebuild ancestors bottom-up as complete,
// same-height segments and repair underfull children before packing each level.

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
    left_total = add_spans_or_abort(left_total, counts[i])
  }
  let right_children : Array[BTreeNode[T]] = Array::new(
    capacity=children.length() - mid,
  )
  let right_counts : Array[Int] = Array::new(capacity=children.length() - mid)
  let mut right_total = 0
  for i in mid..<children.length() {
    right_children.push(children[i])
    right_counts.push(counts[i])
    right_total = add_spans_or_abort(right_total, counts[i])
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
) -> (Array[BTreeNode[T]], Array[Int]) {
  let new_children : Array[BTreeNode[T]] = splice.new_leaves.map(pair => {
    Leaf(elem=pair.0, span=pair.1)
  })
  apply_node_splice(
    children,
    counts,
    splice.start_idx,
    splice.end_idx,
    new_children,
  )
}

///|
fn[T] apply_node_splice(
  children : Array[BTreeNode[T]],
  counts : Array[Int],
  start_idx : Int,
  end_idx : Int,
  new_children : Array[BTreeNode[T]],
) -> (Array[BTreeNode[T]], Array[Int]) {
  let result : Array[BTreeNode[T]] = []
  let result_counts : Array[Int] = []
  result.append(children[:start_idx])
  result_counts.append(counts[:start_idx])
  result.append(new_children[:])
  result_counts.append(new_children.map(child => child.total())[:])
  result.append(children[end_idx:])
  result_counts.append(counts[end_idx:])
  (result, result_counts)
}

///|
/// Return the existing bottom-up grouping policy as scalar chunk sizes.
/// For `child_count >= min_degree`, every size is in
/// `[min_degree, 2 * min_degree]` and the sizes sum to `child_count`.
fn legal_chunk_sizes(child_count : Int, min_degree : Int) -> Array[Int] {
  guard child_count >= min_degree else {
    abort("legal_chunk_sizes: child count is underfull")
  }
  let max_degree = 2 * min_degree
  let sizes : Array[Int] = []
  let mut remaining = child_count
  while remaining > max_degree {
    let chunk_size = if remaining - max_degree < min_degree {
      remaining / 2
    } else {
      max_degree
    }
    sizes.push(chunk_size)
    remaining = remaining - chunk_size
  }
  sizes.push(remaining)
  sizes
}

///|
/// Pack one level into a complete ordered segment. An empty input stays empty;
/// one underfull node is carried upward until its parent can repair it.
fn[T] pack_level(
  children : Array[BTreeNode[T]],
  min_degree : Int,
) -> Array[BTreeNode[T]] {
  guard !children.is_empty() else { return [] }
  if children.length() < min_degree {
    return [make_internal(children)]
  }
  let sizes = legal_chunk_sizes(children.length(), min_degree)
  if sizes.length() == 1 {
    return [make_internal(children)]
  }
  let nodes : Array[BTreeNode[T]] = []
  let mut offset = 0
  for size in sizes {
    nodes.push(make_internal(children[offset:offset + size].to_owned()))
    offset = offset + size
  }
  nodes
}

///|
/// Walk a complete same-height segment upward through ancestor frames.
fn[T] walk_up_ancestors(
  path : Array[PathFrame[T]],
  start_from : Int,
  initial_segment : Array[BTreeNode[T]],
  min_degree : Int,
) -> Array[BTreeNode[T]] {
  let mut segment = initial_segment
  for i in start_from>=..0 {
    let frame = path[i]
    let (children, counts) = apply_node_splice(
      frame.children,
      frame.counts,
      frame.child_idx,
      frame.child_idx + 1,
      segment,
    )
    repair_underfull_children(children, counts, min_degree, min_degree)
    segment = pack_level(children, min_degree)
  }
  segment
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
  validate_positive_spans(splice.new_leaves, "BTree splice")
  let leaf_delta = splice.new_leaves.length() -
    (splice.end_idx - splice.start_idx)
  let leaf_parent = path[path.length() - 1]
  let (children, _) = apply_splice(
    leaf_parent.children,
    leaf_parent.counts,
    splice,
  )
  let initial_segment = pack_level(children, min_degree)
  let segment = walk_up_ancestors(
    path,
    path.length() - 2,
    initial_segment,
    min_degree,
  )
  { segment, leaf_delta }
}

///|
/// Rebuild ancestors after a subtree-level splice (used by range delete).
fn[T] propagate_node_splice(
  splice : NodeSplice[T],
  min_degree : Int,
) -> PropagateResult[T] {
  let (children, counts) = apply_node_splice(
    splice.children,
    splice.counts,
    splice.start_idx,
    splice.end_idx,
    splice.new_children,
  )
  // Boundary-chain repair can leave more than one adjacent subtree root
  // underfull. Repair the complete replacement before packing it upward.
  repair_underfull_children(children, counts, min_degree, min_degree)
  let initial_segment = pack_level(children, min_degree)
  let segment = walk_up_ancestors(
    splice.prefix,
    splice.prefix.length() - 1,
    initial_segment,
    min_degree,
  )
  { segment, leaf_delta: splice.leaf_delta }
}
