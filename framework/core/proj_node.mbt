// ProjNode[T]: Generic projection node parameterized by AST type T.
// Preserves node IDs and positions needed for projectional editing.

///|
/// Generic projection node parameterized by AST type T.
/// `kind : T` holds the AST node, `children : Array[ProjNode[T]]` holds child projections.
pub struct ProjNode[T] {
  node_id : Int
  kind : T
  children : Array[ProjNode[T]]
  start : Int
  end : Int
} derive(Show, Eq)

///|
pub fn[T] ProjNode::new(
  kind : T,
  start : Int,
  end : Int,
  node_id : Int,
  children : Array[ProjNode[T]],
) -> ProjNode[T] {
  { node_id, kind, children, start, end }
}

///|
pub fn[T] ProjNode::id(self : ProjNode[T]) -> NodeId {
  NodeId(self.node_id)
}

///|
/// Allocate a fresh projection node ID from a shared counter.
/// Public for cross-package use by language-specific projection builders.
pub fn next_proj_node_id(counter : Ref[Int]) -> Int {
  let id = counter.val
  counter.val = counter.val + 1
  id
}

///|
/// Assign fresh IDs to a ProjNode subtree.
/// Public for cross-package use by reconciliation.
pub fn[T] assign_fresh_ids(
  node : ProjNode[T],
  counter : Ref[Int],
) -> ProjNode[T] {
  let new_id = next_proj_node_id(counter)
  let new_children : Array[ProjNode[T]] = []
  for child in node.children {
    new_children.push(assign_fresh_ids(child, counter))
  }
  ProjNode::new(node.kind, node.start, node.end, new_id, new_children)
}
