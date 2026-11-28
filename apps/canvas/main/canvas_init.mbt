///|
pub fn create_canvas() -> Int32 {
  let handle = canvas_instances.length()
  canvas_instances.push(Some(Runtime(CanvasRuntime::CanvasRuntime())))
  handle
}

///|
/// App-private handle operation retained for backing-contract tests.
/// UI insertion uses the typed library/context path; this is not a JS export.
pub fn add_node(
  handle : Int32,
  kind_key : String,
  sx : Double,
  sy : Double,
) -> Unit {
  match canvas_runtime_for_public(handle) {
    Some(runtime) => runtime.add_node(kind_key, sx, sy)
    None => ()
  }
}

///|
#derive(Eq, ToJson, FromJson)
struct NodeParamJson {
  name : String
  value_kind : String
  value : String
  unit : String?
  editable : Bool
}

///|
/// Serializable node snapshot. Uses plain String for `id` to carry
/// the stable NodeId value across the JS boundary.
#derive(Eq, ToJson, FromJson)
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
}

///|
#derive(Eq, ToJson, FromJson)
struct EdgeJson {
  id : String
  path_d : String
  selected : Bool
  aria_label : String
}

///|
/// Serialized in-flight connection. `from` is the source node id;
/// `cursor_x`/`cursor_y` are finite world coordinates of the pointer.
#derive(Eq, ToJson, FromJson)
struct ConnectingJson {
  from : String
  from_port : String
  cursor_x : Double
  cursor_y : Double
  path_d : String?
}

///|
#derive(Eq, ToJson, FromJson)
struct PortCompatibilityJson {
  node_id : String
  port_id : String
  compatible : Bool
}

///|
#derive(Eq, ToJson, FromJson)
struct ValidationJson {
  severity : String
  message : String
  node_id : String?
}

///|
#derive(Eq, ToJson, FromJson)
struct InspectorNodeJson {
  id : String
  title : String
  subtitle : String
  configured : Bool
  input_count : Int32
  output_count : Int32
  source : String
}

///|
fn render_viewport_to_json(viewport : Viewport) -> Json {
  let origin = viewport.screen_origin()
  let fields : Map[String, Json] = Map([])
  fields["x"] = Json(origin.x())
  fields["y"] = Json(origin.y())
  fields["scale"] = Json(viewport.scale().to_double())
  Json::object(fields)
}

///|
/// Serializable render snapshot sent to TypeScript each RAF frame.
/// `selected`/`selected_edge`/`connecting`/`inspector` are absent (key omitted)
/// when not active — MoonBit derive(ToJson) omits None keys. TypeScript: use `!= null` checks.
/// `input_compatibility` is always present and is empty when no connection is active.
#derive(Eq)
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
  action_count : Int32
  inspector : InspectorNodeJson?
}

///|
impl ToJson for RenderStateJson with fn to_json(self) {
  let fields : Map[String, Json] = Map([])
  fields["viewport"] = render_viewport_to_json(self.viewport)
  fields["nodes"] = Json(self.nodes)
  fields["edges"] = Json(self.edges)
  match self.selected {
    None => ()
    Some(selected) => fields["selected"] = Json(selected)
  }
  match self.selected_edge {
    None => ()
    Some(selected_edge) => fields["selected_edge"] = Json(selected_edge)
  }
  fields["selected_nodes"] = Json(self.selected_nodes)
  match self.connecting {
    None => ()
    Some(connecting) => fields["connecting"] = ToJson::to_json(connecting)
  }
  fields["input_compatibility"] = Json(self.input_compatibility)
  fields["validation"] = Json(self.validation)
  fields["action_count"] = Json(self.action_count)
  match self.inspector {
    None => ()
    Some(inspector) => fields["inspector"] = ToJson::to_json(inspector)
  }
  Json::object(fields)
}

///|
extend RenderStateJson with ToJson::{to_json}

///|
pub fn get_render_state(handle : Int32) -> String {
  match canvas_runtime_for_public(handle) {
    Some(runtime) => runtime.render_state().to_json().stringify()
    None => ""
  }
}

///|
pub fn get_action_log(handle : Int32) -> String {
  match canvas_runtime_for_public(handle) {
    Some(runtime) => runtime.action_log_json()
    None => Json(([] : Array[GraphOperation])).stringify()
  }
}
