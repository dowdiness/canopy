///|
/// Global handle registry. Index = handle (Int returned by create_canvas).
let _registry : Array[CanvasRuntime] = []

///|
pub fn create_canvas() -> Int {
  _registry.push(CanvasRuntime::CanvasRuntime())
  _registry.length() - 1
}

///|
/// Handle pointer-down. `node_id` is the canvas node id under the pointer,
/// or 0 for background. Dispatches to pan or drag start internally.
pub fn pointer_down(
  handle : Int,
  node_id : Int,
  sx : Double,
  sy : Double,
) -> Unit {
  let id : NodeId? = if node_id <= 0 { None } else { Some(NodeId(node_id)) }
  _registry[handle].pointer_down(id, sx, sy)
}

///|
/// Pointer-down on an output handle: start an edge-creation gesture.
pub fn pointer_down_handle(
  handle : Int,
  node_id : Int,
  port_id : String,
  sx : Double,
  sy : Double,
) -> Unit {
  _registry[handle].pointer_down_handle(NodeId(node_id), port_id, sx, sy)
}

///|
/// Handle pointer-move in canvas-local screen coordinates.
/// Routes to the active gesture (pan, drag, or connect) internally.
pub fn pointer_move(handle : Int, sx : Double, sy : Double) -> Unit {
  _registry[handle].pointer_move(sx, sy)
}

///|
pub fn zoom(handle : Int, delta : Double, cx : Double, cy : Double) -> Unit {
  _registry[handle].zoom(delta, cx, cy)
}

///|
pub fn pointer_up(
  handle : Int,
  node_id : Int,
  target_port_id : String,
  additive : Bool,
) -> Unit {
  _registry[handle].pointer_up(node_id, target_port_id, additive)
}

///|
pub fn hover_node(handle : Int, node_id : Int) -> Unit {
  _registry[handle].hover_node(node_id)
}

///|
/// Add a workflow node from the library/context menu at canvas-local screen
/// coordinates. `kind_key` is intentionally string-based at the FFI boundary;
/// MoonBit converts it to an extensible `WorkflowNodeKind` inside the model.
pub fn add_node(
  handle : Int,
  kind_key : String,
  sx : Double,
  sy : Double,
) -> Unit {
  _registry[handle].add_node(kind_key, sx, sy)
}

///|
fn decode_node_ids(json_text : String) -> Array[NodeId] {
  let json = @json.parse(json_text) catch { _ => return [] }
  @json.from_json(json) catch {
    _ => []
  }
}

///|
pub fn delete_nodes(handle : Int, node_ids_json : String) -> Unit {
  let node_ids = decode_node_ids(node_ids_json)
  if node_ids.length() == 0 {
    return
  }
  _registry[handle].delete_nodes(node_ids)
}

///|
pub fn disconnect_ports(
  handle : Int,
  source : Int,
  source_port : String,
  target : Int,
  target_port : String,
) -> Unit {
  _registry[handle].disconnect_ports(
    NodeId(source),
    source_port,
    NodeId(target),
    target_port,
  )
}

///|
/// Serializable node snapshot. Uses plain Int for `id` to avoid
/// the NodeId newtype wrapper appearing in JSON output.
struct NodeJson {
  id : Int
  x : Double
  y : Double
  w : Double
  h : Double
  kind : NodeKind
  title : String
  subtitle : String
  inputs : Array[PortDef]
  outputs : Array[PortDef]
  configured : Bool
} derive(Eq, ToJson)

///|
struct EdgeJson {
  id : Int
  source : Int
  source_port : String
  target : Int
  target_port : String
} derive(Eq, ToJson)

///|
/// Serialized in-flight connection. `from` is the source node id;
/// `cursor_x`/`cursor_y` are world coordinates of the pointer.
struct ConnectingJson {
  from : Int
  from_port : String
  cursor_x : Double
  cursor_y : Double
} derive(Eq, ToJson)

///|
struct ValidationJson {
  severity : String
  message : String
  node_id : Int?
} derive(Eq, ToJson)

///|
struct InspectorNodeJson {
  id : Int
  title : String
  subtitle : String
  configured : Bool
  input_count : Int
  output_count : Int
  source : String
} derive(Eq, ToJson)

///|
/// Serializable render snapshot sent to TypeScript each RAF frame.
/// `selected`/`connecting`/`inspector` are absent (key omitted) when not active
/// — MoonBit derive(ToJson) omits None keys. TypeScript: use `!= null` checks.
struct RenderStateJson {
  viewport : Viewport
  nodes : Array[NodeJson]
  edges : Array[EdgeJson]
  selected : Int?
  selected_nodes : Array[Int]
  connecting : ConnectingJson?
  validation : Array[ValidationJson]
  action_count : Int
  inspector : InspectorNodeJson?
} derive(Eq, ToJson)

///|
fn node_id_to_int(id : NodeId) -> Int {
  let NodeId(n) = id
  n
}

///|
fn node_to_json(n : CanvasNode) -> NodeJson {
  let NodeId(id) = n.id
  {
    id,
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
  }
}

///|
fn edge_to_json(e : Edge) -> EdgeJson {
  let EdgeId(id) = e.id
  let NodeId(s) = e.source
  let NodeId(t) = e.target
  {
    id,
    source: s,
    source_port: e.source_port,
    target: t,
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
  let NodeId(id) = node.id
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
fn validate_workflow(state : CanvasState) -> Array[ValidationJson] {
  validate_workflow_document(canvas_document_from_state(state))
}

///|
fn render_state_json(
  state : CanvasState,
  validation : Array[ValidationJson],
) -> RenderStateJson {
  let selected : Int? = match state.interaction.selected {
    None => None
    Some(id) => Some(node_id_to_int(id))
  }
  let selected_nodes = state.interaction.selected_nodes.map(node_id_to_int)
  {
    viewport: state.viewport,
    nodes: state.nodes.map(node_to_json),
    edges: state.edges.map(edge_to_json),
    selected,
    selected_nodes,
    connecting: connecting_to_json(state.interaction.connecting),
    validation,
    action_count: state.action_log.length(),
    inspector: None,
  }
}

///|
fn render_state_string(
  state : CanvasState,
  validation : Array[ValidationJson],
) -> String {
  render_state_json(state, validation).to_json().stringify()
}

///|
pub fn get_render_state(handle : Int) -> String {
  _registry[handle].render_state().to_json().stringify()
}

///|
pub fn get_action_log(handle : Int) -> String {
  _registry[handle].action_log_json()
}
