///|
/// Opaque integer ID for canvas nodes.
/// Uses tuple-struct pattern from projection/types.mbt.
pub struct NodeId(Int) derive(Show, Eq, ToJson)

///|
/// Visual kind of a node.
pub enum NodeKind {
  /// Filled rectangle. `color` is a CSS color string (e.g. "#8250df").
  Shape(String)
  /// Text label. `content` is the displayed string.
  Text(String)
} derive(Show, Eq, ToJson)

///|
/// Pan and zoom state of the canvas viewport.
/// `x` and `y` are the world origin in canvas-local screen space.
pub(all) struct Viewport {
  x : Double
  y : Double
  scale : Double
} derive(Show, Eq, ToJson)

///|
/// A single node on the canvas. Coordinates are in world space.
pub(all) struct CanvasNode {
  id : NodeId
  x : Double
  y : Double
  w : Double
  h : Double
  kind : NodeKind
} derive(Show, Eq)

///|
/// State captured at the start of a node drag gesture.
pub(all) struct DragState {
  node_id : NodeId
  /// Offset from cursor world position to node origin (node.x - cursor.x at drag start).
  offset_x : Double
  offset_y : Double
} derive(Show, Eq)

///|
/// State captured at the start of a pan gesture.
pub(all) struct PanState {
  start_screen_x : Double
  start_screen_y : Double
  start_pan_x : Double
  start_pan_y : Double
} derive(Show, Eq)

///|
pub(all) struct InteractionState {
  dragging : DragState?
  panning : PanState?
  selected : NodeId?
  /// True from pointerdown until pointerup.
  pointer_down : Bool
  /// True once pointermove fires during the current pointer session.
  did_move : Bool
} derive(Show, Eq)

///|
pub(all) struct CanvasState {
  viewport : Viewport
  nodes : Array[CanvasNode]
  interaction : InteractionState
} derive(Show)

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
    interaction: {
      dragging: None,
      panning: None,
      selected: None,
      pointer_down: false,
      did_move: false,
    },
  }
}
