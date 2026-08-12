///|
/// Local wire wrapper for the spatial viewport. MoonBit's orphan rule prevents
/// a graph-model package from implementing a core JSON trait directly for a
/// type owned by the spatial package. The manual object codec is intentional:
/// GraphOperation V2 requires the flat `{x, y, scale}` shape and field-specific
/// diagnostics at this boundary, while semantic construction stays explicit.
priv struct ViewportCodec(@spatial.Viewport)

///|
fn wire_finite_number(value : Double) -> Bool {
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
      guard wire_finite_number(number) else {
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
  fields["x"] = origin.x().to_json()
  fields["y"] = origin.y().to_json()
  fields["scale"] = viewport.scale().to_double().to_json()
  Json::object(fields)
}

///|
impl @json.FromJson for ViewportCodec with fn from_json(json, path) {
  let fields = match json {
    Json::Object(fields) => fields
    _ => raise @json.JsonDecodeError((path, "Viewport: expected JSON object"))
  }
  let x = viewport_codec_json_number_field(fields, path, "x")
  let y = viewport_codec_json_number_field(fields, path, "y")
  let origin = @spatial.ScreenPoint::from_xy(x~, y~) catch {
    @spatial.CoordinateError::NonFinite =>
      raise @json.JsonDecodeError(
        (path, "Viewport: origin coordinates must be finite"),
      )
  }
  let scale_number = viewport_codec_json_number_field(fields, path, "scale")
  let scale = @spatial.Scale::from_double(value=scale_number) catch {
    @spatial.ScaleError::NonFinite | @spatial.ScaleError::NonPositive =>
      raise @json.JsonDecodeError(
        (path.add_key("scale"), "Viewport: 'scale' must be finite and positive"),
      )
  }
  ViewportCodec(@spatial.Viewport::from_scale(origin~, scale~))
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
priv struct CanvasNodeWire {
  id : NodeId
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
} derive(ToJson, FromJson)

///|
priv struct NodePositionWire {
  node_id : NodeId
  x : Double
  y : Double
} derive(ToJson, FromJson)

///|
fn canvas_node_to_wire(node : CanvasNode) -> CanvasNodeWire {
  let position = node.position()
  let size = node.size()
  {
    id: node.id,
    x: position.x(),
    y: position.y(),
    w: size.width(),
    h: size.height(),
    kind: node.kind,
    title: node.title,
    subtitle: node.subtitle,
    inputs: node.inputs,
    outputs: node.outputs,
    configured: node.configured,
  }
}

///|
fn node_position_to_wire(position : NodePosition) -> NodePositionWire {
  { node_id: position.id, x: position.point.x(), y: position.point.y() }
}

///|
fn finite_wire_geometry_field(
  value : Double,
  path : @json.JsonPath,
  owner : String,
  key : String,
) -> Double raise @json.JsonDecodeError {
  guard wire_finite_number(value) else {
    raise @json.JsonDecodeError(
      (path.add_key(key), "\{owner}: '\{key}' must be finite"),
    )
  }
  value
}

///|
fn canvas_node_from_wire(
  wire : CanvasNodeWire,
  path : @json.JsonPath,
) -> CanvasNode raise @json.JsonDecodeError {
  let x = finite_wire_geometry_field(wire.x, path, "CanvasNode", "x")
  let y = finite_wire_geometry_field(wire.y, path, "CanvasNode", "y")
  let position = @spatial.WorldPoint::from_xy(x~, y~) catch {
    @spatial.CoordinateError::NonFinite =>
      raise @json.JsonDecodeError(
        (path, "CanvasNode: position coordinates must be finite"),
      )
  }
  let width = finite_wire_geometry_field(wire.w, path, "CanvasNode", "w")
  let height = finite_wire_geometry_field(wire.h, path, "CanvasNode", "h")
  let size = NodeSize::from_wh(width~, height~) catch {
    NodeSizeError::NonFiniteWidth =>
      raise @json.JsonDecodeError(
        (path.add_key("w"), "CanvasNode: 'w' must be finite"),
      )
    NodeSizeError::NonFiniteHeight =>
      raise @json.JsonDecodeError(
        (path.add_key("h"), "CanvasNode: 'h' must be finite"),
      )
    NodeSizeError::NegativeWidth =>
      raise @json.JsonDecodeError(
        (path.add_key("w"), "CanvasNode: 'w' must be non-negative"),
      )
    NodeSizeError::NegativeHeight =>
      raise @json.JsonDecodeError(
        (path.add_key("h"), "CanvasNode: 'h' must be non-negative"),
      )
  }
  CanvasNode::from_parts(
    id=wire.id,
    position~,
    size~,
    kind=wire.kind,
    title=wire.title,
    subtitle=wire.subtitle,
    inputs=wire.inputs,
    outputs=wire.outputs,
    configured=wire.configured,
  )
}

///|
fn node_position_from_wire(
  wire : NodePositionWire,
  path : @json.JsonPath,
) -> NodePosition raise @json.JsonDecodeError {
  let x = finite_wire_geometry_field(wire.x, path, "NodePosition", "x")
  let y = finite_wire_geometry_field(wire.y, path, "NodePosition", "y")
  let position = @spatial.WorldPoint::from_xy(x~, y~) catch {
    @spatial.CoordinateError::NonFinite =>
      raise @json.JsonDecodeError(
        (path, "NodePosition: coordinates must be finite"),
      )
  }
  @spatial.ItemPosition::from_id_and_point(id=wire.node_id, point=position)
}

///|
priv enum WorkflowActionJson {
  AddNode(CanvasNodeWire)
  MoveNodes(Array[NodePositionWire])
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
    AddNode(node) => WorkflowActionJson::AddNode(canvas_node_to_wire(node))
    MoveNodes(positions) =>
      WorkflowActionJson::MoveNodes(positions.map(node_position_to_wire))
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
