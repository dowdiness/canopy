// Interactive Tree Editor: Edit operations

///|
/// Apply a tree edit operation to the editor state
pub fn[T] TreeEditorState::apply_edit(
  self : TreeEditorState[T],
  edit : TreeEditOp,
) -> TreeEditorState[T] {
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
    // Structural ops that use node_id — clear editing state
    Unwrap(node_id~, ..)
    | SwapChildren(node_id~)
    | WrapInIf(node_id~)
    | WrapInBop(node_id~, ..)
    | ChangeOperator(node_id~, ..)
    | ExtractToLet(node_id~, ..)
    | InlineDefinition(node_id~)
    | Rename(node_id~, ..) => {
      let _ = node_id
      { ..self, editing_node: None, edit_value: "" }
    }
    // Binding-level ops — clear editing state
    DeleteBinding(..)
    | InlineAllUsages(..)
    | DuplicateBinding(..)
    | MoveBindingUp(..)
    | MoveBindingDown(..)
    | AddBinding(..) => { ..self, editing_node: None, edit_value: "" }
  }
}
