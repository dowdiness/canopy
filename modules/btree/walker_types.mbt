// Walker contract:
// - mutation descent copies path arrays before prepare hooks mutate them
// - leaf actions read LeafContext and return pure Splice descriptions
// - propagation rewrites only the unpublished candidate path and handles splits

///|
priv struct PathFrame[T] {
  children : Array[BTreeNode[T]]
  counts : Array[Int32]
  child_idx : Int32
}

///|
/// A cursor pointing at a leaf together with its ancestor path.
priv struct Cursor[T] {
  path : Array[PathFrame[T]]
  leaf_elem : T
  leaf_span : Int32
  offset : Int32
  child_idx : Int32
}

///|
priv struct LeafCursor[T] {
  path : Array[PathFrame[T]]
  elem : T
  span : Int32
  offset : Int32
}

///|
/// LCA interval for range operations. child_height is used by range delete
/// to reconstruct boundary subtrees at the correct level.
priv struct AncestorRange[T] {
  prefix : Array[PathFrame[T]]
  children : Array[BTreeNode[T]]
  counts : Array[Int32]
  start_idx : Int32
  end_idx : Int32
  child_height : Int32
}

///|
priv struct NodeSplice[T] {
  prefix : Array[PathFrame[T]]
  children : Array[BTreeNode[T]]
  counts : Array[Int32]
  start_idx : Int32
  end_idx : Int32
  new_children : Array[BTreeNode[T]]
  leaf_delta : Int32
}

///|
/// Value snapshot passed to a leaf splice callback. It captures the current
/// leaf and optional adjacent values from the same immediate parent without
/// exposing a live tree collection. These values are not guaranteed logical
/// neighbors across parent boundaries. See the README's API Contracts section.
#derive(Debug)
pub(all) struct LeafContext[T] {
  /// Current leaf value.
  elem : T
  /// Current leaf span.
  span : Int32
  /// Span offset addressed by the mutation.
  offset : Int32
  /// Current leaf index in its parent child array.
  child_idx : Int32
  priv left_elem : T?
  priv right_elem : T?
}

///|
/// Replacement description for a current leaf parent's child array.
/// `start_idx` and `end_idx` must satisfy
/// `0 <= start_idx <= end_idx <= parent child count`; invalid indices are not
/// separately validated.
#derive(Debug)
pub(all) struct Splice[T] {
  /// Inclusive child index where replacement begins.
  start_idx : Int32
  /// Exclusive child index where replacement ends.
  end_idx : Int32
  /// Replacement leaves, inserted in order. Every span must be positive.
  new_leaves : Array[(T, Int32)]
}

///|
priv struct PropagateResult[T] {
  segment : Array[BTreeNode[T]]
  leaf_delta : Int32
}

///|
/// Return the left sibling leaf value captured from the immediate parent, if
/// present. This is not a cross-parent logical predecessor lookup.
pub fn[T] LeafContext::left_neighbor(self : LeafContext[T]) -> T? {
  self.left_elem
}

///|
/// Return the right sibling leaf value captured from the immediate parent, if
/// present. This is not a cross-parent logical successor lookup.
pub fn[T] LeafContext::right_neighbor(self : LeafContext[T]) -> T? {
  self.right_elem
}

///|
fn[T] LeafContext::from_cursor(cursor : Cursor[T]) -> LeafContext[T] {
  guard cursor.path.length() > 0 else {
    abort("LeafContext::from_cursor: cursor missing parent frame")
  }
  let frame = cursor.path[cursor.path.length() - 1]
  let left_elem : T? = match frame.children.get(cursor.child_idx - 1) {
    Some(Leaf(elem~, ..)) => Some(elem)
    _ => None
  }
  let right_elem : T? = match frame.children.get(cursor.child_idx + 1) {
    Some(Leaf(elem~, ..)) => Some(elem)
    _ => None
  }
  {
    elem: cursor.leaf_elem,
    span: cursor.leaf_span,
    offset: cursor.offset,
    child_idx: cursor.child_idx,
    left_elem,
    right_elem,
  }
}

///|
fn[T] LeafCursor::from_cursor(cursor : Cursor[T]) -> LeafCursor[T] {
  {
    path: cursor.path,
    elem: cursor.leaf_elem,
    span: cursor.leaf_span,
    offset: cursor.offset,
  }
}

///|
pub extend LeafContext with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend Splice with @moonbitlang/core/debug.Debug::{to_repr}
