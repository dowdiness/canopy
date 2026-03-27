///|
/// Global handle registry. Index = handle (Int returned by create_canvas).
let _registry : Array[CanvasState] = []

///|
fn make_initial_state() -> CanvasState {
  {
    // Center the world origin roughly in a 1440×800 browser viewport
    viewport: { x: 520.0, y: 300.0, scale: 1.0 },
    nodes: [
      {
        id: NodeId(1),
        x: -320.0,
        y: -160.0,
        w: 200.0,
        h: 120.0,
        kind: NodeKind::Shape("#8250df"),
      },
      {
        id: NodeId(2),
        x: -60.0,
        y: -160.0,
        w: 200.0,
        h: 120.0,
        kind: NodeKind::Shape("#c792ea"),
      },
      {
        id: NodeId(3),
        x: 200.0,
        y: -160.0,
        w: 200.0,
        h: 120.0,
        kind: NodeKind::Shape("#82aaff"),
      },
      {
        id: NodeId(4),
        x: -320.0,
        y: 20.0,
        w: 200.0,
        h: 60.0,
        kind: NodeKind::Text("Canopy Canvas"),
      },
      {
        id: NodeId(5),
        x: -60.0,
        y: 20.0,
        w: 200.0,
        h: 60.0,
        kind: NodeKind::Text("Pan · Zoom · Drag"),
      },
      {
        id: NodeId(6),
        x: 200.0,
        y: 20.0,
        w: 200.0,
        h: 60.0,
        kind: NodeKind::Text("∞"),
      },
    ],
    interaction: {
      dragging: None,
      panning: None,
      selected: None,
      pointer_down: false,
      did_move: false,
    },
  }
}

///|
pub fn create_canvas() -> Int {
  _registry.push(make_initial_state())
  _registry.length() - 1
}

///|
pub fn pan_start(handle : Int, sx : Double, sy : Double) -> Unit {
  _registry[handle] = update_pan_start(_registry[handle], sx, sy)
}

///|
pub fn pan_move(handle : Int, sx : Double, sy : Double) -> Unit {
  _registry[handle] = update_pan_move(_registry[handle], sx, sy)
}

///|
pub fn zoom(handle : Int, delta : Double, cx : Double, cy : Double) -> Unit {
  _registry[handle] = update_zoom(_registry[handle], delta, cx, cy)
}

///|
pub fn node_drag_start(
  handle : Int,
  node_id : Int,
  world_x : Double,
  world_y : Double
) -> Unit {
  _registry[handle] = update_node_drag_start(
    _registry[handle], NodeId(node_id), world_x, world_y,
  )
}

///|
pub fn node_drag_move(handle : Int, world_x : Double, world_y : Double) -> Unit {
  _registry[handle] = update_node_drag_move(_registry[handle], world_x, world_y)
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
/// `selected` is null (None) when no node is selected.
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
  rs.to_json().to_string()
}
