///|
/// Find which child slot contains span position `pos`.
/// Strict (<): position at a slot boundary falls into the next slot.
fn find_slot(counts : Array[Int], pos : Int, _total : Int) -> (Int, Int) {
  guard counts.length() > 0 else { abort("find_slot: empty counts") }
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
/// Find which child slot to insert into at span position `pos`.
/// Inclusive (<=): position at a slot boundary stays in the current slot.
fn find_slot_inclusive(
  counts : Array[Int],
  pos : Int,
  _total : Int,
) -> (Int, Int) {
  guard counts.length() > 0 else { abort("find_slot_inclusive: empty counts") }
  match
    counts[:counts.length() - 1].find_by_sum(
      pos,
      in_slot=fn(remaining, count) { remaining <= count },
      fn(i, remaining) { Some((i, remaining)) },
    ) {
    Some(pair) => pair
    None => {
      let last = counts.length() - 1
      (last, pos - (_total - counts[last]))
    }
  }
}

///|
fn[T] prepare_noop(
  _children : Array[BTreeNode[T]],
  _counts : Array[Int],
  _idx : Int,
  _min_degree : Int,
) -> Unit {

}

///|
/// Borrow one child from left sibling — cheaper than merge (O(1) rotation,
/// preserves node count). Used when target is underfull but sibling has spare.
fn[T] borrow_from_left(
  children : Array[BTreeNode[T]],
  counts : Array[Int],
  idx : Int,
) -> Unit {
  let left = children[idx - 1]
  let target = children[idx]
  match (left, target) {
    (
      Internal(children=left_ch, counts=left_cn, total=left_total),
      Internal(children=target_ch, counts=target_cn, total=target_total),
    ) => {
      let last_idx = left_ch.length() - 1
      let borrowed_child = left_ch.remove(last_idx)
      let borrowed_count = left_cn.remove(last_idx)
      target_ch.insert(0, borrowed_child)
      target_cn.insert(0, borrowed_count)
      let new_left_total = left_total - borrowed_count
      let new_target_total = target_total + borrowed_count
      children[idx - 1] = Internal(
        children=left_ch,
        counts=left_cn,
        total=new_left_total,
      )
      children[idx] = Internal(
        children=target_ch,
        counts=target_cn,
        total=new_target_total,
      )
      counts[idx - 1] = new_left_total
      counts[idx] = new_target_total
    }
    _ => abort("borrow_from_left: expected internal nodes")
  }
}

///|
fn[T] borrow_from_right(
  children : Array[BTreeNode[T]],
  counts : Array[Int],
  idx : Int,
) -> Unit {
  let target = children[idx]
  let right = children[idx + 1]
  match (target, right) {
    (
      Internal(children=target_ch, counts=target_cn, total=target_total),
      Internal(children=right_ch, counts=right_cn, total=right_total),
    ) => {
      let borrowed_child = right_ch.remove(0)
      let borrowed_count = right_cn.remove(0)
      target_ch.push(borrowed_child)
      target_cn.push(borrowed_count)
      let new_target_total = target_total + borrowed_count
      let new_right_total = right_total - borrowed_count
      children[idx] = Internal(
        children=target_ch,
        counts=target_cn,
        total=new_target_total,
      )
      children[idx + 1] = Internal(
        children=right_ch,
        counts=right_cn,
        total=new_right_total,
      )
      counts[idx] = new_target_total
      counts[idx + 1] = new_right_total
    }
    _ => abort("borrow_from_right: expected internal nodes")
  }
}

///|
fn[T] merge_children(
  children : Array[BTreeNode[T]],
  counts : Array[Int],
  idx : Int,
) -> Unit {
  let left = children[idx]
  let right = children[idx + 1]
  match (left, right) {
    (
      Internal(children=left_ch, counts=left_cn, total=left_total),
      Internal(children=right_ch, counts=right_cn, total=right_total),
    ) => {
      for i in 0..<right_ch.length() {
        left_ch.push(right_ch[i])
        left_cn.push(right_cn[i])
      }
      let merged = Internal(
        children=left_ch,
        counts=left_cn,
        total=left_total + right_total,
      )
      children[idx] = merged
      counts[idx] = merged.total()
      let _ = children.remove(idx + 1)
      let _ = counts.remove(idx + 1)
    }
    _ => abort("merge_children: expected internal nodes")
  }
}

///|
fn[T] BTreeNode::needs_rebalance(self : BTreeNode[T], min_degree : Int) -> Bool {
  match self {
    Leaf(..) => false
    Internal(children~, ..) => children.length() <= min_degree
  }
}

///|
fn[T] BTreeNode::can_lend(self : BTreeNode[T], min_degree : Int) -> Bool {
  match self {
    Leaf(..) => false
    Internal(children~, ..) => children.length() > min_degree
  }
}

///|
fn[T] ensure_min_children(
  children : Array[BTreeNode[T]],
  counts : Array[Int],
  idx : Int,
  min_degree : Int,
) -> Unit {
  if !children[idx].needs_rebalance(min_degree) {
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
  } else {
    merge_children(children, counts, idx)
  }
}

///|
/// Pre-delete hook: ensure the child we're about to descend into has
/// > min_degree children, so a subsequent delete won't underflow.
/// Tries borrow first (cheaper), falls back to merge.
pub fn[T] prepare_ensure_min(
  children : Array[BTreeNode[T]],
  counts : Array[Int],
  idx : Int,
  min_degree : Int,
) -> Unit {
  ensure_min_children(children, counts, idx, min_degree)
}

///|
/// Pre-insert hook: proactively split full children before descending,
/// so the insert never needs to backtrack. This is the top-down
/// B-tree insert strategy (vs bottom-up split-and-propagate).
pub fn[T] prepare_split(
  children : Array[BTreeNode[T]],
  counts : Array[Int],
  idx : Int,
  min_degree : Int,
) -> Unit {
  if !children[idx].is_full(min_degree) {
    return
  }
  match children[idx] {
    Internal(children=child_children, counts=child_counts, ..) => {
      let (left, right) = split_internal(child_children, child_counts)
      children[idx] = left
      counts[idx] = left.total()
      children.insert(idx + 1, right)
      counts.insert(idx + 1, right.total())
    }
    Leaf(..) => ()
  }
}

///|
/// Core descent: navigate from root to leaf at span position `pos`.
///
/// At each internal node, find_slot_fn is called TWICE:
/// 1. Before prepare — to identify which child to prepare
/// 2. After prepare — because prepare (split/merge) may change indices
/// This two-pass approach is why the first result's offset is discarded.
pub fn[T] descend(
  node : BTreeNode[T],
  pos : Int,
  min_degree : Int,
  prepare : (Array[BTreeNode[T]], Array[Int], Int, Int) -> Unit,
  find_slot_fn : (Array[Int], Int, Int) -> (Int, Int),
  allow_leaf_end : Bool,
) -> Cursor[T]? {
  let path : Array[PathFrame[T]] = []
  fn step(current : BTreeNode[T], current_pos : Int) -> Cursor[T]? {
    match current {
      Leaf(elem~, span~) =>
        if current_pos >= 0 &&
          (current_pos < span || (allow_leaf_end && current_pos == span)) {
          let child_idx = if path.length() == 0 {
            0
          } else {
            path[path.length() - 1].child_idx
          }
          return Some({
            path,
            leaf_elem: elem,
            leaf_span: span,
            offset: current_pos,
            child_idx,
          })
        } else {
          None
        }
      Internal(children~, counts~, total~) => {
        // First pass: find slot to prepare (may be invalidated by prepare)
        let (pre_idx, _) = find_slot_fn(counts, current_pos, total)
        prepare(children, counts, pre_idx, min_degree)
        // Second pass: find correct slot after prepare may have split/merged
        let updated_total = counts.sum()
        let (child_idx, remaining) = find_slot_fn(
          counts, current_pos, updated_total,
        )
        path.push({ children, counts, child_idx })
        step(children[child_idx], remaining)
      }
    }
  }
  step(node, pos)
}

///|
pub fn[T] copy_path(
  path : Array[PathFrame[T]],
  keep : Int,
) -> Array[PathFrame[T]] {
  let copied : Array[PathFrame[T]] = Array::new(capacity=keep)
  for i in 0..<keep {
    copied.push(path[i])
  }
  copied
}

///|
pub fn[T] descend_leftmost(
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
        { path, leaf_elem: elem, leaf_span: span, offset: 0, child_idx }
      }
      Internal(children~, counts~, ..) => {
        path.push({ children, counts, child_idx: 0 })
        step(children[0])
      }
    }
  }
  step(node)
}

///|
pub fn[T] cursor_next_leaf(cursor : Cursor[T]) -> Cursor[T]? {
  for depth in (cursor.path.length() - 1)>=..0 {
    let frame = cursor.path[depth]
    let next_idx = frame.child_idx + 1
    if next_idx < frame.children.length() {
      let prefix = copy_path(cursor.path, depth)
      prefix.push({
        children: frame.children,
        counts: frame.counts,
        child_idx: next_idx,
      })
      return Some(descend_leftmost(frame.children[next_idx], prefix))
    }
  }
  None
}

///|
pub fn[T] descend_leaf_at(
  node : BTreeNode[T],
  pos : Int,
  min_degree : Int,
) -> LeafCursor[T]? {
  match descend(node, pos, min_degree, prepare_noop, find_slot, false) {
    None => None
    Some(cursor) => Some(LeafCursor::from_cursor(cursor))
  }
}

///|
pub fn[T] descend_leaf_at_end_boundary(
  node : BTreeNode[T],
  end_ : Int,
  min_degree : Int,
) -> LeafCursor[T]? {
  if end_ == 0 {
    return None
  }
  match
    descend(node, end_, min_degree, prepare_noop, find_slot_inclusive, true) {
    None => None
    Some(cursor) => Some(LeafCursor::from_cursor(cursor))
  }
}

///|
pub fn[T : BTreeElem] BTreeNode::each_slice_in_range(
  self : BTreeNode[T],
  start : Int,
  end_ : Int,
  f : (T) -> Unit,
) -> Unit {
  if start >= end_ {
    return
  }
  let mut pos = start
  let mut cursor = descend(self, start, 0, prepare_noop, find_slot, false)
  while pos < end_ {
    match cursor {
      None => break
      Some(cur) => {
        let slice_start = cur.offset
        let available = cur.leaf_span - slice_start
        let remaining = end_ - pos
        let take = if available > remaining { remaining } else { available }
        let slice_end = slice_start + take
        if slice_start == 0 && slice_end == cur.leaf_span {
          f(cur.leaf_elem)
        } else {
          f(must_slice(cur.leaf_elem, start=slice_start, end=slice_end))
        }
        pos = pos + take
        cursor = cursor_next_leaf(cur)
      }
    }
  }
}
