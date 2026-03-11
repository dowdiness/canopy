// Interactive Tree Editor: Data structures and operations for the unified tree editor
// Combines visualization + editing in one component

///|
/// Rendered children for an interactive node.
pub enum InteractiveChildren {
  Loaded(Array[InteractiveTreeNode])
  Elided(Int)
} derive(Show)

///|
/// Interactive tree node with editing state
pub struct InteractiveTreeNode {
  id : NodeId
  kind : @ast.Term
  label : String
  children : InteractiveChildren
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
/// Non-recursive node summary used by refresh-time subtree reuse.
priv enum InteractiveNodeShape {
  Int(Int)
  Var(String)
  Lam(String)
  App
  Bop(@ast.Bop)
  If
  Let(String)
  Unit
  Error(String)
} derive(Eq)

///|
/// Shallow stamp for deciding whether a previously loaded subtree can be reused.
priv struct InteractiveNodeStamp {
  id : NodeId
  shape : InteractiveNodeShape
  label : String
  child_ids : Array[NodeId]
  elided_descendant_count : Int?
  selected : Bool
  editing : Bool
  collapsed : Bool
  drop_target : Bool
  text_range : Range
} derive(Eq)

///|
/// Result of a refresh build, including whether the previous node was reused.
priv struct RefreshedInteractiveNode {
  node : InteractiveTreeNode
  reused_previous : Bool
}

///|
/// Structural indexes for the current projection snapshot.
priv struct TreeStructureIndexes {
  preorder_ids : Array[NodeId]
  preorder_range_by_root : Map[NodeId, (Int, Int)]
  parent_by_child : Map[NodeId, NodeId]
  loaded_nodes : Map[NodeId, InteractiveTreeNode]
}

///|
fn empty_tree_structure_indexes() -> TreeStructureIndexes {
  {
    preorder_ids: [],
    preorder_range_by_root: {},
    parent_by_child: {},
    loaded_nodes: {},
  }
}

///|
/// Build the non-recursive node shape for stamp comparison.
fn interactive_node_shape(kind : @ast.Term) -> InteractiveNodeShape {
  match kind {
    Int(n) => Int(n)
    Var(name) => Var(name)
    Lam(param, _) => Lam(param)
    App(_, _) => App
    Bop(op, _, _) => Bop(op)
    If(_, _, _) => If
    Let(name, _, _) => Let(name)
    Unit => Unit
    Error(msg) => Error(msg)
  }
}

///|
/// Create an interactive tree node from a ProjNode with UI state applied.
/// This is a rendering helper only; index-backed editor operations should use
/// `TreeEditorState::from_projection(...)`.
fn InteractiveTreeNode::from_term_node_with_state(
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
  from_term_node_with_optional_ids(node, source_map, ui_state, None)
}

///|
/// Create an interactive tree node and optionally collect valid IDs.
fn from_term_node_with_optional_ids(
  node : ProjNode,
  source_map : SourceMap,
  ui_state : TreeUIState,
  valid_ids : Array[NodeId]?,
) -> InteractiveTreeNode {
  let node_id = NodeId(node.node_id)
  match valid_ids {
    Some(valid_ids) => valid_ids.push(node_id)
    None => ()
  }
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
  let children = if collapsed {
    let mut descendant_count = 0
    for child in node.children {
      descendant_count += collect_projection_descendants(child, valid_ids)
    }
    Elided(descendant_count)
  } else {
    let loaded : Array[InteractiveTreeNode] = []
    for child in node.children {
      loaded.push(
        from_term_node_with_optional_ids(child, source_map, ui_state, valid_ids),
      )
    }
    Loaded(loaded)
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
/// Count projection descendants while collecting valid IDs for hidden branches.
fn collect_projection_descendants(
  node : ProjNode,
  valid_ids : Array[NodeId]?,
) -> Int {
  let node_id = NodeId(node.node_id)
  match valid_ids {
    Some(valid_ids) => valid_ids.push(node_id)
    None => ()
  }
  let mut subtree_size = 1
  for child in node.children {
    subtree_size += collect_projection_descendants(child, valid_ids)
  }
  subtree_size
}

///|
/// Index the currently loaded interactive tree by node ID for reuse during refresh.
fn build_loaded_node_index(
  tree : InteractiveTreeNode?,
) -> Map[NodeId, InteractiveTreeNode] {
  let index : Map[NodeId, InteractiveTreeNode] = {}
  match tree {
    None => ()
    Some(node) => index_loaded_nodes(index, node)
  }
  index
}

///|
fn index_loaded_nodes(
  index : Map[NodeId, InteractiveTreeNode],
  node : InteractiveTreeNode,
) -> Unit {
  index[node.id] = node
  match node.children {
    Loaded(children) =>
      for child in children {
        index_loaded_nodes(index, child)
      }
    Elided(_) => ()
  }
}

///|
/// Build the shallow reuse stamp for an interactive node.
fn interactive_node_stamp(node : InteractiveTreeNode) -> InteractiveNodeStamp {
  let child_ids : Array[NodeId] = []
  let elided_descendant_count = match node.children {
    Loaded(children) => {
      for child in children {
        child_ids.push(child.id)
      }
      None
    }
    Elided(descendant_count) => Some(descendant_count)
  }
  {
    id: node.id,
    shape: interactive_node_shape(node.kind),
    label: node.label,
    child_ids,
    elided_descendant_count,
    selected: node.selected,
    editing: node.editing,
    collapsed: node.collapsed,
    drop_target: node.drop_target,
    text_range: node.text_range,
  }
}

///|
/// Record a refreshed node into structural indexes and return the refresh result.
fn finish_refreshed_interactive_node(
  indexes : TreeStructureIndexes,
  node_id : NodeId,
  preorder_start : Int,
  node : InteractiveTreeNode,
  reused_previous : Bool,
) -> RefreshedInteractiveNode {
  indexes.loaded_nodes[node_id] = node
  indexes.preorder_range_by_root[node_id] = (
    preorder_start,
    indexes.preorder_ids.length() - 1,
  )
  { node, reused_previous }
}

///|
/// Record projection-only subtree structure without materializing interactive nodes.
fn record_projection_subtree(
  node : ProjNode,
  valid_ids : Array[NodeId],
  parent_id : NodeId?,
  indexes : TreeStructureIndexes,
) -> Int {
  let node_id = NodeId(node.node_id)
  valid_ids.push(node_id)
  let preorder_start = indexes.preorder_ids.length()
  indexes.preorder_ids.push(node_id)
  match parent_id {
    Some(parent_id) => indexes.parent_by_child[node_id] = parent_id
    None => ()
  }
  let mut subtree_size = 1
  for child in node.children {
    subtree_size += record_projection_subtree(
      child,
      valid_ids,
      Some(node_id),
      indexes,
    )
  }
  indexes.preorder_range_by_root[node_id] = (
    preorder_start,
    indexes.preorder_ids.length() - 1,
  )
  subtree_size
}

///|
/// Refresh a node while reusing the previous loaded subtree when its shallow
/// stamp and ordered child reuse state are unchanged.
fn refresh_node_with_reuse_impl(
  node : ProjNode,
  source_map : SourceMap,
  ui_state : TreeUIState,
  valid_ids : Array[NodeId],
  previous_nodes : Map[NodeId, InteractiveTreeNode],
  parent_id : NodeId?,
  indexes : TreeStructureIndexes,
) -> RefreshedInteractiveNode {
  let node_id = NodeId(node.node_id)
  valid_ids.push(node_id)
  let preorder_start = indexes.preorder_ids.length()
  indexes.preorder_ids.push(node_id)
  match parent_id {
    Some(parent_id) => indexes.parent_by_child[node_id] = parent_id
    None => ()
  }
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
  let label = get_node_label(node.kind)
  let previous_node = previous_nodes.get(node_id)
  if collapsed {
    let mut descendant_count = 0
    for child in node.children {
      descendant_count += record_projection_subtree(
        child,
        valid_ids,
        Some(node_id),
        indexes,
      )
    }
    let stamp : InteractiveNodeStamp = {
      id: node_id,
      shape: interactive_node_shape(node.kind),
      label,
      child_ids: [],
      elided_descendant_count: Some(descendant_count),
      selected,
      editing,
      collapsed,
      drop_target,
      text_range,
    }
    match previous_node {
      Some(previous) =>
        if interactive_node_stamp(previous) == stamp {
          finish_refreshed_interactive_node(
            indexes, node_id, preorder_start, previous, true,
          )
        } else {
          let refreshed = {
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
          finish_refreshed_interactive_node(
            indexes, node_id, preorder_start, refreshed, false,
          )
        }
      None => {
        let refreshed = {
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
        finish_refreshed_interactive_node(
          indexes, node_id, preorder_start, refreshed, false,
        )
      }
    }
  } else {
    let children : Array[InteractiveTreeNode] = []
    let child_ids : Array[NodeId] = []
    let previous_loaded_children = match previous_node {
      Some(previous) =>
        match previous.children {
          Loaded(previous_children) => Some(previous_children)
          Elided(_) => None
        }
      None => None
    }
    let mut children_reused = match previous_loaded_children {
      Some(_) => true
      None => false
    }
    for child_index, child in node.children {
      let child_result = refresh_node_with_reuse_impl(
        child,
        source_map,
        ui_state,
        valid_ids,
        previous_nodes,
        Some(node_id),
        indexes,
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
      shape: interactive_node_shape(node.kind),
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
          finish_refreshed_interactive_node(
            indexes, node_id, preorder_start, previous, true,
          )
        } else {
          let refreshed = {
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
          finish_refreshed_interactive_node(
            indexes, node_id, preorder_start, refreshed, false,
          )
        }
      None => {
        let refreshed = {
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
        finish_refreshed_interactive_node(
          indexes, node_id, preorder_start, refreshed, false,
        )
      }
    }
  }
}

///|
/// Build the current interactive tree and structural indexes from a projection snapshot.
fn build_tree_projection_snapshot(
  proj : ProjNode?,
  source_map : SourceMap,
  ui_state : TreeUIState,
  previous_nodes : Map[NodeId, InteractiveTreeNode],
) -> (InteractiveTreeNode?, Array[NodeId], TreeStructureIndexes) {
  let valid_ids : Array[NodeId] = []
  let indexes = empty_tree_structure_indexes()
  let tree = match proj {
    Some(ast) =>
      Some(
        refresh_node_with_reuse_impl(
          ast,
          source_map,
          ui_state,
          valid_ids,
          previous_nodes,
          None,
          indexes,
        ).node,
      )
    None => None
  }
  (tree, valid_ids, indexes)
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
  /// Preorder list for the full projection tree
  priv preorder_ids : Array[NodeId]
  /// Inclusive preorder slice for each subtree root
  priv preorder_range_by_root : Map[NodeId, (Int, Int)]
  /// Parent links for structural queries
  priv parent_by_child : Map[NodeId, NodeId]
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
  let indexes = empty_tree_structure_indexes()
  {
    tree: None,
    selection: [],
    editing_node: None,
    edit_value: "",
    dragging: None,
    drop_target: None,
    drop_position: None,
    collapsed_nodes: @immut/hashset.new(),
    preorder_ids: indexes.preorder_ids,
    preorder_range_by_root: indexes.preorder_range_by_root,
    parent_by_child: indexes.parent_by_child,
    loaded_nodes: indexes.loaded_nodes,
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
  let (tree, _, indexes) = build_tree_projection_snapshot(
    proj,
    source_map,
    ui_state,
    {},
  )
  {
    tree,
    selection: [],
    editing_node: None,
    edit_value: "",
    dragging: None,
    drop_target: None,
    drop_position: None,
    collapsed_nodes,
    preorder_ids: indexes.preorder_ids,
    preorder_range_by_root: indexes.preorder_range_by_root,
    parent_by_child: indexes.parent_by_child,
    loaded_nodes: indexes.loaded_nodes,
  }
}

///|
/// Refresh tree from projection while preserving UI state (collapsed nodes).
/// Also prunes stale IDs from UI state that no longer exist in the tree.
pub fn TreeEditorState::refresh(
  self : TreeEditorState,
  proj : ProjNode?,
  source_map : SourceMap,
) -> TreeEditorState {
  match proj {
    Some(ast) => {
      let previous_nodes = build_loaded_node_index(self.tree)
      let selection_set = @immut/hashset.from_iter(self.selection.iter())
      let ui_state : TreeUIState = {
        collapsed_nodes: self.collapsed_nodes,
        selection: selection_set,
        editing_node: self.editing_node,
        drop_target: self.drop_target,
      }
      let (tree, valid_id_list, indexes) = build_tree_projection_snapshot(
        Some(ast),
        source_map,
        ui_state,
        previous_nodes,
      )
      let valid_ids = @immut/hashset.from_iter(valid_id_list.iter())
      let collapsed_nodes = self.collapsed_nodes.intersection(valid_ids)
      let selection = self.selection.filter(fn(id) { valid_ids.contains(id) })
      let editing_node = match self.editing_node {
        Some(id) => if valid_ids.contains(id) { Some(id) } else { None }
        None => None
      }
      let edit_value = if editing_node is None && self.editing_node is Some(_) {
        ""
      } else {
        self.edit_value
      }
      let dragging = match self.dragging {
        Some(id) => if valid_ids.contains(id) { Some(id) } else { None }
        None => None
      }
      let drop_target = match self.drop_target {
        Some(id) => if valid_ids.contains(id) { Some(id) } else { None }
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
        collapsed_nodes,
        preorder_ids: indexes.preorder_ids,
        preorder_range_by_root: indexes.preorder_range_by_root,
        parent_by_child: indexes.parent_by_child,
        loaded_nodes: indexes.loaded_nodes,
      }
    }
    None => {
      let indexes = empty_tree_structure_indexes()
      {
        ..self,
        tree: None,
        preorder_ids: indexes.preorder_ids,
        preorder_range_by_root: indexes.preorder_range_by_root,
        parent_by_child: indexes.parent_by_child,
        loaded_nodes: indexes.loaded_nodes,
      }
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
              let subtree_valid_ids : Array[NodeId] = []
              let subtree_indexes = empty_tree_structure_indexes()
              let hydrated = refresh_node_with_reuse_impl(
                proj_node,
                source_map,
                ui_state,
                subtree_valid_ids,
                self.loaded_nodes,
                self.parent_by_child.get(node_id),
                subtree_indexes,
              )
              let (updated_tree, changed_nodes) = replace_loaded_subtree(
                Some(tree),
                node_id,
                hydrated.node,
              )
              let loaded_nodes = replace_loaded_nodes_for_subtree(
                self.loaded_nodes,
                collect_subtree_ids(self, node_id),
                subtree_indexes.loaded_nodes,
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

///|
/// Apply selection state locally to the loaded interactive tree.
fn apply_selection_edit(
  state : TreeEditorState,
  selection : Array[NodeId],
) -> TreeEditorState {
  let selection_set = @immut/hashset.from_iter(selection.iter())
  match state.tree {
    None => { ..state, selection, }
    Some(root) => {
      let (updated, changed) = apply_selection_to_node(root, selection_set)
      if changed {
        let loaded_nodes = build_loaded_node_index(Some(updated))
        { ..state, selection, tree: Some(updated), loaded_nodes }
      } else {
        { ..state, selection, }
      }
    }
  }
}

///|
fn apply_selection_to_node(
  node : InteractiveTreeNode,
  selection : @immut/hashset.HashSet[NodeId],
) -> (InteractiveTreeNode, Bool) {
  let new_selected = selection.contains(node.id)
  match node.children {
    Loaded(existing_children) => {
      let updated_children : Array[InteractiveTreeNode] = []
      let mut any_child_changed = false
      for child in existing_children {
        let (updated, changed) = apply_selection_to_node(child, selection)
        updated_children.push(updated)
        if changed {
          any_child_changed = true
        }
      }
      if new_selected == node.selected && not(any_child_changed) {
        (node, false)
      } else {
        let children = if any_child_changed {
          Loaded(updated_children)
        } else {
          node.children
        }
        ({ ..node, selected: new_selected, children }, true)
      }
    }
    Elided(_) =>
      if new_selected == node.selected {
        (node, false)
      } else {
        ({ ..node, selected: new_selected }, true)
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
fn collect_subtree_ids(
  state : TreeEditorState,
  root_id : NodeId,
) -> Array[NodeId] {
  match state.preorder_range_by_root.get(root_id) {
    Some((start_idx, end_idx)) =>
      collect_preorder_slice(state.preorder_ids, start_idx, end_idx)
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
/// Check if a node is a descendant of another node using parent links.
fn is_descendant_of(
  state : TreeEditorState,
  node_id : NodeId,
  ancestor_id : NodeId,
) -> Bool {
  if node_id == ancestor_id {
    false
  } else {
    is_descendant_in_parent_links(state.parent_by_child, node_id, ancestor_id)
  }
}

///|
/// Collect all node IDs between start and end (inclusive) using preorder indexes.
fn collect_nodes_in_range(
  state : TreeEditorState,
  start : NodeId,
  end : NodeId,
) -> Array[NodeId] {
  match
    (
      state.preorder_range_by_root.get(start),
      state.preorder_range_by_root.get(end),
    ) {
    (Some((start_idx, _)), Some((end_idx, _))) => {
      let min_idx = if start_idx < end_idx { start_idx } else { end_idx }
      let max_idx = if start_idx > end_idx { start_idx } else { end_idx }
      collect_preorder_slice(state.preorder_ids, min_idx, max_idx)
    }
    // If either endpoint is missing, return empty to avoid stale references
    _ => []
  }
}

///|
/// Update the collapsed state of a node in the tree
fn update_collapsed_state(
  tree : InteractiveTreeNode?,
  node_id : NodeId,
  collapsed : Bool,
) -> (InteractiveTreeNode?, Array[InteractiveTreeNode]) {
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
fn replace_loaded_subtree(
  tree : InteractiveTreeNode?,
  node_id : NodeId,
  replacement : InteractiveTreeNode,
) -> (InteractiveTreeNode?, Array[InteractiveTreeNode]) {
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
fn replace_loaded_subtree_node(
  node : InteractiveTreeNode,
  target_id : NodeId,
  replacement : InteractiveTreeNode,
) -> (InteractiveTreeNode, Bool, Array[InteractiveTreeNode]) {
  if node.id == target_id {
    (replacement, true, [replacement])
  } else {
    match node.children {
      Loaded(existing_children) => {
        let children : Array[InteractiveTreeNode] = []
        let child_path : Array[InteractiveTreeNode] = []
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
          let changed_path : Array[InteractiveTreeNode] = [updated]
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
fn update_node_collapsed(
  node : InteractiveTreeNode,
  target_id : NodeId,
  collapsed : Bool,
) -> (InteractiveTreeNode, Bool, Array[InteractiveTreeNode]) {
  if node.id == target_id {
    let updated = { ..node, collapsed, }
    (updated, true, [updated])
  } else {
    match node.children {
      Loaded(existing_children) => {
        let children : Array[InteractiveTreeNode] = []
        let child_path : Array[InteractiveTreeNode] = []
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
          let changed_path : Array[InteractiveTreeNode] = [updated]
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
fn update_loaded_nodes_for_path(
  loaded_nodes : Map[NodeId, InteractiveTreeNode],
  changed_nodes : Array[InteractiveTreeNode],
) -> Map[NodeId, InteractiveTreeNode] {
  let updated = loaded_nodes.copy()
  for node in changed_nodes {
    updated[node.id] = node
  }
  updated
}

///|
/// Replace the materialized node index for one subtree and patch changed ancestors.
fn replace_loaded_nodes_for_subtree(
  loaded_nodes : Map[NodeId, InteractiveTreeNode],
  subtree_ids : Array[NodeId],
  replacement_nodes : Map[NodeId, InteractiveTreeNode],
  changed_nodes : Array[InteractiveTreeNode],
) -> Map[NodeId, InteractiveTreeNode] {
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
