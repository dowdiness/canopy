///|
/// Global handle registry. Index = handle (Int returned by create_canvas).
let _registry : Array[CanvasState] = []

///|
pub fn create_canvas() -> Int {
  _registry.push(CanvasState::default())
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
  _registry[handle] = update_pointer_down(_registry[handle], id, sx, sy)
}

///|
/// Handle pointer-move in canvas-local screen coordinates.
/// Routes to the active gesture (pan or drag) internally.
pub fn pointer_move(handle : Int, sx : Double, sy : Double) -> Unit {
  _registry[handle] = update_pointer_move(_registry[handle], sx, sy)
}

///|
pub fn zoom(handle : Int, delta : Double, cx : Double, cy : Double) -> Unit {
  _registry[handle] = update_zoom(_registry[handle], delta, cx, cy)
}

///|
pub fn pointer_up(handle : Int, node_id : Int) -> Unit {
  _registry[handle] = update_pointer_up(_registry[handle], node_id)
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
} derive(ToJson)

///|
/// Serializable render snapshot sent to TypeScript each RAF frame.
/// `selected` is absent (key omitted) when no node is selected — MoonBit derive(ToJson) omits None keys.
/// TypeScript: use `rs.selected != null` (loose equality) not `rs.selected !== null`.
struct RenderStateJson {
  viewport : Viewport
  nodes : Array[NodeJson]
  selected : Int?
} derive(ToJson)

///|
pub fn get_render_state(handle : Int) -> String {
  let state = _registry[handle]
  let selected : Int? = match state.interaction.selected {
    None => None
    Some(NodeId(id)) => Some(id)
  }
  let nodes = state.nodes.map(fn(n) {
    let NodeId(id) = n.id
    ({ id, x: n.x, y: n.y, w: n.w, h: n.h, kind: n.kind } : NodeJson)
  })
  let rs : RenderStateJson = { viewport: state.viewport, nodes, selected }
  rs.to_json().stringify()
}
