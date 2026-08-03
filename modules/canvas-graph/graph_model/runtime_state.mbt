///|
/// Durable workflow graph document. High-frequency UI affordances such as
/// hover, live drag preview, and viewport live outside this value.
pub(all) struct CanvasDocument {
  nodes : Array[CanvasNode]
  edges : Array[Edge]
  next_node_id : Int
} derive(Debug, Eq)

///|
/// Ephemeral live-drag overlay. Empty positions means no active preview;
/// committed node positions remain in `CanvasDocument` until pointerup.
pub(all) struct DragPreview {
  positions : Array[NodePosition]
} derive(Debug, Eq)

///|
pub impl Show for DragPreview with fn output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
/// Selection is its own UI input so sparse inspector surfaces can depend on it
/// without reading drag/viewport gesture state.
pub(all) struct SelectionState {
  selected : NodeId?
  selected_nodes : Array[NodeId]
} derive(Debug, Eq)

///|
pub fn selection_from_interaction(
  interaction : InteractionState,
) -> SelectionState {
  {
    selected: interaction.selected,
    selected_nodes: interaction.selected_nodes.copy(),
  }
}

///|
pub fn interaction_with_selection(
  interaction : InteractionState,
  selection : SelectionState,
) -> InteractionState {
  {
    ..interaction,
    selected: selection.selected,
    selected_nodes: selection.selected_nodes.copy(),
  }
}

///|
pub fn idle_drag_preview() -> DragPreview {
  { positions: [] }
}

///|
pub fn default_viewport() -> Viewport {
  { x: 760.0, y: 330.0, scale: 0.75 }
}

///|
pub fn canvas_document_from_state(state : CanvasState) -> CanvasDocument {
  {
    nodes: state.nodes.copy(),
    edges: state.edges.copy(),
    next_node_id: state.next_node_id,
  }
}

///|
pub fn canvas_state_from_parts(
  document : CanvasDocument,
  viewport : Viewport,
  interaction : InteractionState,
  action_log : Array[GraphOperation],
) -> CanvasState {
  {
    viewport,
    nodes: document.nodes.copy(),
    edges: document.edges.copy(),
    next_node_id: document.next_node_id,
    interaction: interaction_with_selection(
      interaction,
      selection_from_interaction(interaction),
    ),
    action_log: action_log.copy(),
  }
}

///|
fn preview_position_for(
  preview : DragPreview,
  node_id : NodeId,
) -> NodePosition? {
  find_position(preview.positions, node_id)
}

///|
fn canvas_node_with_preview(
  node : CanvasNode,
  preview : DragPreview,
) -> CanvasNode {
  match preview_position_for(preview, node.id) {
    None => node
    Some(pos) => { ..node, x: pos.x, y: pos.y }
  }
}

///|
pub fn state_with_preview_nodes(
  state : CanvasState,
  preview : DragPreview,
) -> CanvasState {
  {
    ..state,
    nodes: state.nodes.map(fn(node) { canvas_node_with_preview(node, preview) }),
  }
}
