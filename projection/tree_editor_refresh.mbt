// Interactive Tree Editor: Refresh/reuse logic and tree indexes

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
  if not(TreeNode::same_kind(proj_node.kind, prev_node.kind)) {
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
        if NodeId(child.node_id) != prev_children[i].id {
          return false
        }
        if not(can_skip_subtree(child, prev_children[i], source_map, ui_state)) {
          return false
        }
      }
      true
    }
    Elided(prev_count) =>
      // Must still be collapsed AND descendant count unchanged.
      // Without the count check, edits inside a collapsed subtree
      // (e.g., adding/removing a let-def) would reuse a stale Elided(n).
      if not(collapsed) {
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
  let node_id = NodeId(node.node_id)
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
            not(child_result.reused_previous) {
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
/// Collect a contiguous preorder slice from the structural index.
fn collect_preorder_slice(
  preorder_ids : Array[NodeId],
  start_idx : Int,
  end_idx : Int,
) -> Array[NodeId] {
  let result : Array[NodeId] = []
  for i = start_idx; i <= end_idx; i = i + 1 {
    result.push(preorder_ids[i])
  }
  result
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
fn[T] replace_loaded_subtree_node(
  node : InteractiveTreeNode[T],
  target_id : NodeId,
  replacement : InteractiveTreeNode[T],
) -> (InteractiveTreeNode[T], Bool, Array[InteractiveTreeNode[T]]) {
  if node.id == target_id {
    (replacement, true, [replacement])
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
            let (updated_child, child_found, changed_nodes) = replace_loaded_subtree_node(
              child, target_id, replacement,
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
/// Recursively update a node's collapsed state and return the changed path.
fn[T] update_node_collapsed(
  node : InteractiveTreeNode[T],
  target_id : NodeId,
  collapsed : Bool,
) -> (InteractiveTreeNode[T], Bool, Array[InteractiveTreeNode[T]]) {
  if node.id == target_id {
    let updated = { ..node, collapsed, }
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
            let (updated_child, child_found, changed_nodes) = update_node_collapsed(
              child, target_id, collapsed,
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
/// Patch only the changed node path into the loaded-node index.
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
      if new_selected == node.selected && not(any_child_changed) {
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
      let editing_node = match self.editing_node {
        Some(id) =>
          if new_loaded_nodes.get(id) is Some(_) {
            Some(id)
          } else {
            None
          }
        None => None
      }
      let edit_value = if editing_node is None && self.editing_node is Some(_) {
        ""
      } else {
        self.edit_value
      }
      let dragging = match self.dragging {
        Some(id) =>
          if new_loaded_nodes.get(id) is Some(_) {
            Some(id)
          } else {
            None
          }
        None => None
      }
      let drop_target = match self.drop_target {
        Some(id) =>
          if new_loaded_nodes.get(id) is Some(_) {
            Some(id)
          } else {
            None
          }
        None => None
      }
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
          match get_node_in_tree(proj, node_id) {
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
