// Walker contract:
// - descent owns navigation and may mutate internal nodes via prepare hooks
// - leaf actions read LeafContext and return pure Splice descriptions
// - propagation is the only phase that rewrites ancestors and handles splits

///|
priv struct PathFrame[T] {
  children : Array[BTreeNode[T]]
  counts : Array[Int]
  child_idx : Int
}

///|
/// A cursor pointing at a leaf together with its ancestor path.
priv struct Cursor[T] {
  path : Array[PathFrame[T]]
  leaf_elem : T
  leaf_span : Int
  offset : Int
  child_idx : Int
}

///|
priv struct LeafCursor[T] {
  path : Array[PathFrame[T]]
  elem : T
  span : Int
  offset : Int
}

///|
/// LCA interval for range operations. child_height is used by range delete
/// to reconstruct boundary subtrees at the correct level.
priv struct AncestorRange[T] {
  prefix : Array[PathFrame[T]]
  children : Array[BTreeNode[T]]
  counts : Array[Int]
  start_idx : Int
  end_idx : Int
  child_height : Int
}

///|
priv struct NodeSplice[T] {
  prefix : Array[PathFrame[T]]
  children : Array[BTreeNode[T]]
  counts : Array[Int]
  start_idx : Int
  end_idx : Int
  new_children : Array[BTreeNode[T]]
  leaf_delta : Int
}

///|
/// Read-only context passed to pure leaf splice computations.
pub(all) struct LeafContext[T] {
  elem : T
  span : Int
  offset : Int
  child_idx : Int
  priv left_elem : T?
  priv right_elem : T?
} derive(Debug)

///|
pub(all) struct Splice[T] {
  start_idx : Int
  end_idx : Int
  new_leaves : Array[(T, Int)]
} derive(Debug)

///|
priv struct PropagateResult[T] {
  node : BTreeNode[T]
  overflow : BTreeNode[T]?
  leaf_delta : Int
}

///|
pub fn[T] LeafContext::left_neighbor(self : LeafContext[T]) -> T? {
  self.left_elem
}

///|
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
