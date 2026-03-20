// Interactive Tree Editor: TreeEditorState and edit operations

///|
/// Editor state for the interactive tree
pub struct TreeEditorState {
  /// The interactive tree representation
  tree : InteractiveTreeNode?
  /// Currently selected nodes
  selection : Array[NodeId]
  /// Node being edited inline
  editing_node : NodeId?
  /// Current edit value for inline editing
  edit_value : String
  /// Node being dragged
  dragging : NodeId?
  /// Current drop target
  drop_target : NodeId?
  /// Drop position relative to target
  drop_position : DropPosition?
  /// Set of collapsed node IDs (UI state separate from model, immutable)
  collapsed_nodes : @immut/hashset.HashSet[NodeId]
  /// Currently materialized interactive nodes by ID
  priv loaded_nodes : Map[NodeId, InteractiveTreeNode]
}

///|
/// Look up a materialized interactive node by ID. O(1) via the loaded-node index.
pub fn TreeEditorState::get_loaded_node(
  self : TreeEditorState,
  node_id : NodeId,
) -> InteractiveTreeNode? {
  self.loaded_nodes.get(node_id)
}

///|
/// Create a new tree editor state
pub fn TreeEditorState::new() -> TreeEditorState {
  {
    tree: None,
    selection: [],
    editing_node: None,
    edit_value: "",
    dragging: None,
    drop_target: None,
    drop_position: None,
    collapsed_nodes: @immut/hashset.new(),
    loaded_nodes: {},
  }
}

///|
/// Create tree editor state from a projection snapshot.
pub fn TreeEditorState::from_projection(
  proj : ProjNode?,
  source_map : SourceMap,
) -> TreeEditorState {
  let collapsed_nodes : @immut/hashset.HashSet[NodeId] = @immut/hashset.new()
  let ui_state : TreeUIState = {
    collapsed_nodes,
    selection: @immut/hashset.new(),
    editing_node: None,
    drop_target: None,
  }
  let loaded_nodes : Map[NodeId, InteractiveTreeNode] = {}
  let tree = match proj {
    Some(ast) =>
      Some(
        refresh_node_minimal(ast, source_map, ui_state, {}, loaded_nodes).node,
      )
    None => None
  }
  {
    tree,
    selection: [],
    editing_node: None,
    edit_value: "",
    dragging: None,
    drop_target: None,
    drop_position: None,
    collapsed_nodes,
    loaded_nodes,
  }
}

///|
/// Refresh tree from projection while preserving UI state (collapsed nodes).
/// Also prunes stale IDs from UI state that no longer exist in the tree.
/// Uses `refresh_node_minimal` — no eager structural indexes are built.
pub fn TreeEditorState::refresh(
  self : TreeEditorState,
  proj : ProjNode?,
  source_map : SourceMap,
) -> TreeEditorState {
  match proj {
    Some(ast) => {
      let selection_set = @immut/hashset.from_iter(self.selection.iter())
      let ui_state : TreeUIState = {
        collapsed_nodes: self.collapsed_nodes,
        selection: selection_set,
        editing_node: self.editing_node,
        drop_target: self.drop_target,
      }
      let new_loaded_nodes : Map[NodeId, InteractiveTreeNode] = {}
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
pub fn TreeEditorState::expand_node(
  self : TreeEditorState,
  node_id : NodeId,
  proj : ProjNode?,
  source_map : SourceMap,
) -> TreeEditorState {
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
fn TreeEditorState::hydrate_subtree(
  self : TreeEditorState,
  node_id : NodeId,
  proj : ProjNode?,
  source_map : SourceMap,
) -> TreeEditorState {
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
              let subtree_loaded_nodes : Map[NodeId, InteractiveTreeNode] = {}
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

///|
/// Apply a tree edit operation to the editor state
pub fn TreeEditorState::apply_edit(
  self : TreeEditorState,
  edit : TreeEditOp,
) -> TreeEditorState {
  match edit {
    Select(node_id~) => apply_selection_edit(self, [node_id])
    SelectRange(start~, end~) => {
      // Collect all nodes between start and end (inclusive) in preorder.
      // If either endpoint is stale (missing), preserve existing selection.
      let new_selection = collect_nodes_in_range(self, start, end)
      if new_selection.is_empty() && not(self.selection.is_empty()) {
        self
      } else {
        apply_selection_edit(self, new_selection)
      }
    }
    StartEdit(node_id~) => {
      // Get current value from loaded nodes
      let edit_value = match self.loaded_nodes.get(node_id) {
        Some(node) => node.label
        None => ""
      }
      { ..self, editing_node: Some(node_id), edit_value }
    }
    CommitEdit(node_id~, new_value~) => {
      let _ = (node_id, new_value)
      { ..self, editing_node: None, edit_value: "" }
    }
    CancelEdit => { ..self, editing_node: None, edit_value: "" }
    Delete(node_id~) => {
      // Collect all node IDs in subtree being deleted
      let subtree_ids = collect_subtree_ids(self, node_id)
      // Remove all subtree nodes from selection
      let selection = self.selection.filter(fn(id) {
        not(subtree_ids.contains(id))
      })
      // Clear editing if editing any node in subtree
      let (editing_node, edit_value) = match self.editing_node {
        Some(edit_id) =>
          if subtree_ids.contains(edit_id) {
            (None, "")
          } else {
            (self.editing_node, self.edit_value)
          }
        None => (None, self.edit_value)
      }
      // Remove all subtree nodes from collapsed set (immutable)
      let mut collapsed_nodes = self.collapsed_nodes
      for id in subtree_ids {
        collapsed_nodes = collapsed_nodes.remove(id)
      }
      // Clear dragging if dragging a node in subtree
      let dragging = match self.dragging {
        Some(drag_id) =>
          if subtree_ids.contains(drag_id) {
            None
          } else {
            self.dragging
          }
        None => None
      }
      // Clear drop_target if targeting a node in subtree
      let drop_target = match self.drop_target {
        Some(target_id) =>
          if subtree_ids.contains(target_id) {
            None
          } else {
            self.drop_target
          }
        None => None
      }
      let drop_position = if drop_target is None {
        None
      } else {
        self.drop_position
      }
      {
        ..self,
        selection,
        editing_node,
        edit_value,
        dragging,
        drop_target,
        drop_position,
        collapsed_nodes,
      }
    }
    WrapInLambda(node_id~, var_name~) => {
      // UI state: keep the wrapped node selected
      // Structural change is handled by SyncEditor::apply_tree_edit + refresh
      let _ = var_name
      { ..self, selection: [node_id] }
    }
    WrapInApp(node_id~) =>
      // UI state: keep the wrapped node selected
      // Structural change is handled by SyncEditor::apply_tree_edit + refresh
      { ..self, selection: [node_id] }
    InsertChild(parent~, index~, kind~) => {
      // UI state: select the parent node
      // Structural change is handled by SyncEditor::apply_tree_edit + refresh
      let _ = (index, kind)
      { ..self, selection: [parent] }
    }
    StartDrag(node_id~) =>
      // Clear any stale drop state when starting a new drag
      {
        ..self,
        dragging: Some(node_id),
        drop_target: None,
        drop_position: None,
      }
    DragOver(target~, position~) =>
      // Guard: only accept drag over if currently dragging and target is not source
      match self.dragging {
        Some(drag_id) =>
          if drag_id == target {
            // Can't drop on self
            self
          } else if is_descendant_of(self, target, drag_id) {
            // Can't drop on descendant
            self
          } else {
            { ..self, drop_target: Some(target), drop_position: Some(position) }
          }
        None => self // Ignore if not dragging
      }
    Drop(source~, target~, position~) =>
      // Guard: only accept drop if dragging matches source
      match self.dragging {
        Some(drag_id) =>
          if drag_id == source &&
            source != target &&
            not(is_descendant_of(self, target, source)) {
            // Valid drop
            let _ = position
            {
              ..self,
              selection: [source],
              dragging: None,
              drop_target: None,
              drop_position: None,
            }
          } else {
            // Invalid drop, just clear drag state
            { ..self, dragging: None, drop_target: None, drop_position: None }
          }
        None =>
          // Not dragging, ignore
          self
      }
    Collapse(node_id~) =>
      // Guard: only collapse if node exists in tree
      if self.loaded_nodes.get(node_id) is Some(_) {
        // Immutable add to collapsed_nodes
        let collapsed_nodes = self.collapsed_nodes.add(node_id)
        // Update tree node to reflect collapsed state
        let (tree, changed_nodes) = update_collapsed_state(
          self.tree,
          node_id,
          true,
        )
        let loaded_nodes = update_loaded_nodes_for_path(
          self.loaded_nodes,
          changed_nodes,
        )
        { ..self, tree, collapsed_nodes, loaded_nodes }
      } else {
        self
      }
    Expand(node_id~) =>
      match self.loaded_nodes.get(node_id) {
        // Keep Expand atomic: callers must hydrate elided branches via
        // `expand_node(...)` before clearing the collapsed flag.
        Some(node) =>
          match node.children {
            Elided(_) => self
            Loaded(_) => {
              let collapsed_nodes = self.collapsed_nodes.remove(node_id)
              let (tree, changed_nodes) = update_collapsed_state(
                self.tree,
                node_id,
                false,
              )
              let loaded_nodes = update_loaded_nodes_for_path(
                self.loaded_nodes,
                changed_nodes,
              )
              { ..self, tree, collapsed_nodes, loaded_nodes }
            }
          }
        None => self
      }
  }
}
