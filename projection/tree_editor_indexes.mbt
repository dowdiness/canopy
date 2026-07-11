// Interactive Tree Editor: parent-map / preorder index builders and queries

///|
/// Build parent map by walking the InteractiveTreeNode tree.
fn[T] build_parent_map_from_tree(
  tree : InteractiveTreeNode[T]?,
) -> Map[NodeId, NodeId] {
  let map : Map[NodeId, NodeId] = {}
  match tree {
    Some(root) => build_parent_map_walk(root, map)
    None => ()
  }
  map
}

///|
fn[T] build_parent_map_walk(
  node : InteractiveTreeNode[T],
  map : Map[NodeId, NodeId],
) -> Unit {
  match node.children {
    Loaded(children) =>
      for child in children {
        map[child.id] = node.id
        build_parent_map_walk(child, map)
      }
    Elided(_) => ()
  }
}

///|
/// Build preorder index by walking the InteractiveTreeNode tree.
fn[T] build_preorder_from_tree(tree : InteractiveTreeNode[T]?) -> LazyPreorder {
  let ids : Array[NodeId] = []
  let range_by_root : Map[NodeId, (Int, Int)] = {}
  match tree {
    Some(root) => build_preorder_walk(root, ids, range_by_root)
    None => ()
  }
  { ids, range_by_root }
}

///|
fn[T] build_preorder_walk(
  node : InteractiveTreeNode[T],
  ids : Array[NodeId],
  range_by_root : Map[NodeId, (Int, Int)],
) -> Unit {
  let start = ids.length()
  ids.push(node.id)
  match node.children {
    Loaded(children) =>
      for child in children {
        build_preorder_walk(child, ids, range_by_root)
      }
    Elided(_) => ()
  }
  range_by_root[node.id] = (start, ids.length() - 1)
}

///|
/// Collect a contiguous preorder slice from the structural index.
fn collect_preorder_slice(
  preorder_ids : Array[NodeId],
  start_idx : Int,
  end_idx : Int,
) -> Array[NodeId] {
  [
    for i in start_idx..<=end_idx => preorder_ids[i]
  ]
}

///|
/// Collect all node IDs in a subtree rooted at the given node using preorder ranges.
fn[T] collect_subtree_ids(
  state : TreeEditorState[T],
  root_id : NodeId,
) -> Array[NodeId] {
  let preorder = build_preorder_from_tree(state.tree)
  match preorder.range_by_root.get(root_id) {
    Some((start_idx, end_idx)) =>
      collect_preorder_slice(preorder.ids, start_idx, end_idx)
    None => []
  }
}

///|
/// Check whether `node_id` is structurally under `ancestor_id` via parent links.
fn is_descendant_in_parent_links(
  parent_by_child : Map[NodeId, NodeId],
  node_id : NodeId,
  ancestor_id : NodeId,
) -> Bool {
  match parent_by_child.get(node_id) {
    Some(parent_id) =>
      if parent_id == ancestor_id {
        true
      } else {
        is_descendant_in_parent_links(parent_by_child, parent_id, ancestor_id)
      }
    None => false
  }
}

///|
/// Check if a node is a descendant of another node.
/// Short-circuits if either node is not in loaded_nodes (e.g., inside an
/// Elided subtree or missing entirely). Only builds the parent map when
/// both nodes are confirmed loaded.
fn[T] is_descendant_of(
  state : TreeEditorState[T],
  node_id : NodeId,
  ancestor_id : NodeId,
) -> Bool {
  if node_id == ancestor_id {
    return false
  }
  // Both nodes must be loaded (visible in the UI) for ancestry to matter.
  // Elided or missing nodes cannot be valid drag targets/sources.
  if state.loaded_nodes.get(node_id) is None ||
    state.loaded_nodes.get(ancestor_id) is None {
    return false
  }
  let parent_map = build_parent_map_from_tree(state.tree)
  is_descendant_in_parent_links(parent_map, node_id, ancestor_id)
}

///|
/// Collect all node IDs between start and end (inclusive) using preorder indexes.
fn[T] collect_nodes_in_range(
  state : TreeEditorState[T],
  start : NodeId,
  end : NodeId,
) -> Array[NodeId] {
  let preorder = build_preorder_from_tree(state.tree)
  match (preorder.range_by_root.get(start), preorder.range_by_root.get(end)) {
    (Some((start_idx, _)), Some((end_idx, _))) => {
      let min_idx = if start_idx < end_idx { start_idx } else { end_idx }
      let max_idx = if start_idx > end_idx { start_idx } else { end_idx }
      collect_preorder_slice(preorder.ids, min_idx, max_idx)
    }
    _ => []
  }
}
