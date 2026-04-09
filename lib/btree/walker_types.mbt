// Walker contract:
// - descent owns navigation and may mutate internal nodes via prepare hooks
// - leaf actions read LeafContext and return pure Splice descriptions
// - propagation is the only phase that rewrites ancestors and handles splits

///|
pub(all) struct PathFrame[T] {
  children : Array[BTreeNode[T]]
  counts : Array[Int]
  child_idx : Int
} derive(Debug)

///|
/// A cursor pointing at a leaf together with its ancestor path.
pub(all) struct Cursor[T] {
  path : Array[PathFrame[T]]
  leaf_elem : T
  leaf_span : Int
  offset : Int
  child_idx : Int
} derive(Debug)

///|
pub(all) struct LeafCursor[T] {
  path : Array[PathFrame[T]]
  elem : T
  span : Int
  offset : Int
} derive(Debug)

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
pub(all) struct NodeSplice[T] {
  prefix : Array[PathFrame[T]]
  children : Array[BTreeNode[T]]
  counts : Array[Int]
  start_idx : Int
  end_idx : Int
  new_children : Array[BTreeNode[T]]
  original_child_count : Int
  leaf_delta : Int
}

///|
/// Read-only context passed to pure leaf splice computations.
pub(all) struct LeafContext[T] {
  elem : T
  span : Int
  offset : Int
  children : Array[BTreeNode[T]]
  child_idx : Int
} derive(Debug)

///|
pub(all) struct Splice[T] {
  start_idx : Int
  end_idx : Int
  new_leaves : Array[(T, Int)]
} derive(Debug)

///|
pub(all) struct PropagateResult[T] {
  node : BTreeNode[T]
  overflow : BTreeNode[T]?
  leaf_delta : Int
}

///|
pub fn[T] LeafContext::left_neighbor(self : LeafContext[T]) -> T? {
  guard self.child_idx > 0 else { return None }
  match self.children[self.child_idx - 1] {
    Leaf(elem~, ..) => Some(elem)
    _ => None
  }
}

///|
pub fn[T] LeafContext::right_neighbor(self : LeafContext[T]) -> T? {
  guard self.child_idx + 1 < self.children.length() else { return None }
  match self.children[self.child_idx + 1] {
    Leaf(elem~, ..) => Some(elem)
    _ => None
  }
}

///|
pub fn[T] LeafContext::from_cursor(cursor : Cursor[T]) -> LeafContext[T] {
  guard cursor.path.length() > 0 else {
    abort("LeafContext::from_cursor: cursor missing parent frame")
  }
  let frame = cursor.path[cursor.path.length() - 1]
  {
    elem: cursor.leaf_elem,
    span: cursor.leaf_span,
    offset: cursor.offset,
    children: frame.children,
    child_idx: cursor.child_idx,
  }
}

///|
pub fn[T] LeafCursor::from_cursor(cursor : Cursor[T]) -> LeafCursor[T] {
  {
    path: cursor.path,
    elem: cursor.leaf_elem,
    span: cursor.leaf_span,
    offset: cursor.offset,
  }
}
