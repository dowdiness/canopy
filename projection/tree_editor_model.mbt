// Interactive Tree Editor: Data types and rendering model

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
  Module
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
/// Lazy preorder index, built on demand.
priv struct LazyPreorder {
  ids : Array[NodeId]
  range_by_root : Map[NodeId, (Int, Int)]
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
    Module(_, _) => Module
    Unit => Unit
    Unbound(name) => Var(name) // Unbound rendered same as Var in editor
    Error(msg) => Error(msg)
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
  from_term_node_impl(node, source_map, ui_state)
}

///|
/// Create an interactive tree node with UI state applied.
fn from_term_node_impl(
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
  let children = if collapsed {
    let mut descendant_count = 0
    for child in node.children {
      descendant_count += count_projection_descendants(child)
    }
    Elided(descendant_count)
  } else {
    let loaded : Array[InteractiveTreeNode] = []
    for child in node.children {
      loaded.push(from_term_node_impl(child, source_map, ui_state))
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
/// Count projection descendants.
fn count_projection_descendants(node : ProjNode) -> Int {
  let mut subtree_size = 1
  for child in node.children {
    subtree_size += count_projection_descendants(child)
  }
  subtree_size
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
    Module(defs, _) => {
      let names = defs.map(fn(d) { d.0 })
      "module [" + names.join(", ") + "]"
    }
    Unit => "()"
    Unbound(name) => "?" + name
    Error(msg) => "Error: " + msg
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
