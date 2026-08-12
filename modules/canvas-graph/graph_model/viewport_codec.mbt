///|
/// Local wire wrapper for the spatial viewport. MoonBit's orphan rule prevents
/// a graph-model package from implementing a core JSON trait directly for a
/// type owned by the spatial package.
priv struct ViewportCodec(@spatial.Viewport)

///|
fn viewport_codec_finite_number(value : Double) -> Bool {
  !value.is_nan() && !value.is_inf()
}

///|
fn viewport_codec_json_number_field(
  fields : Map[String, Json],
  path : @json.JsonPath,
  key : String,
) -> Double raise @json.JsonDecodeError {
  match fields.get(key) {
    Some(Json::Number(number, ..)) => {
      guard viewport_codec_finite_number(number) else {
        raise @json.JsonDecodeError(
          (path.add_key(key), "Viewport: '\{key}' must be finite"),
        )
      }
      number
    }
    _ =>
      raise @json.JsonDecodeError(
        (path.add_key(key), "Viewport: '\{key}' must be a number"),
      )
  }
}

///|
impl ToJson for ViewportCodec with fn to_json(self) {
  let ViewportCodec(viewport) = self
  let origin = viewport.screen_origin()
  let fields : Map[String, Json] = Map([])
  fields["x"] = origin.x.to_json()
  fields["y"] = origin.y.to_json()
  fields["scale"] = viewport.scale().to_json()
  Json::object(fields)
}

///|
impl @json.FromJson for ViewportCodec with fn from_json(json, path) {
  let fields = match json {
    Json::Object(fields) => fields
    _ => raise @json.JsonDecodeError((path, "Viewport: expected JSON object"))
  }
  let origin = @spatial.ScreenPoint::from_xy(
    x=viewport_codec_json_number_field(fields, path, "x"),
    y=viewport_codec_json_number_field(fields, path, "y"),
  )
  let scale = viewport_codec_json_number_field(fields, path, "scale")
  let viewport = @spatial.Viewport::from_scale(origin~, scale~) catch {
    @spatial.ViewportError::InvalidOrigin =>
      raise @json.JsonDecodeError(
        (path, "Viewport: origin coordinates must be finite"),
      )
    @spatial.ViewportError::InvalidScale =>
      raise @json.JsonDecodeError(
        (path.add_key("scale"), "Viewport: 'scale' must be finite and positive"),
      )
  }
  ViewportCodec(viewport)
}

///|
fn viewport_to_json(viewport : @spatial.Viewport) -> Json {
  ToJson::to_json(ViewportCodec(viewport))
}

///|
fn viewport_from_json(
  json : Json,
  path : @json.JsonPath,
) -> @spatial.Viewport raise @json.JsonDecodeError {
  let ViewportCodec(viewport) : ViewportCodec = @json.from_json(json, path~)
  viewport
}

///|
priv enum WorkflowActionJson {
  AddNode(CanvasNode)
  MoveNodes(Array[NodePosition])
  ConnectPorts(NodeId, String, NodeId, String)
  DisconnectPorts(NodeId, String, NodeId, String)
  DeleteNodes(Array[NodeId])
  RenameNode(NodeId, String)
  SetNodeParam(NodeId, String, String)
  SelectNodes(Array[NodeId])
  SetViewport(ViewportCodec)
} derive(ToJson)

///|
pub impl ToJson for WorkflowAction with fn to_json(self) {
  let encoded : WorkflowActionJson = match self {
    AddNode(node) => WorkflowActionJson::AddNode(node)
    MoveNodes(positions) => WorkflowActionJson::MoveNodes(positions)
    ConnectPorts(source, source_port, target, target_port) =>
      WorkflowActionJson::ConnectPorts(source, source_port, target, target_port)
    DisconnectPorts(source, source_port, target, target_port) =>
      WorkflowActionJson::DisconnectPorts(
        source, source_port, target, target_port,
      )
    DeleteNodes(nodes) => WorkflowActionJson::DeleteNodes(nodes)
    RenameNode(node_id, name) => WorkflowActionJson::RenameNode(node_id, name)
    SetNodeParam(node_id, parameter, value) =>
      WorkflowActionJson::SetNodeParam(node_id, parameter, value)
    SelectNodes(nodes) => WorkflowActionJson::SelectNodes(nodes)
    SetViewport(viewport) =>
      WorkflowActionJson::SetViewport(ViewportCodec(viewport))
  }
  ToJson::to_json(encoded)
}
