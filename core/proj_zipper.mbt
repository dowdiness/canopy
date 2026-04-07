// ProjNode tree navigation via path arithmetic.
// O(n) DFS to find path, O(depth) to compute neighbor — no tree copy.

///|
pub(all) enum Direction {
  Up
  Down
  Left
  Right
} derive(Debug)

///|
/// DFS walk — find the sequence of child indices from root to target NodeId.
/// Returns None when the target is not in the tree.
fn[T] find_path_to(root : ProjNode[T], target : NodeId) -> Array[Int]? {
  let acc : Array[Int] = []
  if find_path_to_inner(root, target, acc) {
    Some(acc)
  } else {
    None
  }
}

///|
fn[T] find_path_to_inner(
  node : ProjNode[T],
  target : NodeId,
  acc : Array[Int],
) -> Bool {
  if node.id() == target {
    return true
  }
  for i in 0..<node.children.length() {
    acc.push(i)
    if find_path_to_inner(node.children[i], target, acc) {
      return true
    }
    let _ = acc.pop()
  }
  false
}

///|
/// Walk proj_root following path[0..limit), returning the node at that depth.
fn[T] walk_path(
  root : ProjNode[T],
  path : Array[Int],
  limit : Int,
) -> ProjNode[T]? {
  let mut node = root
  for i in 0..<limit {
    let idx = path[i]
    if idx >= node.children.length() {
      return None
    }
    node = node.children[idx]
  }
  Some(node)
}

///|
/// Navigate from `cursor` one step in `direction` within a ProjNode tree.
/// Returns the NodeId of the new focus, or None when the move is invalid.
pub fn[T] navigate_proj(
  cursor : NodeId,
  direction : Direction,
  proj_root : ProjNode[T],
) -> NodeId? {
  let path = match find_path_to(proj_root, cursor) {
    Some(p) => p
    None => return None
  }
  match direction {
    Up => {
      if path.is_empty() {
        return None
      }
      let parent = walk_path(proj_root, path, path.length() - 1)
      parent.map(fn(n) { n.id() })
    }
    Down => {
      let node = walk_path(proj_root, path, path.length())
      match node {
        Some(n) =>
          if n.children.is_empty() {
            None
          } else {
            Some(n.children[0].id())
          }
        None => None
      }
    }
    Left => {
      if path.is_empty() {
        return None
      }
      let idx = path[path.length() - 1]
      if idx == 0 {
        return None
      }
      let parent = walk_path(proj_root, path, path.length() - 1)
      parent.map(fn(p) { p.children[idx - 1].id() })
    }
    Right => {
      if path.is_empty() {
        return None
      }
      let idx = path[path.length() - 1]
      let parent = walk_path(proj_root, path, path.length() - 1)
      match parent {
        Some(p) =>
          if idx + 1 >= p.children.length() {
            None
          } else {
            Some(p.children[idx + 1].id())
          }
        None => None
      }
    }
  }
}
