// Interactive Tree Editor: local structural edit operations

///|
/// Update the collapsed state of a node in the tree
fn[T] update_collapsed_state(
  tree : InteractiveTreeNode[T]?,
  node_id : NodeId,
  collapsed : Bool,
) -> (InteractiveTreeNode[T]?, Array[InteractiveTreeNode[T]]) {
  match tree {
    None => (None, [])
    Some(node) => {
      let (updated, _, changed_nodes) = update_node_collapsed(
        node, node_id, collapsed,
      )
      (Some(updated), changed_nodes)
    }
  }
}

///|
/// Replace a loaded subtree with a freshly hydrated subtree and return the changed path.
fn[T] replace_loaded_subtree(
  tree : InteractiveTreeNode[T]?,
  node_id : NodeId,
  replacement : InteractiveTreeNode[T],
) -> (InteractiveTreeNode[T]?, Array[InteractiveTreeNode[T]]) {
  match tree {
    None => (None, [])
    Some(node) => {
      let (updated, _, changed_nodes) = replace_loaded_subtree_node(
        node, node_id, replacement,
      )
      (Some(updated), changed_nodes)
    }
  }
}

///|
/// Find `target_id` in a loaded InteractiveTreeNode subtree and apply `f`
/// to the matching node. Returns the updated root, whether the target was
/// found, and the changed ancestor path (root-to-target, inclusive).
/// Short-circuits on first match. `Elided` subtrees are treated as opaque.
fn[T] modify_node_at(
  node : InteractiveTreeNode[T],
  target_id : NodeId,
  f : (InteractiveTreeNode[T]) -> InteractiveTreeNode[T],
) -> (InteractiveTreeNode[T], Bool, Array[InteractiveTreeNode[T]]) {
  if node.id == target_id {
    let updated = f(node)
    (updated, true, [updated])
  } else {
    match node.children {
      Loaded(existing_children) => {
        let children : Array[InteractiveTreeNode[T]] = []
        let child_path : Array[InteractiveTreeNode[T]] = []
        let mut found = false
        for child in existing_children {
          if found {
            children.push(child)
          } else {
            let (updated_child, child_found, changed_nodes) = modify_node_at(
              child, target_id, f,
            )
            children.push(updated_child)
            if child_found {
              found = true
              for changed in changed_nodes {
                child_path.push(changed)
              }
            }
          }
        }
        if found {
          let updated = { ..node, children: Loaded(children) }
          let changed_path : Array[InteractiveTreeNode[T]] = [updated]
          for changed in child_path {
            changed_path.push(changed)
          }
          (updated, true, changed_path)
        } else {
          (node, false, [])
        }
      }
      Elided(_) => (node, false, [])
    }
  }
}

///|
fn[T] replace_loaded_subtree_node(
  node : InteractiveTreeNode[T],
  target_id : NodeId,
  replacement : InteractiveTreeNode[T],
) -> (InteractiveTreeNode[T], Bool, Array[InteractiveTreeNode[T]]) {
  modify_node_at(node, target_id, _ => replacement)
}

///|
fn[T] update_node_collapsed(
  node : InteractiveTreeNode[T],
  target_id : NodeId,
  collapsed : Bool,
) -> (InteractiveTreeNode[T], Bool, Array[InteractiveTreeNode[T]]) {
  modify_node_at(node, target_id, n => { ..n, collapsed })
}
///|
fn[T] update_loaded_nodes_for_path(
  loaded_nodes : Map[NodeId, InteractiveTreeNode[T]],
  changed_nodes : Array[InteractiveTreeNode[T]],
) -> Map[NodeId, InteractiveTreeNode[T]] {
  let updated = loaded_nodes.copy()
  for node in changed_nodes {
    updated[node.id] = node
  }
  updated
}

///|
/// Replace the materialized node index for one subtree and patch changed ancestors.
fn[T] replace_loaded_nodes_for_subtree(
  loaded_nodes : Map[NodeId, InteractiveTreeNode[T]],
  subtree_ids : Array[NodeId],
  replacement_nodes : Map[NodeId, InteractiveTreeNode[T]],
  changed_nodes : Array[InteractiveTreeNode[T]],
) -> Map[NodeId, InteractiveTreeNode[T]] {
  let updated = loaded_nodes.copy()
  for node_id in subtree_ids {
    updated.remove(node_id)
  }
  for node_id, node in replacement_nodes {
    updated[node_id] = node
  }
  for node in changed_nodes {
    updated[node.id] = node
  }
  updated
}

///|
/// Apply selection state locally to the loaded interactive tree.
fn[T] apply_selection_edit(
  state : TreeEditorState[T],
  selection : Array[NodeId],
) -> TreeEditorState[T] {
  let selection_set = @immut/hashset.from_iter(selection.iter())
  match state.tree {
    None => { ..state, selection, }
    Some(root) => {
      let (updated, changed, changed_nodes) = apply_selection_to_node(
        root, selection_set,
      )
      if changed {
        let loaded_nodes = update_loaded_nodes_for_path(
          state.loaded_nodes,
          changed_nodes,
        )
        { ..state, selection, tree: Some(updated), loaded_nodes }
      } else {
        { ..state, selection, }
      }
    }
  }
}

///|
fn[T] apply_selection_to_node(
  node : InteractiveTreeNode[T],
  selection : @immut/hashset.HashSet[NodeId],
) -> (InteractiveTreeNode[T], Bool, Array[InteractiveTreeNode[T]]) {
  let new_selected = selection.contains(node.id)
  match node.children {
    Loaded(existing_children) => {
      let updated_children : Array[InteractiveTreeNode[T]] = []
      let child_path : Array[InteractiveTreeNode[T]] = []
      let mut any_child_changed = false
      for child in existing_children {
        let (updated, changed, changed_nodes) = apply_selection_to_node(
          child, selection,
        )
        updated_children.push(updated)
        if changed {
          any_child_changed = true
          for cn in changed_nodes {
            child_path.push(cn)
          }
        }
      }
      if new_selected == node.selected && !any_child_changed {
        (node, false, [])
      } else {
        let children = if any_child_changed {
          Loaded(updated_children)
        } else {
          node.children
        }
        let updated = { ..node, selected: new_selected, children }
        let changed_path : Array[InteractiveTreeNode[T]] = [updated]
        for cn in child_path {
          changed_path.push(cn)
        }
        (updated, true, changed_path)
      }
    }
    Elided(_) =>
      if new_selected == node.selected {
        (node, false, [])
      } else {
        let updated = { ..node, selected: new_selected }
        (updated, true, [updated])
      }
  }
}
