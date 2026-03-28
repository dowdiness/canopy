///|
fn update_pan_start(
  state : CanvasState,
  screen_x : Double,
  screen_y : Double,
) -> CanvasState {
  let pan : PanState = {
    start_screen_x: screen_x,
    start_screen_y: screen_y,
    start_pan_x: state.viewport.x,
    start_pan_y: state.viewport.y,
  }
  let new_interaction : InteractionState = {
    ..state.interaction,
    panning: Some(pan),
    pointer_down: true,
    did_move: false,
  }
  { ..state, interaction: new_interaction }
}

///|
/// Pan is computed as absolute offset from start_pan to avoid
/// float accumulation across multiple move events.
fn update_pan_move(
  state : CanvasState,
  screen_x : Double,
  screen_y : Double,
) -> CanvasState {
  match state.interaction.panning {
    None => state
    Some(pan) => {
      let new_viewport : Viewport = {
        ..state.viewport,
        x: pan.start_pan_x + (screen_x - pan.start_screen_x),
        y: pan.start_pan_y + (screen_y - pan.start_screen_y),
      }
      let did_move = state.interaction.did_move ||
        screen_x != pan.start_screen_x ||
        screen_y != pan.start_screen_y
      let new_interaction : InteractionState = {
        ..state.interaction,
        did_move,
      }
      { ..state, viewport: new_viewport, interaction: new_interaction }
    }
  }
}

///|
/// Zoom the viewport toward the cursor position `(cx, cy)` in canvas-local
/// screen coords. Factor 0.9 = zoom out, 1/0.9 ≈ 1.111 = zoom in.
fn update_zoom(
  state : CanvasState,
  delta : Double,
  cx : Double,
  cy : Double,
) -> CanvasState {
  let factor = if delta > 0.0 { 0.9 } else { 1.0 / 0.9 }
  let old_scale = state.viewport.scale
  let raw = old_scale * factor
  let new_scale = if raw < 0.1 { 0.1 } else if raw > 8.0 { 8.0 } else { raw }
  let ratio = new_scale / old_scale
  let new_viewport : Viewport = {
    scale: new_scale,
    x: cx + (state.viewport.x - cx) * ratio,
    y: cy + (state.viewport.y - cy) * ratio,
  }
  { ..state, viewport: new_viewport }
}

///|
fn screen_to_world(
  viewport : Viewport,
  sx : Double,
  sy : Double,
) -> (Double, Double) {
  ((sx - viewport.x) / viewport.scale, (sy - viewport.y) / viewport.scale)
}

///|
/// Dispatch a pointer-down event to pan or drag based on node_id.
/// Accepts screen coordinates; converts to world coords internally for dragging.
fn update_pointer_down(
  state : CanvasState,
  node_id : NodeId?,
  sx : Double,
  sy : Double,
) -> CanvasState {
  match node_id {
    None => update_pan_start(state, sx, sy)
    Some(id) => {
      let (wx, wy) = screen_to_world(state.viewport, sx, sy)
      update_node_drag_start(state, id, wx, wy)
    }
  }
}

///|
/// Dispatch a pointer-move event to the active gesture.
/// Accepts screen coordinates; converts to world coords internally for dragging.
fn update_pointer_move(
  state : CanvasState,
  sx : Double,
  sy : Double,
) -> CanvasState {
  match state.interaction.dragging {
    Some(_) => {
      let (wx, wy) = screen_to_world(state.viewport, sx, sy)
      update_node_drag_move(state, wx, wy)
    }
    None => update_pan_move(state, sx, sy)
  }
}

///|
fn find_node(nodes : Array[CanvasNode], id : NodeId) -> CanvasNode? {
  for node in nodes {
    if node.id == id {
      return Some(node)
    }
  }
  None
}

///|
fn update_node_drag_start(
  state : CanvasState,
  node_id : NodeId,
  world_x : Double,
  world_y : Double,
) -> CanvasState {
  match find_node(state.nodes, node_id) {
    None => state
    Some(node) => {
      let drag : DragState = {
        node_id,
        offset_x: node.x - world_x,
        offset_y: node.y - world_y,
      }
      let new_interaction : InteractionState = {
        ..state.interaction,
        dragging: Some(drag),
        pointer_down: true,
        did_move: false,
      }
      { ..state, interaction: new_interaction }
    }
  }
}

///|
fn update_node_drag_move(
  state : CanvasState,
  world_x : Double,
  world_y : Double,
) -> CanvasState {
  match state.interaction.dragging {
    None => state
    Some(drag) => {
      let new_nodes = state.nodes.map(fn(node) {
        if node.id == drag.node_id {
          { ..node, x: world_x + drag.offset_x, y: world_y + drag.offset_y }
        } else {
          node
        }
      })
      let new_interaction : InteractionState = {
        ..state.interaction,
        did_move: true,
      }
      { ..state, nodes: new_nodes, interaction: new_interaction }
    }
  }
}

///|
/// Handle pointer release. `node_id_int` is the canvas node id under the pointer,
/// or 0 if released over the background.
/// A "click" = pointer_down was true AND no movement occurred → select the node.
fn update_pointer_up(state : CanvasState, node_id_int : Int) -> CanvasState {
  let hovered : NodeId? = if node_id_int <= 0 {
    None
  } else {
    Some(NodeId(node_id_int))
  }
  let new_selected : NodeId? = if state.interaction.pointer_down &&
    not(state.interaction.did_move) {
    hovered
  } else {
    state.interaction.selected
  }
  let new_interaction : InteractionState = {
    dragging: None,
    panning: None,
    pointer_down: false,
    did_move: false,
    selected: new_selected,
  }
  { ..state, interaction: new_interaction }
}
