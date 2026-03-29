// Zipper ↔ NodeId bridge.
// Connects structural Zipper positions to the NodeId-based identity
// used by SourceMap and the tree-edit layer.

///|
using @loomcore {type Range}

///|
/// Extract child indices from a Zipper path (root-to-focus order).
/// Thin alias over `to_path_indices` — provided for bridge callers who
/// don't want to import the full zipper API.
pub fn zipper_to_trail(z : Zipper) -> Array[Int] {
  to_path_indices(z)
}

///|
/// Walk a ProjNode tree by following a sequence of child indices.
/// Returns the node reached at `trail[depth]`, or None if any step is
/// out of range.
pub fn walk_proj(
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
  let trail = zipper_to_trail(z)
  walk_proj(proj_root, trail, 0)
}

///|
/// DFS walk — find the sequence of child indices that leads from `root`
/// to the node with `target` NodeId.  Returns None when not found.
pub fn path_indices_to_node(
  root : @core.ProjNode[@ast.Term],
  target : @core.NodeId,
) -> Array[Int]? {
  if root.id() == target {
    return Some([])
  }
  for i = 0; i < root.children.length(); i = i + 1 {
    match path_indices_to_node(root.children[i], target) {
      Some(suffix) => {
        let path : Array[Int] = [i]
        path.append(suffix)
        return Some(path)
      }
      None => continue
    }
  }
  None
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

///|
/// Return the NodeId of the innermost AST node covering `offset`.
/// Thin wrapper around `SourceMap::innermost_node_at`.
pub fn node_id_at_offset(
  source_map : @core.SourceMap,
  offset : Int,
) -> @core.NodeId? {
  source_map.innermost_node_at(offset)
}

///|
/// Return the text range recorded for `node_id`.
/// Thin wrapper around `SourceMap::get_range`.
pub fn text_range_from_node_id(
  source_map : @core.SourceMap,
  node_id : @core.NodeId,
) -> Range? {
  source_map.get_range(node_id)
}
