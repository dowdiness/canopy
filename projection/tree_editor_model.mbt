// Interactive Tree Editor: Data types, rendering model, and editor state

///|
/// Rendered children for an interactive node.
pub enum InteractiveChildren[T] {
  Loaded(Array[InteractiveTreeNode[T]])
  Elided(Int)
} derive(Show)

///|
/// Interactive tree node with editing state
pub struct InteractiveTreeNode[T] {
  id : NodeId
  kind : T
  label : String
  children : InteractiveChildren[T]
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
pub fn[T : Renderable] InteractiveTreeNode::from_term_node(
  node : ProjNode[T],
  source_map : SourceMap,
) -> InteractiveTreeNode[T] {
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
/// Shallow stamp for deciding whether a previously loaded subtree can be reused.
/// Shallow stamp — uses kind_tag + label instead of full T equality
/// to keep stamp comparison O(1) rather than O(subtree).
priv struct InteractiveNodeStamp {
  id : NodeId
  kind_tag : String
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
priv struct RefreshedInteractiveNode[T] {
  node : InteractiveTreeNode[T]
  reused_previous : Bool
}

///|
/// Lazy preorder index, built on demand.
priv struct LazyPreorder {
  ids : Array[NodeId]
  range_by_root : Map[NodeId, (Int, Int)]
}

///|
/// Build the shallow reuse stamp for an interactive node.
fn[T : Renderable] interactive_node_stamp(
  node : InteractiveTreeNode[T],
) -> InteractiveNodeStamp {
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
    kind_tag: Renderable::kind_tag(node.kind),
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
/// Create an interactive tree node from a ProjNode with UI state applied.
/// This is a rendering helper only; index-backed editor operations should use
/// `TreeEditorState::from_projection(...)`.
fn[T : Renderable] InteractiveTreeNode::from_term_node_with_state(
  node : ProjNode[T],
  source_map : SourceMap,
  collapsed_nodes : @immut/hashset.HashSet[NodeId],
) -> InteractiveTreeNode[T] {
  let ui_state : TreeUIState = {
    collapsed_nodes,
    selection: @immut/hashset.new(),
    editing_node: None,
    drop_target: None,
  }
  from_term_node_impl(node, source_map, ui_state)
}

///|
/// Create an interactive tree node with UI state applied.
fn[T : Renderable] from_term_node_impl(
  node : ProjNode[T],
  source_map : SourceMap,
  ui_state : TreeUIState,
) -> InteractiveTreeNode[T] {
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
  let children = if collapsed {
    let mut descendant_count = 0
    for child in node.children {
      descendant_count += count_projection_descendants(child)
    }
    Elided(descendant_count)
  } else {
    let loaded : Array[InteractiveTreeNode[T]] = []
    for child in node.children {
      loaded.push(from_term_node_impl(child, source_map, ui_state))
    }
    Loaded(loaded)
  }
  {
    id: node_id,
    kind: node.kind,
    label: Renderable::label(node.kind),
    children,
    selected,
    editing,
    collapsed,
    drop_target,
    text_range,
  }
}

///|
/// Count projection descendants.
fn[T] count_projection_descendants(node : ProjNode[T]) -> Int {
  let mut subtree_size = 1
  for child in node.children {
    subtree_size += count_projection_descendants(child)
  }
  subtree_size
}

///|
/// Check if a node is a leaf (editable inline).
/// A leaf has no structural children per the TreeNode trait.
pub fn[T : TreeNode] is_leaf_node(kind : T) -> Bool {
  T::children(kind).is_empty()
}

///|
/// Editor state for the interactive tree
pub struct TreeEditorState[T] {
  /// The interactive tree representation
  tree : InteractiveTreeNode[T]?
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
  priv loaded_nodes : Map[NodeId, InteractiveTreeNode[T]]
}

///|
/// Look up a materialized interactive node by ID. O(1) via the loaded-node index.
pub fn[T] TreeEditorState::get_loaded_node(
  self : TreeEditorState[T],
  node_id : NodeId,
) -> InteractiveTreeNode[T]? {
  self.loaded_nodes.get(node_id)
}

///|
/// Check if a node ID is valid in the current tree state.
pub fn[T] TreeEditorState::has_node(
  self : TreeEditorState[T],
  node_id : NodeId,
) -> Bool {
  self.loaded_nodes.get(node_id) is Some(_)
}

///|
/// Create a new tree editor state
pub fn[T] TreeEditorState::new() -> TreeEditorState[T] {
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
pub fn[T : TreeNode + Renderable] TreeEditorState::from_projection(
  proj : ProjNode[T]?,
  source_map : SourceMap,
) -> TreeEditorState[T] {
  let collapsed_nodes : @immut/hashset.HashSet[NodeId] = @immut/hashset.new()
  let ui_state : TreeUIState = {
    collapsed_nodes,
    selection: @immut/hashset.new(),
    editing_node: None,
    drop_target: None,
  }
  let loaded_nodes : Map[NodeId, InteractiveTreeNode[T]] = {}
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
