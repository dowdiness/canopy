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
  edge_to_json : (Edge) -> EdgeJson
  inspector_node : (CanvasDocument, NodeId) -> InspectorNodeJson?
  selected_inspector_source : String
  hovered_inspector_source : String
  add_node : (CanvasState, String, Double, Double) -> CanvasState
}

///|
fn CanvasHostPolicy::CanvasHostPolicy(
  initial_state~ : () -> CanvasState,
  validate_document~ : (CanvasDocument) -> Array[ValidationJson],
  node_to_json~ : (CanvasNode) -> NodeJson,
  edge_to_json~ : (Edge) -> EdgeJson,
  inspector_node~ : (CanvasDocument, NodeId) -> InspectorNodeJson?,
  selected_inspector_source~ : String,
  hovered_inspector_source~ : String,
  add_node~ : (CanvasState, String, Double, Double) -> CanvasState,
) -> CanvasHostPolicy {
  {
    initial_state,
    validate_document,
    node_to_json,
    edge_to_json,
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
    edge_to_json~,
    inspector_node=workflow_inspector_node,
    selected_inspector_source="selected",
    hovered_inspector_source="hovered",
    add_node=(state, kind_key, world_x, world_y) => {
      @graph_model.workflow_add_node(state, kind_key, world_x, world_y)
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
    edges: normalized.document.edges.map(self.edge_to_json),
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
    Some(pos) => { ..node, x: pos.x, y: pos.y }
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
        cursor_x: c.cursor_x,
        cursor_y: c.cursor_y,
      })
    }
  }
}

///|
fn CanvasHostPolicy::render_full_canvas(
  _self : CanvasHostPolicy,
  lowered : LoweredCanvas,
  viewport : Viewport,
  drag_preview : DragPreview,
  selection : SelectionState,
  interaction : InteractionState,
  action_count : Int,
) -> CanvasFullRenderJson {
  let selected : String? = match selection.selected {
    None => None
    Some(id) => Some(node_id_to_string(id))
  }
  let selected_nodes = selection.selected_nodes.map(node_id_to_string)
  {
    viewport,
    nodes: lowered.nodes.map(fn(node) {
      render_node_with_preview(node, drag_preview)
    }),
    edges: lowered.edges.copy(),
    selected,
    selected_nodes,
    connecting: connecting_to_json(interaction.connecting),
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
    selected_nodes: full.selected_nodes.copy(),
    connecting: full.connecting,
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
) -> RenderStateJson {
  let selected : String? = match state.interaction.selected {
    None => None
    Some(id) => Some(node_id_to_string(id))
  }
  let selected_nodes = state.interaction.selected_nodes.map(node_id_to_string)
  {
    viewport: state.viewport,
    nodes: state.nodes.map(self.node_to_json),
    edges: state.edges.map(self.edge_to_json),
    selected,
    selected_nodes,
    connecting: connecting_to_json(state.interaction.connecting),
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
    x: n.x,
    y: n.y,
    w: n.w,
    h: n.h,
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
fn edge_to_json(e : Edge) -> EdgeJson {
  {
    id: e.id.to_string(),
    source: e.source.to_string(),
    source_port: e.source_port,
    target: e.target.to_string(),
    target_port: e.target_port,
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
) -> RenderStateJson {
  workflow_canvas_host_policy().render_state_json(state, validation)
}

///|
fn render_state_string(
  state : CanvasState,
  validation : Array[ValidationJson],
) -> String {
  render_state_json(state, validation).to_json().stringify()
}
