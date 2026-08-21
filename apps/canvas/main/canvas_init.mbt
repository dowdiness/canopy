///|
/// Global handle registry. Index = handle (Int returned by create_canvas).
let _registry : Array[CanvasRuntime] = []

///|
pub fn create_canvas() -> Int {
  _registry.push(CanvasRuntime::CanvasRuntime())
  _registry.length() - 1
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
pub fn clear_selected_edge(handle : Int) -> Unit {
  _registry[handle].clear_selected_edge()
}

///|
pub fn delete_selection(handle : Int) -> Bool {
  _registry[handle].delete_selection()
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
struct NodeParamJson {
  name : String
  value_kind : String
  value : String
  unit : String?
  editable : Bool
} derive(Eq, ToJson, FromJson)

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
} derive(Eq, ToJson, FromJson)

///|
struct EdgeJson {
  id : String
  path_d : String
  selected : Bool
  aria_label : String
} derive(Eq, ToJson, FromJson)

///|
/// Serialized in-flight connection. `from` is the source node id;
/// `cursor_x`/`cursor_y` are finite world coordinates of the pointer.
struct ConnectingJson {
  from : String
  from_port : String
  cursor_x : Double
  cursor_y : Double
  path_d : String?
} derive(Eq, ToJson, FromJson)

///|
struct PortCompatibilityJson {
  node_id : String
  port_id : String
  compatible : Bool
} derive(Eq, ToJson, FromJson)

///|
struct ValidationJson {
  severity : String
  message : String
  node_id : String?
} derive(Eq, ToJson, FromJson)

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
fn render_viewport_to_json(viewport : Viewport) -> Json {
  let origin = viewport.screen_origin()
  let fields : Map[String, Json] = Map([])
  fields["x"] = origin.x().to_json()
  fields["y"] = origin.y().to_json()
  fields["scale"] = viewport.scale().to_double().to_json()
  Json::object(fields)
}

///|
/// Serializable render snapshot sent to TypeScript each RAF frame.
/// `selected`/`selected_edge`/`connecting`/`inspector` are absent (key omitted)
/// when not active — MoonBit derive(ToJson) omits None keys. TypeScript: use `!= null` checks.
/// `input_compatibility` is always present and is empty when no connection is active.
struct RenderStateJson {
  viewport : Viewport
  nodes : Array[NodeJson]
  edges : Array[EdgeJson]
  selected : String?
  selected_edge : String?
  selected_nodes : Array[String]
  connecting : ConnectingJson?
  input_compatibility : Array[PortCompatibilityJson]
  validation : Array[ValidationJson]
  action_count : Int
  inspector : InspectorNodeJson?
} derive(Eq)

///|
impl ToJson for RenderStateJson with fn to_json(self) {
  let fields : Map[String, Json] = Map([])
  fields["viewport"] = render_viewport_to_json(self.viewport)
  fields["nodes"] = self.nodes.to_json()
  fields["edges"] = self.edges.to_json()
  match self.selected {
    None => ()
    Some(selected) => fields["selected"] = selected.to_json()
  }
  match self.selected_edge {
    None => ()
    Some(selected_edge) => fields["selected_edge"] = selected_edge.to_json()
  }
  fields["selected_nodes"] = self.selected_nodes.to_json()
  match self.connecting {
    None => ()
    Some(connecting) => fields["connecting"] = connecting.to_json()
  }
  fields["input_compatibility"] = self.input_compatibility.to_json()
  fields["validation"] = self.validation.to_json()
  fields["action_count"] = self.action_count.to_json()
  match self.inspector {
    None => ()
    Some(inspector) => fields["inspector"] = inspector.to_json()
  }
  Json::object(fields)
}

///|
extend RenderStateJson with ToJson::{to_json}

///|
pub fn get_render_state(handle : Int) -> String {
  _registry[handle].render_state().to_json().stringify()
}

///|
pub fn get_action_log(handle : Int) -> String {
  _registry[handle].action_log_json()
}
