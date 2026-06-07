///|
pub using @graph_model {
  type CanvasNode,
  type CanvasState,
  type ConnectState,
  type DragOrigin,
  type DragState,
  type Edge,
  type EdgeId,
  type GraphOperation,
  type InteractionState,
  type NodeId,
  type NodeKind,
  type NodePosition,
  type PanState,
  type PortDef,
  type PortType,
  type Viewport,
  type WorkflowAction,
  type WorkflowNodeKind,
}

///|
using @graph_model {
  find_node,
  find_position,
  make_workflow_node,
  port_type_by_id,
  record_action,
}

///|
/// Durable workflow graph document. High-frequency UI affordances such as
/// hover, live drag preview, and viewport live outside this value.
struct CanvasDocument {
  nodes : Array[CanvasNode]
  edges : Array[Edge]
  next_node_id : Int
  next_edge_id : Int
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
struct SelectionState {
  selected : NodeId?
  selected_nodes : Array[NodeId]
} derive(Debug, Eq)

///|
fn selection_from_interaction(interaction : InteractionState) -> SelectionState {
  {
    selected: interaction.selected,
    selected_nodes: interaction.selected_nodes.copy(),
  }
}

///|
fn interaction_with_selection(
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
fn idle_drag_preview() -> DragPreview {
  { positions: [] }
}

///|
fn default_viewport() -> Viewport {
  { x: 760.0, y: 330.0, scale: 0.75 }
}

///|
fn canvas_document_from_state(state : CanvasState) -> CanvasDocument {
  {
    nodes: state.nodes.copy(),
    edges: state.edges.copy(),
    next_node_id: state.next_node_id,
    next_edge_id: state.next_edge_id,
  }
}

///|
fn canvas_state_from_parts(
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
    next_edge_id: document.next_edge_id,
    interaction: interaction_with_selection(
      interaction,
      selection_from_interaction(interaction),
    ),
    action_log: action_log.copy(),
  }
}
