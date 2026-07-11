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

///|
/// Navigate from `cursor` one step in `direction`, reusing a cached path
/// from a previous navigation to skip the O(n) DFS. Returns the new path
/// (for the next call) and the new focus NodeId.
///
/// At edges (can't go up from root, can't go down from leaf, etc.) both
/// returns are None.
pub fn[T] navigate_proj_cached(
  cursor : NodeId,
  direction : Direction,
  proj_root : ProjNode[T],
  cached_path : Array[Int]?,
) -> (Array[Int]?, NodeId?) {
  let path = match cached_path {
    Some(p) =>
      match walk_path(proj_root, p, p.length()) {
        Some(node) => if node.id() == cursor { p } else { return (None, None) } // stale cache, caller will retry
        None => return (None, None) // stale cache
      }
    None => {
      let found = find_path_to(proj_root, cursor)
      match found {
        Some(p) => p
        None => return (None, None)
      }
    }
  }
  match direction {
    Up => {
      if path.is_empty() {
        return (None, None)
      }
      let parent = walk_path(proj_root, path, path.length() - 1)
      (path_pop(path), parent.map(fn(n) { n.id() }))
    }
    Down => {
      let node = walk_path(proj_root, path, path.length())
      match node {
        Some(n) =>
          if n.children.is_empty() {
            (None, None)
          } else {
            (Some(path_push(path, 0)), Some(n.children[0].id()))
          }
        None => (None, None)
      }
    }
    Left => {
      if path.is_empty() {
        return (None, None)
      }
      let idx = path[path.length() - 1]
      if idx == 0 {
        return (None, None)
      }
      let parent = walk_path(proj_root, path, path.length() - 1)
      (
        path_replace_last(path, idx - 1),
        parent.map(fn(p) { p.children[idx - 1].id() }),
      )
    }
    Right => {
      if path.is_empty() {
        return (None, None)
      }
      let idx = path[path.length() - 1]
      let parent = walk_path(proj_root, path, path.length() - 1)
      match parent {
        Some(p) =>
          if idx + 1 >= p.children.length() {
            (None, None)
          } else {
            (path_replace_last(path, idx + 1), Some(p.children[idx + 1].id()))
          }
        None => (None, None)
      }
    }
  }
}

///|
/// Pop last element — returns new owned array.
fn path_pop(path : Array[Int]) -> Array[Int]? {
  if path.is_empty() {
    return None
  }
  let a : Array[Int] = []
  let n = path.length()
  a.reserve_capacity(n - 1)
  for i in 0..<(n - 1) {
    a.push(path[i])
  }
  Some(a)
}

///|
/// Append an element — returns new owned array.
fn path_push(path : Array[Int], new_idx : Int) -> Array[Int] {
  let a : Array[Int] = []
  let n = path.length()
  a.reserve_capacity(n + 1)
  for i in 0..<n {
    a.push(path[i])
  }
  a.push(new_idx)
  a
}

///|
/// Copy `path` but replace the last element with `new_last`.
fn path_replace_last(path : Array[Int], new_last : Int) -> Array[Int]? {
  if path.is_empty() {
    return None
  }
  let a : Array[Int] = []
  let n = path.length()
  a.reserve_capacity(n)
  for i in 0..<(n - 1) {
    a.push(path[i])
  }
  a.push(new_last)
  Some(a)
}
