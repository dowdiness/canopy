// Chain repair for underfull boundary subtrees.
//
// After rebuild_boundary_chain_optional constructs a boundary subtree,
// the boundary child at each level may be underfull. These underfull nodes
// form a chain (single path). This module repairs the chain bottom-up
// using borrow/merge, reusing existing B-tree rebalancing primitives.

///|
/// Repair underfull nodes along the boundary chain of a subtree.
/// `keep_left` determines which child is the boundary child:
///   keep_left=true  → last child at each level (rightmost = rebuilt from below)
///   keep_left=false → first child at each level (leftmost = rebuilt from below)
/// Returns the repaired subtree.
fn[T] repair_boundary_chain(
  node : BTreeNode[T],
  keep_left : Bool,
  min_degree : Int,
) -> BTreeNode[T] {
  match node {
    Leaf(..) => node
    Internal(children~, counts~, ..) => {
      if children.length() == 0 {
        return node
      }
      // Copy arrays to avoid aliasing with original tree nodes.
      // borrow/merge mutate children arrays in place.
      let children = children.copy()
      let counts = counts.copy()
      let boundary_idx = if keep_left {
        children.length() - 1
      } else {
        0
      }
      // Recursively repair the boundary child
      let repaired_child = repair_boundary_chain(
        children[boundary_idx],
        keep_left,
        min_degree,
      )
      children[boundary_idx] = repaired_child
      counts[boundary_idx] = repaired_child.total()
      // Repair this level if the boundary child is underfull
      if repaired_child.is_underfull(min_degree) && children.length() > 1 {
        ensure_min_after_splice(children, counts, boundary_idx, min_degree)
      }
      let new_total = counts.sum()
      Internal(children~, counts~, total=new_total)
    }
  }
}

///|
/// Repair underfull nodes along a merged boundary chain.
/// In a merged boundary, the boundary child position at each level depends
/// on the interleaving of left and right path suffixes. We pass explicit
/// per-level indices.
fn[T] repair_merged_boundary_chain(
  node : BTreeNode[T],
  boundary_indices : Array[Int],
  depth : Int,
  min_degree : Int,
) -> BTreeNode[T] {
  match node {
    Leaf(..) => node
    Internal(children~, counts~, total~) => {
      if depth >= boundary_indices.length() || children.length() == 0 {
        return node
      }
      let boundary_idx = boundary_indices[depth]
      // Clamp index in case merge at a lower level shifted things
      let boundary_idx = if boundary_idx >= children.length() {
        children.length() - 1
      } else {
        boundary_idx
      }
      // Recursively repair the boundary child
      let repaired_child = repair_merged_boundary_chain(
        children[boundary_idx],
        boundary_indices,
        depth + 1,
        min_degree,
      )
      children[boundary_idx] = repaired_child
      counts[boundary_idx] = repaired_child.total()
      // Repair this level if underfull
      if repaired_child.is_underfull(min_degree) && children.length() > 1 {
        ensure_min_after_splice(children, counts, boundary_idx, min_degree)
      }
      let new_total = counts.sum()
      Internal(children~, counts~, total=new_total)
    }
  }
}
