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
/// or "" for background. Dispatches to pan or drag start internally.
pub fn pointer_down(
  handle : Int,
  node_id : String,
  sx : Double,
  sy : Double,
) -> Unit {
  let id : NodeId? = if node_id == "" { None } else { Some(NodeId(node_id)) }
  _registry[handle].pointer_down(id, sx, sy)
}

///|
/// Pointer-down on an output handle: start an edge-creation gesture.
pub fn pointer_down_handle(
  handle : Int,
  node_id : String,
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
  node_id : String,
  target_port_id : String,
  additive : Bool,
) -> Unit {
  _registry[handle].pointer_up(node_id, target_port_id, additive)
}

///|
pub fn hover_node(handle : Int, node_id : String) -> Unit {
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
  source : String,
  source_port : String,
  target : String,
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
struct NodeParamJson {
  name : String
  value_kind : String
  value : String
  unit : String?
  editable : Bool
} derive(Eq, ToJson)

///|
/// Serializable node snapshot. Uses plain String for `id` to carry
/// the stable NodeId value across the JS boundary.
struct NodeJson {
  id : String
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
  params : Array[NodeParamJson]
} derive(Eq, ToJson)

///|
struct EdgeJson {
  id : String
  source : String
  source_port : String
  target : String
  target_port : String
} derive(Eq, ToJson)

///|
/// Serialized in-flight connection. `from` is the source node id;
/// `cursor_x`/`cursor_y` are world coordinates of the pointer.
struct ConnectingJson {
  from : String
  from_port : String
  cursor_x : Double
  cursor_y : Double
} derive(Eq, ToJson)

///|
struct ValidationJson {
  severity : String
  message : String
  node_id : String?
} derive(Eq, ToJson)

///|
struct InspectorNodeJson {
  id : String
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
  selected : String?
  selected_nodes : Array[String]
  connecting : ConnectingJson?
  validation : Array[ValidationJson]
  action_count : Int
  inspector : InspectorNodeJson?
} derive(Eq, ToJson)

///|
pub fn get_render_state(handle : Int) -> String {
  _registry[handle].render_state().to_json().stringify()
}

///|
pub fn get_action_log(handle : Int) -> String {
  _registry[handle].action_log_json()
}
