// Interactive Tree Editor: Refresh/reuse logic and tree indexes

///|
/// Check if a subtree can be completely skipped during refresh.
fn[T : TreeNode + Renderable] can_skip_subtree(
  proj_node : ProjNode[T],
  prev_node : InteractiveTreeNode[T],
  source_map : SourceMap,
  ui_state : TreeUIState,
) -> Bool {
  let node_id = prev_node.id
  // Check text_range — positions shift when text is inserted/deleted before this node
  let text_range = match source_map.get_range(node_id) {
    Some(range) => range
    None => Range::new(proj_node.start, proj_node.end)
  }
  if text_range != prev_node.text_range {
    return false
  }
  // Check UI state matches
  let collapsed = ui_state.collapsed_nodes.contains(node_id)
  if collapsed != prev_node.collapsed {
    return false
  }
  let selected = ui_state.selection.contains(node_id)
  if selected != prev_node.selected {
    return false
  }
  let editing = match ui_state.editing_node {
    Some(id) => id == node_id
    None => false
  }
  if editing != prev_node.editing {
    return false
  }
  let drop_target = match ui_state.drop_target {
    Some(id) => id == node_id
    None => false
  }
  if drop_target != prev_node.drop_target {
    return false
  }
  // Check kind matches — use same_kind + label instead of full T equality
  // to avoid deep subtree comparison on complex AST types
  if !TreeNode::same_kind(proj_node.kind, prev_node.kind) {
    return false
  }
  if Renderable::label(proj_node.kind) != prev_node.label {
    return false
  }
  // Check children match recursively. Recursive verification is necessary
  // because reconcile_ast preserves node IDs when kinds match (e.g.,
  // Int(4) → Int(5) keeps the same ID). A shallow ID-only check would
  // miss leaf value changes. The recursive cost is O(subtree) but cheaper
  // than full refresh_node_minimal (no stamp alloc, no new InteractiveTreeNode).
  match prev_node.children {
    Loaded(prev_children) => {
      // If currently collapsed but previously loaded, must rebuild as Elided
      if collapsed {
        return false
      }
      if proj_node.children.length() != prev_children.length() {
        return false
      }
      for i, child in proj_node.children {
        if NodeId::from_int(child.node_id) != prev_children[i].id {
          return false
        }
        if !can_skip_subtree(child, prev_children[i], source_map, ui_state) {
          return false
        }
      }
      true
    }
    Elided(prev_count) =>
      // Must still be collapsed AND descendant count unchanged.
      // Without the count check, edits inside a collapsed subtree
      // (e.g., adding/removing a let-def) would reuse a stale Elided(n).
      if !collapsed {
        false
      } else {
        let mut current_count = 0
        for child in proj_node.children {
          current_count += count_projection_descendants(child)
        }
        current_count == prev_count
      }
  }
}

///|
/// Copy all loaded_nodes entries from a reused subtree.
fn[T] carry_over_loaded_nodes(
  node : InteractiveTreeNode[T],
  target : Map[NodeId, InteractiveTreeNode[T]],
) -> Unit {
  target[node.id] = node
  match node.children {
    Loaded(children) =>
      for child in children {
        carry_over_loaded_nodes(child, target)
      }
    Elided(_) => ()
  }
}

///|
/// Simplified refresh that skips eager index building.
/// Populates `new_loaded_nodes` as it walks but does not build preorder_ids,
/// parent_by_child, or preorder_range_by_root.
fn[T : TreeNode + Renderable] refresh_node_minimal(
  node : ProjNode[T],
  source_map : SourceMap,
  ui_state : TreeUIState,
  previous_nodes : Map[NodeId, InteractiveTreeNode[T]],
  new_loaded_nodes : Map[NodeId, InteractiveTreeNode[T]],
) -> RefreshedInteractiveNode[T] {
  let node_id = NodeId::from_int(node.node_id)
  let text_range = match source_map.get_range(node_id) {
    Some(range) => range
    None => Range::new(node.start, node.end)
  }
  let collapsed = ui_state.collapsed_nodes.contains(node_id)
  let selected = ui_state.selection.contains(node_id)
  let editing = match ui_state.editing_node {
    Some(id) => id == node_id
    None => false
  }
  let drop_target = match ui_state.drop_target {
    Some(id) => id == node_id
    None => false
  }
  let label = Renderable::label(node.kind)
  let previous_node = previous_nodes.get(node_id)
  // Phase 2: subtree skip — check if entire subtree can be reused
  match previous_node {
    Some(previous) =>
      if can_skip_subtree(node, previous, source_map, ui_state) {
        // Carry over all loaded_nodes entries from reused subtree
        carry_over_loaded_nodes(previous, new_loaded_nodes)
        return { node: previous, reused_previous: true }
      }
    None => ()
  }
  if collapsed {
    let mut descendant_count = 0
    for child in node.children {
      descendant_count += count_projection_descendants(child)
    }
    // No stamp comparison needed: can_skip_subtree (called above) already
    // validated all stamp fields for the collapsed case. If we reach here,
    // either the subtree changed or there is no previous node to reuse.
    let refreshed : InteractiveTreeNode[T] = {
      id: node_id,
      kind: node.kind,
      label,
      children: Elided(descendant_count),
      selected,
      editing,
      collapsed,
      drop_target,
      text_range,
    }
    new_loaded_nodes[node_id] = refreshed
    { node: refreshed, reused_previous: false }
  } else {
    let children : Array[InteractiveTreeNode[T]] = []
    let child_ids : Array[NodeId] = []
    let previous_loaded_children = match previous_node {
      Some(previous) =>
        match previous.children {
          Loaded(previous_children) => Some(previous_children)
          Elided(_) => None
        }
      None => None
    }
    let mut children_reused = previous_loaded_children is Some(_)
    for child_index, child in node.children {
      let child_result = refresh_node_minimal(
        child, source_map, ui_state, previous_nodes, new_loaded_nodes,
      )
      child_ids.push(child_result.node.id)
      children.push(child_result.node)
      match previous_loaded_children {
        Some(previous_children) =>
          if child_index >= previous_children.length() ||
            previous_children[child_index].id != child_result.node.id ||
            !child_result.reused_previous {
            children_reused = false
          }
        None => ()
      }
    }
    match previous_loaded_children {
      Some(previous_children) =>
        if previous_children.length() != children.length() {
          children_reused = false
        }
      None => ()
    }
    let stamp : InteractiveNodeStamp = {
      id: node_id,
      kind_tag: Renderable::kind_tag(node.kind),
      label,
      child_ids,
      elided_descendant_count: None,
      selected,
      editing,
      collapsed,
      drop_target,
      text_range,
    }
    match previous_node {
      Some(previous) =>
        if children_reused && interactive_node_stamp(previous) == stamp {
          new_loaded_nodes[node_id] = previous
          { node: previous, reused_previous: true }
        } else {
          let refreshed : InteractiveTreeNode[T] = {
            id: node_id,
            kind: node.kind,
            label,
            children: Loaded(children),
            selected,
            editing,
            collapsed,
            drop_target,
            text_range,
          }
          new_loaded_nodes[node_id] = refreshed
          { node: refreshed, reused_previous: false }
        }
      None => {
        let refreshed : InteractiveTreeNode[T] = {
          id: node_id,
          kind: node.kind,
          label,
          children: Loaded(children),
          selected,
          editing,
          collapsed,
          drop_target,
          text_range,
        }
        new_loaded_nodes[node_id] = refreshed
        { node: refreshed, reused_previous: false }
      }
    }
  }
}

///|
/// Refresh tree from projection while preserving UI state (collapsed nodes).
/// Also prunes stale IDs from UI state that no longer exist in the tree.
/// Uses `refresh_node_minimal` — no eager structural indexes are built.
pub fn[T : TreeNode + Renderable] TreeEditorState::refresh(
  self : TreeEditorState[T],
  proj : ProjNode[T]?,
  source_map : SourceMap,
) -> TreeEditorState[T] {
  match proj {
    Some(ast) => {
      let selection_set = @immut/hashset.from_iter(self.selection.iter())
      let ui_state : TreeUIState = {
        collapsed_nodes: self.collapsed_nodes,
        selection: selection_set,
        editing_node: self.editing_node,
        drop_target: self.drop_target,
      }
      let new_loaded_nodes : Map[NodeId, InteractiveTreeNode[T]] = {}
      let tree = Some(
        refresh_node_minimal(
          ast,
          source_map,
          ui_state,
          self.loaded_nodes,
          new_loaded_nodes,
        ).node,
      )
      // Prune stale UI state using new_loaded_nodes.
      // collapsed_nodes is NOT pruned — stale entries are harmless.
      let selection = self.selection.filter(fn(id) {
        new_loaded_nodes.get(id) is Some(_)
      })
      let editing_node = self.editing_node.filter(fn(id) {
        new_loaded_nodes.get(id) is Some(_)
      })
      let edit_value = if editing_node is None && self.editing_node is Some(_) {
        ""
      } else {
        self.edit_value
      }
      let dragging = self.dragging.filter(fn(id) {
        new_loaded_nodes.get(id) is Some(_)
      })
      let drop_target = self.drop_target.filter(fn(id) {
        new_loaded_nodes.get(id) is Some(_)
      })
      let drop_position = if drop_target is None {
        None
      } else {
        self.drop_position
      }
      {
        tree,
        selection,
        editing_node,
        edit_value,
        dragging,
        drop_target,
        drop_position,
        collapsed_nodes: self.collapsed_nodes,
        loaded_nodes: new_loaded_nodes,
      }
    }
    None =>
      {
        ..self,
        tree: None,
        selection: [],
        editing_node: None,
        edit_value: "",
        dragging: None,
        drop_target: None,
        drop_position: None,
        loaded_nodes: {},
      }
  }
}

///|
/// Expand a node and hydrate its children from the current projection snapshot
/// when the expanded branch is currently elided.
pub fn[T : TreeNode + Renderable] TreeEditorState::expand_node(
  self : TreeEditorState[T],
  node_id : NodeId,
  proj : ProjNode[T]?,
  source_map : SourceMap,
) -> TreeEditorState[T] {
  match self.loaded_nodes.get(node_id) {
    Some(current_node) =>
      match current_node.children {
        Elided(_) => {
          let hydrated = self.hydrate_subtree(node_id, proj, source_map)
          hydrated.apply_edit(Expand(node_id~))
        }
        Loaded(_) => self.apply_edit(Expand(node_id~))
      }
    None => self
  }
}

///|
/// Rebuild a single materialized subtree from the current projection snapshot.
/// This still does an O(n) `get_node_in_tree(...)` lookup and is intended for
/// one-off expand hydration, not bulk expand-all.
fn[T : TreeNode + Renderable] TreeEditorState::hydrate_subtree(
  self : TreeEditorState[T],
  node_id : NodeId,
  proj : ProjNode[T]?,
  source_map : SourceMap,
) -> TreeEditorState[T] {
  match (self.tree, proj, self.loaded_nodes.get(node_id)) {
    (Some(tree), Some(proj), Some(current_node)) =>
      match current_node.children {
        Loaded(_) => self
        Elided(_) =>
          match @core.get_node_in_tree(proj, node_id) {
            Some(proj_node) => {
              let ui_state : TreeUIState = {
                collapsed_nodes: self.collapsed_nodes.remove(node_id),
                selection: @immut/hashset.from_iter(self.selection.iter()),
                editing_node: self.editing_node,
                drop_target: self.drop_target,
              }
              let subtree_loaded_nodes : Map[NodeId, InteractiveTreeNode[T]] = {}
              let hydrated = refresh_node_minimal(
                proj_node,
                source_map,
                ui_state,
                self.loaded_nodes,
                subtree_loaded_nodes,
              )
              let (updated_tree, changed_nodes) = replace_loaded_subtree(
                Some(tree),
                node_id,
                hydrated.node,
              )
              let loaded_nodes = replace_loaded_nodes_for_subtree(
                self.loaded_nodes,
                collect_subtree_ids(self, node_id),
                subtree_loaded_nodes,
                changed_nodes,
              )
              { ..self, tree: updated_tree, loaded_nodes }
            }
            None => self
          }
      }
    _ => self
  }
}
