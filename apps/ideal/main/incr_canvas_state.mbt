///|
const INCR_CANVAS_NODE_WIDTH : Double = 150.0

///|
const INCR_CANVAS_NODE_HEIGHT : Double = 44.0

///|
const INCR_CANVAS_GRID_COLUMNS : Int = 4

///|
const INCR_CANVAS_GRID_X : Double = 190.0

///|
const INCR_CANVAS_GRID_Y : Double = 90.0

///|
const INCR_CANVAS_ORIGIN_X : Double = 260.0

///|
const INCR_CANVAS_ORIGIN_Y : Double = 42.0

///|
const INCR_CANVAS_MIN_SCALE : Double = 0.25

///|
const INCR_CANVAS_MAX_SCALE : Double = 4.0

///|
struct IncrCanvasState {
  viewport : @spatial.Viewport
  panning : @spatial.Pan?
  dragging : @spatial.Drag[@incr.CellId]?
  positions : Map[@incr.CellId, @spatial.WorldPoint]
  selected : Array[@incr.CellId]
  snapshot_key : (Int, Int, Int)
  active_pointer_id : Int?
} derive(Eq)

///|
fn IncrCanvasState::empty() -> IncrCanvasState {
  let origin = try! @spatial.ScreenPoint::from_xy(
    x=INCR_CANVAS_ORIGIN_X,
    y=INCR_CANVAS_ORIGIN_Y,
  )
  let scale = try! @spatial.Scale::from_double(value=1.0)
  {
    viewport: @spatial.Viewport::from_scale(origin~, scale~),
    panning: None,
    dragging: None,
    positions: Map([]),
    selected: [],
    snapshot_key: (-1, -1, -1),
    active_pointer_id: None,
  }
}

///|
fn incr_canvas_initial_position(index : Int) -> @spatial.WorldPoint {
  let column = index % INCR_CANVAS_GRID_COLUMNS
  let row = index / INCR_CANVAS_GRID_COLUMNS
  try! @spatial.WorldPoint::from_xy(
    x=column.to_double() * INCR_CANVAS_GRID_X,
    y=row.to_double() * INCR_CANVAS_GRID_Y,
  )
}

///|
/// Reconcile local layout against the live CellId frontier.
///
/// Existing positions are intentionally retained by identity. New cells use a
/// deterministic grid position, while cells absent from the frontier are
/// removed from the local layout.
fn reconcile_incr_positions(
  nodes : Array[@incr.CellId],
  existing : Map[@incr.CellId, @spatial.WorldPoint],
) -> Map[@incr.CellId, @spatial.WorldPoint] {
  let positions : Map[@incr.CellId, @spatial.WorldPoint] = Map([])
  for index, id in nodes {
    let point = existing
      .get(id)
      .unwrap_or_else(() => incr_canvas_initial_position(index))
    positions[id] = point
  }
  positions
}

///|
fn reconcile_incr_selection(
  selected : Array[@incr.CellId],
  nodes : Array[@incr.CellId],
) -> Array[@incr.CellId] {
  let live : Set[@incr.CellId] = Set(nodes[:])
  selected.filter(id => live.contains(id))
}

///|
fn reconcile_incr_canvas(
  state : IncrCanvasState,
  snapshot : @visualizer.RecomputeSnapshot,
) -> IncrCanvasState {
  let nodes = snapshot.nodes.map(node => node.id)
  {
    ..state,
    panning: None,
    dragging: None,
    positions: reconcile_incr_positions(nodes, state.positions),
    selected: reconcile_incr_selection(state.selected, nodes),
    active_pointer_id: None,
  }
}

///|
fn incr_canvas_world_positions(
  state : IncrCanvasState,
) -> Array[@spatial.ItemPosition[@incr.CellId]] {
  state.selected.filter_map(id => {
    state.positions
    .get(id)
    .map(point => @spatial.ItemPosition::from_id_and_point(id~, point~))
  })
}

///|
fn incr_canvas_screen_point(x : Double, y : Double) -> @spatial.ScreenPoint? {
  try @spatial.ScreenPoint::from_xy(x~, y~) catch {
    @spatial.CoordinateError::NonFinite => None
  } noraise {
    point => Some(point)
  }
}

///|
fn incr_canvas_node_contains(
  state : IncrCanvasState,
  id : @incr.CellId,
  screen : @spatial.ScreenPoint,
) -> Bool {
  match state.positions.get(id) {
    Some(world) => {
      let center = state.viewport.world_to_screen(world) catch {
        @spatial.CoordinateError::NonFinite => return false
      }
      (screen.x() - center.x()).abs() <= INCR_CANVAS_NODE_WIDTH / 2.0 &&
      (screen.y() - center.y()).abs() <= INCR_CANVAS_NODE_HEIGHT / 2.0
    }
    None => false
  }
}

///|
fn incr_canvas_hit_test(
  state : IncrCanvasState,
  snapshot : @visualizer.RecomputeSnapshot,
  screen : @spatial.ScreenPoint,
) -> @incr.CellId? {
  let nodes = snapshot.nodes.rev()
  nodes
  .search_by(node => incr_canvas_node_contains(state, node.id, screen))
  .map(index => nodes[index].id)
}

///|
fn incr_canvas_pointer_admitted(
  state : IncrCanvasState,
  pointer_id : Int?,
) -> Bool {
  state.active_pointer_id is None && pointer_id is Some(_)
}

///|
fn incr_canvas_pointer_down(
  state : IncrCanvasState,
  snapshot : @visualizer.RecomputeSnapshot,
  x : Double,
  y : Double,
  pointer_id : Int?,
) -> IncrCanvasState {
  guard incr_canvas_pointer_admitted(state, pointer_id) else { return state }
  let screen = match incr_canvas_screen_point(x, y) {
    Some(point) => point
    None => return state
  }
  match incr_canvas_hit_test(state, snapshot, screen) {
    Some(id) => {
      let selected = if state.selected.contains(id) {
        state.selected
      } else {
        [id]
      }
      let positions = { ..state, selected, }
      let items = incr_canvas_world_positions(positions)
      guard items.length() > 0 else { return state }
      let world = state.viewport.screen_to_world(screen) catch {
        @spatial.CoordinateError::NonFinite => return state
      }
      let drag = @spatial.Drag::start(
        positions=ReadOnlyArray::from_array(items[:]),
        pointer=world,
      )
      {
        ..positions,
        panning: None,
        dragging: Some(drag),
        active_pointer_id: pointer_id,
      }
    }
    None =>
      {
        ..state,
        selected: [],
        panning: Some(
          @spatial.Pan::start(viewport=state.viewport, pointer=screen),
        ),
        dragging: None,
        active_pointer_id: pointer_id,
      }
  }
}

///|
fn incr_canvas_pointer_move(
  state : IncrCanvasState,
  x : Double,
  y : Double,
  pointer_id : Int?,
) -> IncrCanvasState {
  guard state.active_pointer_id == pointer_id else { return state }
  let screen = match incr_canvas_screen_point(x, y) {
    Some(point) => point
    None => return state
  }
  match (state.dragging, state.panning) {
    (Some(drag), _) => {
      let world = state.viewport.screen_to_world(screen) catch {
        @spatial.CoordinateError::NonFinite => return state
      }
      let moved = drag.positions_at(world) catch {
        @spatial.CoordinateError::NonFinite => return state
      }
      let positions = state.positions.copy()
      for item in moved {
        positions[item.id] = item.point
      }
      { ..state, positions, }
    }
    (None, Some(pan)) => {
      let viewport = pan.viewport_at(screen) catch {
        @spatial.CoordinateError::NonFinite => return state
      }
      { ..state, viewport, }
    }
    (None, None) => state
  }
}

///|
fn incr_canvas_pointer_up(
  state : IncrCanvasState,
  pointer_id : Int?,
) -> IncrCanvasState {
  guard state.active_pointer_id == pointer_id else { return state }
  { ..state, panning: None, dragging: None, active_pointer_id: None }
}

///|
fn incr_canvas_capture_lost(state : IncrCanvasState) -> IncrCanvasState {
  { ..state, panning: None, dragging: None, active_pointer_id: None }
}

///|
fn incr_canvas_capture_lost_for_pointer(
  state : IncrCanvasState,
  pointer_id : Int?,
) -> IncrCanvasState {
  guard state.active_pointer_id == pointer_id else { return state }
  incr_canvas_capture_lost(state)
}

///|
fn incr_canvas_zoom(
  state : IncrCanvasState,
  delta : Double,
  x : Double,
  y : Double,
) -> IncrCanvasState {
  guard !delta.is_nan() && !delta.is_inf() && delta != 0.0 else { return state }
  let anchor = match incr_canvas_screen_point(x, y) {
    Some(point) => point
    None => return state
  }
  let current = state.viewport.scale().to_double()
  let factor = if delta < 0.0 { 1.1 } else { 0.9 }
  let next = current * factor
  let bounded = if next < INCR_CANVAS_MIN_SCALE {
    INCR_CANVAS_MIN_SCALE
  } else if next > INCR_CANVAS_MAX_SCALE {
    INCR_CANVAS_MAX_SCALE
  } else {
    next
  }
  let scale = @spatial.Scale::from_double(value=bounded) catch {
    @spatial.ScaleError::NonFinite | @spatial.ScaleError::NonPositive =>
      return state
  }
  let viewport = state.viewport.with_scale_around(anchor~, absolute_scale=scale) catch {
    @spatial.CoordinateError::NonFinite => return state
  }
  { ..state, viewport, }
}
