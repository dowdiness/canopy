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
  record_action({ ..state, viewport: new_viewport }, SetViewport(new_viewport))
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
/// Start an edge-creation gesture from a specific output port.
fn update_connect_start(
  state : CanvasState,
  node_id : NodeId,
  port_id : String,
  world_x : Double,
  world_y : Double,
) -> CanvasState {
  match find_node(state.nodes, node_id) {
    None => state
    Some(node) =>
      match port_type_by_id(node.outputs, port_id) {
        None => state
        Some(_) => {
          let conn : ConnectState = {
            from_node: node_id,
            from_port: port_id,
            cursor_x: world_x,
            cursor_y: world_y,
          }
          let new_interaction : InteractionState = {
            ..state.interaction,
            connecting: Some(conn),
            pointer_down: true,
            did_move: false,
          }
          { ..state, interaction: new_interaction }
        }
      }
  }
}

///|
fn update_connect_move(
  state : CanvasState,
  world_x : Double,
  world_y : Double,
) -> CanvasState {
  match state.interaction.connecting {
    None => state
    Some(conn) => {
      let new_conn : ConnectState = {
        ..conn,
        cursor_x: world_x,
        cursor_y: world_y,
      }
      let new_interaction : InteractionState = {
        ..state.interaction,
        connecting: Some(new_conn),
        did_move: true,
      }
      { ..state, interaction: new_interaction }
    }
  }
}

///|
fn workflow_add_node(
  state : CanvasState,
  kind_key : String,
  world_x : Double,
  world_y : Double,
) -> CanvasState {
  let node = make_workflow_node(
    NodeId(state.next_node_id),
    workflow_node_kind_from_key(kind_key),
    world_x,
    world_y,
  )
  record_action(state, AddNode(node))
}

///|
/// Commit an in-flight connection if released over a compatible target port,
/// otherwise drop it. Rejected connection attempts are still logged as actions.
fn update_connect_end(
  state : CanvasState,
  target : NodeId?,
  target_port : String?,
) -> CanvasState {
  match state.interaction.connecting {
    None => state
    Some(conn) => {
      let action_state = match (target, target_port) {
        (Some(t), Some(port_id)) =>
          match find_node(state.nodes, t) {
            Some(target_node) =>
              match port_type_by_id(target_node.inputs, port_id) {
                Some(_) =>
                  record_action(
                    state,
                    ConnectPorts(conn.from_node, conn.from_port, t, port_id),
                  )
                None => state
              }
            None => state
          }
        _ => state
      }
      let new_interaction : InteractionState = {
        ..action_state.interaction,
        connecting: None,
        pointer_down: false,
        did_move: false,
      }
      { ..action_state, interaction: new_interaction }
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
  match state.interaction.connecting {
    Some(_) => {
      let (wx, wy) = screen_to_world(state.viewport, sx, sy)
      update_connect_move(state, wx, wy)
    }
    None =>
      match state.interaction.dragging {
        Some(_) => {
          let (wx, wy) = screen_to_world(state.viewport, sx, sy)
          update_node_drag_move(state, wx, wy)
        }
        None => update_pan_move(state, sx, sy)
      }
  }
}

///|
fn find_drag_origin(origins : Array[DragOrigin], id : NodeId) -> DragOrigin? {
  for origin in origins {
    if origin.node_id == id {
      return Some(origin)
    }
  }
  None
}

///|
fn drag_ids_for_node(state : CanvasState, node_id : NodeId) -> Array[NodeId] {
  if node_id_in_array(state.interaction.selected_nodes, node_id) {
    state.interaction.selected_nodes.copy()
  } else {
    [node_id]
  }
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
    Some(_) => {
      let drag_ids = drag_ids_for_node(state, node_id)
      let origins : Array[DragOrigin] = []
      for drag_id in drag_ids {
        match find_node(state.nodes, drag_id) {
          None => ()
          Some(node) =>
            origins.push({
              node_id: drag_id,
              offset_x: node.x - world_x,
              offset_y: node.y - world_y,
            })
        }
      }
      let drag : DragState = { node_id, origins }
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
        match find_drag_origin(drag.origins, node.id) {
          None => node
          Some(origin) =>
            {
              ..node,
              x: world_x + origin.offset_x,
              y: world_y + origin.offset_y,
            }
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
fn final_drag_positions(
  state : CanvasState,
  drag : DragState,
) -> Array[NodePosition] {
  let positions : Array[NodePosition] = []
  for origin in drag.origins {
    match find_node(state.nodes, origin.node_id) {
      None => ()
      Some(node) => positions.push({ node_id: node.id, x: node.x, y: node.y })
    }
  }
  positions
}

///|
fn toggle_selection(nodes : Array[NodeId], id : NodeId) -> Array[NodeId] {
  if node_id_in_array(nodes, id) {
    nodes.filter(fn(n) { n != id })
  } else {
    let next = nodes.copy()
    next.push(id)
    next
  }
}

///|
fn selection_after_click(
  state : CanvasState,
  hovered : NodeId?,
  additive : Bool,
) -> Array[NodeId] {
  match hovered {
    None => if additive { state.interaction.selected_nodes.copy() } else { [] }
    Some(id) =>
      if additive {
        toggle_selection(state.interaction.selected_nodes, id)
      } else {
        [id]
      }
  }
}

///|
/// Handle pointer release. `node_id_int` is the canvas node id under the pointer,
/// or 0 if released over the background.
/// A "click" = pointer_down was true AND no movement occurred → select the node.
fn update_pointer_up(
  state : CanvasState,
  node_id_int : Int,
  target_port_id : String,
  additive : Bool,
) -> CanvasState {
  let hovered : NodeId? = if node_id_int <= 0 {
    None
  } else {
    Some(NodeId(node_id_int))
  }
  // If a connection gesture is in flight, commit/cancel it and exit.
  match state.interaction.connecting {
    Some(_) => {
      let target_port = if target_port_id == "" {
        None
      } else {
        Some(target_port_id)
      }
      return update_connect_end(state, hovered, target_port)
    }
    None => ()
  }
  let moved_state = match state.interaction.dragging {
    Some(drag) if state.interaction.did_move => {
      let positions = final_drag_positions(state, drag)
      if positions.length() == 0 {
        state
      } else {
        record_action(state, MoveNodes(positions))
      }
    }
    _ =>
      match state.interaction.panning {
        Some(_) if state.interaction.did_move =>
          record_action(state, SetViewport(state.viewport))
        _ => state
      }
  }
  let selected_state = if state.interaction.pointer_down &&
    !state.interaction.did_move {
    let nodes = selection_after_click(moved_state, hovered, additive)
    record_action(moved_state, SelectNodes(nodes))
  } else {
    moved_state
  }
  let new_interaction : InteractionState = {
    ..selected_state.interaction,
    dragging: None,
    panning: None,
    connecting: None,
    pointer_down: false,
    did_move: false,
  }
  { ..selected_state, interaction: new_interaction }
}
