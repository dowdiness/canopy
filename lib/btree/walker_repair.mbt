// Chain repair for underfull boundary subtrees.
//
// After rebuild_boundary_chain_optional constructs a boundary subtree,
// the boundary child at each level may be underfull. These underfull nodes
// form a chain (single path). This module repairs the chain bottom-up
// using borrow/merge, reusing existing B-tree rebalancing primitives.

///|
/// Shallow-copy an Internal node's children/counts arrays.
/// Prevents borrow/merge from mutating original tree nodes via shared refs.
fn[T] BTreeNode::shallow_copy(self : BTreeNode[T]) -> BTreeNode[T] {
  match self {
    Leaf(..) => self
    Internal(children~, counts~, total~) =>
      Internal(children=children.copy(), counts=counts.copy(), total~)
  }
}

///|
/// How to find the boundary child at each level during chain repair.
priv enum BoundaryKind {
  /// Boundary child is rightmost (keep_left=true: left boundary subtree)
  Left
  /// Boundary child is leftmost (keep_left=false: right boundary subtree)
  Right
  /// Per-level indices from merged boundary interleaving
  Explicit(Array[Int])
}

///|
/// Repair underfull nodes along the boundary chain of a subtree.
/// Walks bottom-up: at each level, if the boundary child is underfull,
/// borrow from or merge with an adjacent sibling.
fn[T] repair_at_boundary(
  node : BTreeNode[T],
  kind : BoundaryKind,
  depth : Int,
  min_degree : Int,
) -> BTreeNode[T] {
  match node {
    Leaf(..) => node
    Internal(children~, counts~, ..) => {
      match kind {
        Explicit(indices) =>
          if depth >= indices.length() || children.length() == 0 {
            return node
          }
        _ => if children.length() == 0 { return node }
      }
      // Copy parent arrays so splice mutations don't alias the original tree.
      let children = children.copy()
      let counts = counts.copy()
      let boundary_idx = match kind {
        Left => children.length() - 1
        Right => 0
        Explicit(indices) => {
          let idx = indices[depth]
          // Defensive clamp — shouldn't trigger since merges happen inside
          // the boundary child, not at its parent's level.
          if idx >= children.length() { children.length() - 1 } else { idx }
        }
      }
      // Shallow-copy only the adjacent siblings that borrow/merge might touch.
      // The boundary child itself will be replaced by the recursive result.
      if boundary_idx > 0 {
        children[boundary_idx - 1] = children[boundary_idx - 1].shallow_copy()
      }
      if boundary_idx + 1 < children.length() {
        children[boundary_idx + 1] = children[boundary_idx + 1].shallow_copy()
      }
      let repaired_child = repair_at_boundary(
        children[boundary_idx],
        kind,
        depth + 1,
        min_degree,
      )
      children[boundary_idx] = repaired_child
      counts[boundary_idx] = repaired_child.total()
      // Loop: ensure_min_after_splice borrows ONE child per call.
      // For min_degree > 2, a heavily underfull boundary child needs
      // multiple borrows (or eventually a merge) to reach min_degree.
      while boundary_idx < children.length() &&
        children[boundary_idx].is_underfull(min_degree) &&
        children.length() > 1 {
        ensure_min_after_splice(children, counts, boundary_idx, min_degree)
      }
      Internal(children~, counts~, total=counts.sum())
    }
  }
}
