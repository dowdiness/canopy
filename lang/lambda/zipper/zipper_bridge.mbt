// Zipper ↔ NodeId bridge.
// Connects structural Zipper positions to the NodeId-based identity
// used by SourceMap and the tree-edit layer.

///|
/// Walk a ProjNode tree by following a sequence of child indices.
/// Returns the node reached at `trail[depth]`, or None if any step is
/// out of range.
fn walk_proj(
  node : @core.ProjNode[@ast.Term],
  trail : Array[Int],
  depth : Int,
) -> @core.ProjNode[@ast.Term]? {
  if depth >= trail.length() {
    Some(node)
  } else {
    let idx = trail[depth]
    if idx < node.children.length() {
      walk_proj(node.children[idx], trail, depth + 1)
    } else {
      None
    }
  }
}

///|
/// Return the ProjNode at the Zipper's current focus position.
/// Uses the Zipper's own path indices to navigate the ProjNode tree, so
/// the two representations must be derived from the same parse.
pub fn find_proj_node_for_focus(
  z : Zipper,
  proj_root : @core.ProjNode[@ast.Term],
) -> @core.ProjNode[@ast.Term]? {
  let trail = to_path_indices(z)
  walk_proj(proj_root, trail, 0)
}

///|
/// DFS walk — find the sequence of child indices that leads from `root`
/// to the node with `target` NodeId.  Returns None when not found.
pub fn path_indices_to_node(
  root : @core.ProjNode[@ast.Term],
  target : @core.NodeId,
) -> Array[Int]? {
  let acc : Array[Int] = []
  if find_path(root, target, acc) {
    Some(acc)
  } else {
    None
  }
}

///|
fn find_path(
  node : @core.ProjNode[@ast.Term],
  target : @core.NodeId,
  acc : Array[Int],
) -> Bool {
  if node.id() == target {
    return true
  }
  for i in 0..<node.children.length() {
    acc.push(i)
    if find_path(node.children[i], target, acc) {
      return true
    }
    let _ = acc.pop()
  }
  false
}

///|
/// Build a transient Zipper positioned at `node_id` within `term`.
/// `proj_root` is used to find the child-index path to `node_id`; the
/// Zipper itself is constructed from `term` using `focus_at`.
/// Returns None when `node_id` is not present in `proj_root`.
pub fn zipper_from_node_id(
  node_id : @core.NodeId,
  term : @ast.Term,
  proj_root : @core.ProjNode[@ast.Term],
) -> Zipper? {
  match path_indices_to_node(proj_root, node_id) {
    None => None
    Some(trail) => Some(focus_at(term, trail))
  }
}

///|
/// Navigate from `cursor` one step in `direction` and return the NodeId
/// of the new focus.
/// Constructs a transient Zipper, moves it, then looks up the
/// corresponding ProjNode to obtain the fresh NodeId.
/// Returns None when the move or the ProjNode lookup fails.
pub fn navigate(
  cursor : @core.NodeId,
  direction : Direction,
  term : @ast.Term,
  proj_root : @core.ProjNode[@ast.Term],
) -> @core.NodeId? {
  let z = match zipper_from_node_id(cursor, term, proj_root) {
    Some(z) => z
    None => return None
  }
  let moved = match direction {
    Up => go_up(z)
    Down => go_down(z)
    Left => go_left(z)
    Right => go_right(z)
  }
  match moved {
    None => None
    Some(z2) =>
      match find_proj_node_for_focus(z2, proj_root) {
        Some(node) => Some(node.id())
        None => None
      }
  }
}
