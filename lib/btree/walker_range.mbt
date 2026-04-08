///|
pub fn[T] BTreeNode::height(self : BTreeNode[T]) -> Int {
  match self {
    Leaf(..) => 0
    // Empty internal is a transient state during range splicing — treat as 0
    Internal(children~, ..) if children.is_empty() => 0
    Internal(children~, ..) => children[0].height() + 1
  }
}

///|
fn[T] shared_prefix_length(
  left : Array[PathFrame[T]],
  right : Array[PathFrame[T]],
) -> Int {
  let max_shared = if left.length() < right.length() {
    left.length()
  } else {
    right.length()
  }
  let mut i = 0
  while i < max_shared && left[i].child_idx == right[i].child_idx {
    i = i + 1
  }
  i
}

///|
fn[T] lowest_common_ancestor_range(
  start : LeafCursor[T],
  end_ : LeafCursor[T],
) -> AncestorRange[T] {
  guard start.path.length() > 0 && end_.path.length() > 0 else {
    abort("lowest_common_ancestor_range: missing leaf parent")
  }
  let prefix_len = shared_prefix_length(start.path, end_.path)
  if prefix_len == start.path.length() && prefix_len == end_.path.length() {
    let target = start.path[prefix_len - 1]
    let prefix = copy_path(start.path, prefix_len - 1)
    let start_idx = target.child_idx
    return {
      prefix,
      children: target.children,
      counts: target.counts,
      start_idx,
      end_idx: start_idx + 1,
      child_height: if target.children.length() == 0 {
        0
      } else {
        target.children[0].height()
      },
    }
  }
  let target = start.path[prefix_len]
  let prefix = copy_path(start.path, prefix_len)
  let start_idx = start.path[prefix_len].child_idx
  let end_idx = end_.path[prefix_len].child_idx + 1
  {
    prefix,
    children: target.children,
    counts: target.counts,
    start_idx,
    end_idx,
    child_height: if target.children.length() == 0 {
      0
    } else {
      target.children[0].height()
    },
  }
}
