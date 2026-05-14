///|
/// Opaque integer ID for canvas nodes.
/// Uses tuple-struct pattern from projection/types.mbt.
pub struct NodeId(Int) derive(Debug, Eq, ToJson)

///|
pub impl Show for NodeId with output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
/// Visual kind of a node.
pub enum NodeKind {
  /// Filled rectangle. `color` is a CSS color string (e.g. "#8250df").
  Shape(String)
  /// Text label. `content` is the displayed string.
  Text(String)
} derive(Debug, Eq, ToJson)

///|
pub impl Show for NodeKind with output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
/// Pan and zoom state of the canvas viewport.
/// `x` and `y` are the world origin in canvas-local screen space.
pub(all) struct Viewport {
  x : Double
  y : Double
  scale : Double
} derive(Debug, Eq, ToJson)

///|
pub impl Show for Viewport with output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
/// A single node on the canvas. Coordinates are in world space.
pub(all) struct CanvasNode {
  id : NodeId
  x : Double
  y : Double
  w : Double
  h : Double
  kind : NodeKind
} derive(Debug, Eq)

///|
pub impl Show for CanvasNode with output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
/// State captured at the start of a node drag gesture.
pub(all) struct DragState {
  node_id : NodeId
  /// Offset from cursor world position to node origin (node.x - cursor.x at drag start).
  offset_x : Double
  offset_y : Double
} derive(Debug, Eq)

///|
pub impl Show for DragState with output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
/// State captured at the start of a pan gesture.
pub(all) struct PanState {
  start_screen_x : Double
  start_screen_y : Double
  start_pan_x : Double
  start_pan_y : Double
} derive(Debug, Eq)

///|
pub impl Show for PanState with output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
pub struct EdgeId(Int) derive(Debug, Eq, ToJson)

///|
pub impl Show for EdgeId with output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
/// A connection between two nodes. Each node has an implicit single output
/// handle (right-center) and input handle (left-center), so handles are not
/// stored explicitly in the prototype.
pub(all) struct Edge {
  id : EdgeId
  source : NodeId
  target : NodeId
} derive(Debug, Eq, ToJson)

///|
pub impl Show for Edge with output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
/// In-flight connection started from a node's output handle.
/// `cursor_x`/`cursor_y` are world coordinates of the pointer.
pub(all) struct ConnectState {
  from_node : NodeId
  cursor_x : Double
  cursor_y : Double
} derive(Debug, Eq)

///|
pub impl Show for ConnectState with output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
pub(all) struct InteractionState {
  dragging : DragState?
  panning : PanState?
  connecting : ConnectState?
  selected : NodeId?
  /// True from pointerdown until pointerup.
  pointer_down : Bool
  /// True once pointermove fires during the current pointer session.
  did_move : Bool
} derive(Debug, Eq)

///|
pub impl Show for InteractionState with output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
pub(all) struct CanvasState {
  viewport : Viewport
  nodes : Array[CanvasNode]
  edges : Array[Edge]
  /// Monotonic counter used to mint EdgeIds for newly-created connections.
  next_edge_id : Int
  interaction : InteractionState
} derive(Debug)

///|
pub impl Show for CanvasState with output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
/// Default state centers the world origin in a 1440×800 browser viewport
/// and seeds six demo nodes.
pub impl Default for CanvasState with default() -> CanvasState {
  {
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
    edges: [
      { id: EdgeId(1), source: NodeId(1), target: NodeId(4) },
      { id: EdgeId(2), source: NodeId(2), target: NodeId(5) },
      { id: EdgeId(3), source: NodeId(3), target: NodeId(6) },
    ],
    next_edge_id: 4,
    interaction: {
      dragging: None,
      panning: None,
      connecting: None,
      selected: None,
      pointer_down: false,
      did_move: false,
    },
  }
}
