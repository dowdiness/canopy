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
/// Pointer-down on an output handle: start an edge-creation gesture.
pub fn pointer_down_handle(
  handle : Int,
  node_id : Int,
  sx : Double,
  sy : Double,
) -> Unit {
  let state = _registry[handle]
  let (wx, wy) = screen_to_world(state.viewport, sx, sy)
  _registry[handle] = update_connect_start(state, NodeId(node_id), wx, wy)
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
struct EdgeJson {
  id : Int
  source : Int
  target : Int
} derive(ToJson)

///|
/// Serialized in-flight connection. `from` is the source node id;
/// `cursor_x`/`cursor_y` are world coordinates of the pointer.
struct ConnectingJson {
  from : Int
  cursor_x : Double
  cursor_y : Double
} derive(ToJson)

///|
/// Serializable render snapshot sent to TypeScript each RAF frame.
/// `selected`/`connecting` are absent (key omitted) when not active — MoonBit derive(ToJson) omits None keys.
/// TypeScript: use `rs.selected != null` (loose equality) not `rs.selected !== null`.
struct RenderStateJson {
  viewport : Viewport
  nodes : Array[NodeJson]
  edges : Array[EdgeJson]
  selected : Int?
  connecting : ConnectingJson?
} derive(ToJson)

///|
pub fn get_render_state(handle : Int) -> String {
  let state = _registry[handle]
  let selected : Int? = match state.interaction.selected {
    None => None
    Some(NodeId(id)) => Some(id)
  }
  let connecting : ConnectingJson? = match state.interaction.connecting {
    None => None
    Some(c) => {
      let NodeId(from) = c.from_node
      Some({ from, cursor_x: c.cursor_x, cursor_y: c.cursor_y })
    }
  }
  let nodes = state.nodes.map(fn(n) {
    let NodeId(id) = n.id
    ({ id, x: n.x, y: n.y, w: n.w, h: n.h, kind: n.kind } : NodeJson)
  })
  let edges = state.edges.map(fn(e) {
    let EdgeId(id) = e.id
    let NodeId(s) = e.source
    let NodeId(t) = e.target
    ({ id, source: s, target: t } : EdgeJson)
  })
  let rs : RenderStateJson = {
    viewport: state.viewport,
    nodes,
    edges,
    selected,
    connecting,
  }
  rs.to_json().stringify()
}
