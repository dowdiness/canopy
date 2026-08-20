///|
using @spatial {type WorldPoint}

///|
/// Private example-local seam between graph runtime mechanics and the workflow
/// canvas host. Runtime code owns incr cells, gesture reducers, and durable /
/// ephemeral synchronization; this policy owns host-specific choices: initial
/// document/viewport, validation messages, render DTO lowering, inspector text,
/// and add-node templates. Keep this private until a second real host proves
/// the reusable runtime API shape.
priv struct CanvasHostPolicy {
  initial_state : () -> CanvasState
  validate_document : (CanvasDocument) -> Array[ValidationJson]
  node_to_json : (CanvasNode) -> NodeJson
  inspector_node : (CanvasDocument, NodeId) -> InspectorNodeJson?
  selected_inspector_source : String
  hovered_inspector_source : String
  add_node : (CanvasState, String, WorldPoint) -> CanvasState
}

///|
fn CanvasHostPolicy::CanvasHostPolicy(
  initial_state~ : () -> CanvasState,
  validate_document~ : (CanvasDocument) -> Array[ValidationJson],
  node_to_json~ : (CanvasNode) -> NodeJson,
  inspector_node~ : (CanvasDocument, NodeId) -> InspectorNodeJson?,
  selected_inspector_source~ : String,
  hovered_inspector_source~ : String,
  add_node~ : (CanvasState, String, WorldPoint) -> CanvasState,
) -> CanvasHostPolicy {
  {
    initial_state,
    validate_document,
    node_to_json,
    inspector_node,
    selected_inspector_source,
    hovered_inspector_source,
    add_node,
  }
}

///|
fn workflow_canvas_host_policy() -> CanvasHostPolicy {
  CanvasHostPolicy::CanvasHostPolicy(
    initial_state=() => CanvasState::default(),
    validate_document=validate_workflow_document,
    node_to_json~,
    inspector_node=workflow_inspector_node,
    selected_inspector_source="selected",
    hovered_inspector_source="hovered",
    add_node=(state, kind_key, position) => {
      @graph_model.workflow_add_node(state, kind_key, position)
    },
  )
}

///|
fn CanvasHostPolicy::validate_canvas_document(
  self : CanvasHostPolicy,
  document : CanvasDocument,
) -> ValidatedCanvas {
  let snapshot : CanvasDocument = {
    nodes: document.nodes.copy(),
    edges: document.edges.copy(),
    next_node_id: document.next_node_id,
  }
  { document: snapshot, validation: (self.validate_document)(snapshot) }
}

///|
fn CanvasHostPolicy::lower_canvas(
  self : CanvasHostPolicy,
  normalized : NormalizedCanvas,
) -> LoweredCanvas {
  {
    nodes: normalized.document.nodes.map(self.node_to_json),
    edges: normalized.document.edges.copy(),
    validation: normalized.validation.copy(),
  }
}

///|
fn CanvasHostPolicy::inspector_node_for_document(
  self : CanvasHostPolicy,
  document : CanvasDocument,
  node_id : NodeId,
) -> InspectorNodeJson? {
  (self.inspector_node)(document, node_id)
}

///|
fn CanvasHostPolicy::inspector_with_source(
  _self : CanvasHostPolicy,
  inspector : InspectorNodeJson?,
  source : String,
) -> InspectorNodeJson? {
  match inspector {
    None => None
    Some(node) => Some({ ..node, source, })
  }
}

///|
fn preview_position_for(
  preview : DragPreview,
  node_id : String,
) -> NodePosition? {
  @graph_model.find_position(preview.positions, NodeId(node_id))
}

///|
fn render_node_with_preview(node : NodeJson, preview : DragPreview) -> NodeJson {
  match preview_position_for(preview, node.id) {
    None => node
    Some(pos) => {
      let point = pos.point
      { ..node, x: point.x(), y: point.y() }
    }
  }
}

///|
fn connecting_to_json(connecting : ConnectState?) -> ConnectingJson? {
  match connecting {
    None => None
    Some(c) => {
      let NodeId(from) = c.from_node
      Some({
        from,
        from_port: c.from_port,
        cursor_x: c.cursor().x(),
        cursor_y: c.cursor().y(),
        path_d: None,
      })
    }
  }
}

///|
fn connecting_to_json_with_path(
  connecting : ConnectState?,
  node_index : Map[String, NodeJson],
) -> ConnectingJson? {
  match connecting_to_json(connecting) {
    None => None
    Some(value) => Some({
      ..value,
      path_d: project_pending_path(node_index, Some(value)),
    })
  }
}

///|
fn edge_render_to_json(edge : EdgeRenderProjection) -> EdgeJson {
  {
    id: edge.id,
    path_d: edge.path_d,
    selected: edge.selected,
    aria_label: edge.aria_label,
  }
}

///|
fn CanvasHostPolicy::render_full_canvas(
  _self : CanvasHostPolicy,
  lowered : LoweredCanvas,
  viewport : Viewport,
  drag_preview : DragPreview,
  selection : SelectionState,
  selected_edge : EdgeId?,
  interaction : InteractionState,
  action_count : Int,
  input_compatibility : Array[PortCompatibilityJson],
) -> CanvasFullRenderJson {
  let selected : String? = match selection.selected {
    None => None
    Some(id) => Some(node_id_to_string(id))
  }
  let selected_nodes = selection.selected_nodes.map(node_id_to_string)
  let rendered_nodes = lowered.nodes.map(fn(node) {
    render_node_with_preview(node, drag_preview)
  })
  let node_index = edge_render_node_index(rendered_nodes)
  {
    viewport,
    nodes: rendered_nodes.copy(),
    edges: project_edge_renders(node_index, lowered.edges, selected_edge).map(
      edge_render_to_json,
    ),
    selected,
    selected_edge: match selected_edge {
      None => None
      Some(id) => Some(id.to_string())
    },
    selected_nodes,
    connecting: connecting_to_json_with_path(interaction.connecting, node_index),
    input_compatibility,
    validation: lowered.validation.copy(),
    action_count,
  }
}

///|
fn CanvasHostPolicy::render_state_from_parts(
  _self : CanvasHostPolicy,
  full : CanvasFullRenderJson,
  inspector : InspectorNodeJson?,
) -> RenderStateJson {
  {
    viewport: full.viewport,
    nodes: full.nodes.copy(),
    edges: full.edges.copy(),
    selected: full.selected,
    selected_edge: full.selected_edge,
    selected_nodes: full.selected_nodes.copy(),
    connecting: full.connecting,
    input_compatibility: full.input_compatibility.copy(),
    validation: full.validation.copy(),
    action_count: full.action_count,
    inspector,
  }
}

///|
fn CanvasHostPolicy::render_state_json(
  self : CanvasHostPolicy,
  state : CanvasState,
  validation : Array[ValidationJson],
  selected_edge : EdgeId?,
  input_compatibility : Array[PortCompatibilityJson],
) -> RenderStateJson {
  let selected : String? = match state.interaction.selected {
    None => None
    Some(id) => Some(node_id_to_string(id))
  }
  let selected_nodes = state.interaction.selected_nodes.map(node_id_to_string)
  let rendered_nodes = state.nodes.map(self.node_to_json)
  let node_index = edge_render_node_index(rendered_nodes)
  {
    viewport: state.viewport,
    nodes: rendered_nodes.copy(),
    edges: project_edge_renders(
      node_index,
      state.edges,
      selected_edge,
    ).map(edge_render_to_json),
    selected,
    selected_edge: match selected_edge {
      None => None
      Some(id) => Some(id.to_string())
    },
    selected_nodes,
    connecting: connecting_to_json_with_path(
      state.interaction.connecting,
      node_index,
    ),
    input_compatibility,
    validation,
    action_count: state.action_log.length(),
    inspector: None,
  }
}

///|
fn node_id_to_string(id : NodeId) -> String {
  id.to_string()
}

///|
fn node_to_json(n : CanvasNode) -> NodeJson {
  {
    id: n.id.to_string(),
    x: n.position().x(),
    y: n.position().y(),
    w: n.size().width(),
    h: n.size().height(),
    kind: n.kind,
    title: n.title,
    subtitle: n.subtitle,
    inputs: n.inputs,
    outputs: n.outputs,
    configured: n.configured,
    params: [],
  }
}

///|
fn input_has_edge(
  node : CanvasNode,
  input : PortDef,
  edges : Array[Edge],
) -> Bool {
  edges
  .iter()
  .any(fn(edge) { edge.target == node.id && edge.target_port == input.id })
}

///|
fn append_node_validation(
  messages : Array[ValidationJson],
  node : CanvasNode,
  edges : Array[Edge],
) -> Unit {
  let id = node.id.to_string()
  if !node.configured {
    messages.push({
      severity: "warning",
      message: "Configure “\{node.title}” before running the workflow.",
      node_id: Some(id),
    })
  }
  for input in node.inputs {
    if !input_has_edge(node, input, edges) {
      messages.push({
        severity: "warning",
        message: "“\{node.title}” is waiting for input “\{input.label}”.",
        node_id: Some(id),
      })
    }
  }
}

///|
fn validate_workflow_document(
  document : CanvasDocument,
) -> Array[ValidationJson] {
  let messages : Array[ValidationJson] = []
  if document.nodes.length() == 0 {
    messages.push({
      severity: "error",
      message: "Add at least one workflow node.",
      node_id: None,
    })
  }
  for node in document.nodes {
    append_node_validation(messages, node, document.edges)
  }
  messages
}

///|
fn workflow_inspector_node(
  document : CanvasDocument,
  node_id : NodeId,
) -> InspectorNodeJson? {
  match @graph_model.find_node(document.nodes, node_id) {
    None => None
    Some(node) =>
      Some({
        id: node_id.to_string(),
        title: node.title,
        subtitle: node.subtitle,
        configured: node.configured,
        input_count: node.inputs.length(),
        output_count: node.outputs.length(),
        source: "",
      })
  }
}

///|
fn render_state_json(
  state : CanvasState,
  validation : Array[ValidationJson],
  selected_edge : EdgeId?,
) -> RenderStateJson {
  workflow_canvas_host_policy().render_state_json(
    state,
    validation,
    selected_edge,
    input_compatibility_for_render_state(state),
  )
}

///|
fn render_state_string(
  state : CanvasState,
  validation : Array[ValidationJson],
) -> String {
  render_state_json(state, validation, None).to_json().stringify()
}
