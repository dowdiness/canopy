// Interactive Tree Editor: Data structures and operations for the unified tree editor
// Combines visualization + editing in one component

///|
/// Interactive tree node with editing state
pub struct InteractiveTreeNode {
  id : NodeId
  kind : @ast.Term
  label : String
  children : Array[InteractiveTreeNode]
  /// Currently selected
  selected : Bool
  /// Inline editing active
  editing : Bool
  /// Subtree collapsed
  collapsed : Bool
  /// Valid drop zone
  drop_target : Bool
  /// Corresponding text range
  text_range : Range
} derive(Show)

///|
/// Create an interactive tree node from a ProjNode
pub fn InteractiveTreeNode::from_term_node(
  node : ProjNode,
  source_map : SourceMap,
) -> InteractiveTreeNode {
  InteractiveTreeNode::from_term_node_with_state(
    node,
    source_map,
    @immut/hashset.new(),
  )
}

///|
/// UI state for building interactive tree nodes
priv struct TreeUIState {
  collapsed_nodes : @immut/hashset.HashSet[NodeId]
  selection : @immut/hashset.HashSet[NodeId]
  editing_node : NodeId?
  drop_target : NodeId?
}

///|
/// Create an interactive tree node from a ProjNode with UI state applied
/// This is the lens get operation: InteractiveTree = get(ProjNode, UIState)
pub fn InteractiveTreeNode::from_term_node_with_state(
  node : ProjNode,
  source_map : SourceMap,
  collapsed_nodes : @immut/hashset.HashSet[NodeId],
) -> InteractiveTreeNode {
  let ui_state : TreeUIState = {
    collapsed_nodes,
    selection: @immut/hashset.new(),
    editing_node: None,
    drop_target: None,
  }
  from_term_node_with_full_state(node, source_map, ui_state)
}

///|
/// Create an interactive tree node with full UI state (internal)
fn from_term_node_with_full_state(
  node : ProjNode,
  source_map : SourceMap,
  ui_state : TreeUIState,
) -> InteractiveTreeNode {
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
  let children : Array[InteractiveTreeNode] = []
  for child in node.children {
    children.push(from_term_node_with_full_state(child, source_map, ui_state))
  }
  {
    id: node_id,
    kind: node.kind,
    label: get_node_label(node.kind),
    children,
    selected,
    editing,
    collapsed,
    drop_target,
    text_range,
  }
}

///|
/// Get display label for a node kind
fn get_node_label(kind : @ast.Term) -> String {
  match kind {
    Int(n) => n.to_string()
    Var(name) => name
    Lam(param, _) => "λ" + param
    App(_, _) => "App"
    Bop(op, _, _) => op.to_string()
    If(_, _, _) => "if"
    Let(name, _, _) => "let " + name
    Unit => "()"
    Error(msg) => "Error: " + msg
  }
}

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
  }
}

///|
/// Create tree editor state from a canonical model
pub fn TreeEditorState::from_model(model : CanonicalModel) -> TreeEditorState {
  let collapsed_nodes : @immut/hashset.HashSet[NodeId] = @immut/hashset.new()
  let tree = match model.get_ast() {
    Some(ast) =>
      Some(
        InteractiveTreeNode::from_term_node_with_state(
          ast,
          model.get_source_map(),
          collapsed_nodes,
        ),
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
  }
}

///|
/// Refresh tree from model while preserving UI state (collapsed nodes)
/// This is the lens-based approach: tree = lens_get(model, ui_state)
/// Also prunes stale IDs from UI state that no longer exist in the tree.
pub fn TreeEditorState::refresh_from_model(
  self : TreeEditorState,
  model : CanonicalModel,
) -> TreeEditorState {
  match model.get_ast() {
    Some(ast) => {
      // Build set of valid IDs from new tree
      let valid_ids = collect_all_ids_from_ast(ast)
      // Prune stale IDs from collapsed_nodes using set intersection
      let collapsed_nodes = self.collapsed_nodes.intersection(valid_ids)
      // Prune stale IDs from selection
      let selection = self.selection.filter(fn(id) { valid_ids.contains(id) })
      // Clear editing_node if stale
      let editing_node = match self.editing_node {
        Some(id) => if valid_ids.contains(id) { Some(id) } else { None }
        None => None
      }
      let edit_value = if editing_node is None && self.editing_node is Some(_) {
        ""
      } else {
        self.edit_value
      }
      // Clear dragging if stale
      let dragging = match self.dragging {
        Some(id) => if valid_ids.contains(id) { Some(id) } else { None }
        None => None
      }
      // Clear drop_target if stale
      let drop_target = match self.drop_target {
        Some(id) => if valid_ids.contains(id) { Some(id) } else { None }
        None => None
      }
      let drop_position = if drop_target is None {
        None
      } else {
        self.drop_position
      }
      // Build selection set for tree construction
      let selection_set = @immut/hashset.from_iter(selection.iter())
      // Build tree with full UI state
      let ui_state : TreeUIState = {
        collapsed_nodes,
        selection: selection_set,
        editing_node,
        drop_target,
      }
      let tree = Some(
        from_term_node_with_full_state(ast, model.get_source_map(), ui_state),
      )
      {
        tree,
        selection,
        editing_node,
        edit_value,
        dragging,
        drop_target,
        drop_position,
        collapsed_nodes,
      }
    }
    None => { ..self, tree: None }
  }
}

///|
/// Collect all node IDs from AST as immutable set
fn collect_all_ids_from_ast(node : ProjNode) -> @immut/hashset.HashSet[NodeId] {
  collect_ids_from_ast_helper(node, @immut/hashset.new())
}

///|
fn collect_ids_from_ast_helper(
  node : ProjNode,
  result : @immut/hashset.HashSet[NodeId],
) -> @immut/hashset.HashSet[NodeId] {
  let mut acc = result.add(NodeId(node.node_id))
  for child in node.children {
    acc = collect_ids_from_ast_helper(child, acc)
  }
  acc
}

///|
/// Apply a tree edit operation to the editor state
pub fn TreeEditorState::apply_edit(
  self : TreeEditorState,
  edit : TreeEditOp,
) -> TreeEditorState {
  match edit {
    Select(node_id~) => { ..self, selection: [node_id] }
    SelectRange(start~, end~) => {
      // Collect all nodes between start and end (inclusive) in tree order
      // If either endpoint is stale (missing), preserve existing selection
      let new_selection = collect_nodes_in_range(self.tree, start, end)
      if new_selection.is_empty() && not(self.selection.is_empty()) {
        self
      } else {
        { ..self, selection: new_selection }
      }
    }
    StartEdit(node_id~) => {
      // Get current value from tree
      let edit_value = match find_node(self.tree, node_id) {
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
      let subtree_ids = collect_subtree_ids(self.tree, node_id)
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
      // Structural change is handled by tree_lens_apply_edit + refresh_from_model
      let _ = var_name
      { ..self, selection: [node_id] }
    }
    WrapInApp(node_id~) =>
      // UI state: keep the wrapped node selected
      // Structural change is handled by tree_lens_apply_edit + refresh_from_model
      { ..self, selection: [node_id] }
    InsertChild(parent~, index~, kind~) => {
      // UI state: select the parent node
      // Structural change is handled by tree_lens_apply_edit + refresh_from_model
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
          } else if is_descendant_of(self.tree, target, drag_id) {
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
            not(is_descendant_of(self.tree, target, source)) {
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
      if find_node(self.tree, node_id) is Some(_) {
        // Immutable add to collapsed_nodes
        let collapsed_nodes = self.collapsed_nodes.add(node_id)
        // Update tree node to reflect collapsed state
        let tree = update_collapsed_state(self.tree, node_id, true)
        { ..self, tree, collapsed_nodes }
      } else {
        self
      }
    Expand(node_id~) =>
      // Guard: only expand if node exists in tree
      if find_node(self.tree, node_id) is Some(_) {
        // Immutable remove from collapsed_nodes
        let collapsed_nodes = self.collapsed_nodes.remove(node_id)
        // Update tree node to reflect expanded state
        let tree = update_collapsed_state(self.tree, node_id, false)
        { ..self, tree, collapsed_nodes }
      } else {
        self
      }
  }
}

///|
/// Find a node by ID in the tree
fn find_node(
  tree : InteractiveTreeNode?,
  node_id : NodeId,
) -> InteractiveTreeNode? {
  match tree {
    None => None
    Some(node) =>
      if node.id == node_id {
        Some(node)
      } else {
        find_node_in_children(node.children, node_id)
      }
  }
}

///|
/// Find a node in a list of children
fn find_node_in_children(
  children : Array[InteractiveTreeNode],
  node_id : NodeId,
) -> InteractiveTreeNode? {
  for child in children {
    if child.id == node_id {
      return Some(child)
    }
    match find_node_in_children(child.children, node_id) {
      Some(found) => return Some(found)
      None => ()
    }
  }
  None
}

///|
/// Collect all node IDs in a subtree rooted at the given node
fn collect_subtree_ids(
  tree : InteractiveTreeNode?,
  root_id : NodeId,
) -> Array[NodeId] {
  match find_node(tree, root_id) {
    Some(node) => {
      let result : Array[NodeId] = []
      flatten_tree_preorder(node, result)
      result
    }
    None => []
  }
}

///|
/// Check if a node is a descendant of another node
fn is_descendant_of(
  tree : InteractiveTreeNode?,
  node_id : NodeId,
  ancestor_id : NodeId,
) -> Bool {
  match find_node(tree, ancestor_id) {
    Some(ancestor) => {
      // Check if node_id is in the subtree rooted at ancestor (excluding ancestor itself)
      for child in ancestor.children {
        if contains_node(child, node_id) {
          return true
        }
      }
      false
    }
    None => false
  }
}

///|
/// Check if a node contains a given node ID in its subtree
fn contains_node(node : InteractiveTreeNode, target_id : NodeId) -> Bool {
  if node.id == target_id {
    true
  } else {
    for child in node.children {
      if contains_node(child, target_id) {
        return true
      }
    }
    false
  }
}

///|
/// Collect all node IDs between start and end (inclusive) in pre-order traversal
/// Uses index-based approach: flatten tree, find indices, return slice from min to max
fn collect_nodes_in_range(
  tree : InteractiveTreeNode?,
  start : NodeId,
  end : NodeId,
) -> Array[NodeId] {
  // Flatten tree to array in pre-order
  let all_nodes : Array[NodeId] = []
  match tree {
    None => return []
    Some(node) => flatten_tree_preorder(node, all_nodes)
  }
  // Find indices of start and end
  let mut start_idx : Int? = None
  let mut end_idx : Int? = None
  for i, id in all_nodes {
    if id == start {
      start_idx = Some(i)
    }
    if id == end {
      end_idx = Some(i)
    }
  }
  // Return slice from min to max (inclusive)
  // Both endpoints must exist in the tree for a valid range selection
  match (start_idx, end_idx) {
    (Some(si), Some(ei)) => {
      let min_idx = if si < ei { si } else { ei }
      let max_idx = if si > ei { si } else { ei }
      let result : Array[NodeId] = []
      for i = min_idx; i <= max_idx; i = i + 1 {
        result.push(all_nodes[i])
      }
      result
    }
    // If either endpoint is missing, return empty to avoid stale references
    _ => []
  }
}

///|
/// Flatten tree to array in pre-order traversal
fn flatten_tree_preorder(
  node : InteractiveTreeNode,
  result : Array[NodeId],
) -> Unit {
  result.push(node.id)
  for child in node.children {
    flatten_tree_preorder(child, result)
  }
}

///|
/// Update the collapsed state of a node in the tree
fn update_collapsed_state(
  tree : InteractiveTreeNode?,
  node_id : NodeId,
  collapsed : Bool,
) -> InteractiveTreeNode? {
  match tree {
    None => None
    Some(node) => Some(update_node_collapsed(node, node_id, collapsed))
  }
}

///|
/// Recursively update a node's collapsed state
fn update_node_collapsed(
  node : InteractiveTreeNode,
  target_id : NodeId,
  collapsed : Bool,
) -> InteractiveTreeNode {
  if node.id == target_id {
    { ..node, collapsed, }
  } else {
    let children : Array[InteractiveTreeNode] = []
    for child in node.children {
      children.push(update_node_collapsed(child, target_id, collapsed))
    }
    { ..node, children, }
  }
}

///|
/// Check if a node is a leaf (editable inline).
/// Error nodes are treated as leaves so they can be edited in place.
pub fn is_leaf_node(kind : @ast.Term) -> Bool {
  match kind {
    Int(_) => true
    Var(_) => true
    Error(_) => true
    _ => false
  }
}

///|
/// Check if a drop is valid
pub fn is_valid_drop(
  source : @ast.Term,
  target : @ast.Term,
  position : DropPosition,
) -> Bool {
  // Prevent dropping a node into itself or its descendants
  // For now, allow most drops
  let _ = (source, target, position)
  true
}
