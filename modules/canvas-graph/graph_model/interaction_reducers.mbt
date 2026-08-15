///|
fn update_pan_start(state : CanvasState, pointer : ScreenPoint) -> CanvasState {
  let pan = @spatial.Pan::start(viewport=state.viewport, pointer~)
  let new_interaction : InteractionState = {
    ..state.interaction,
    panning: Some(pan),
    pointer_down: true,
    did_move: false,
  }
  { ..state, interaction: new_interaction }
}

///|
/// Pan is computed as an absolute offset from the captured snapshot.
pub fn update_pan_move(
  state : CanvasState,
  pointer : ScreenPoint,
) -> CanvasState {
  match state.interaction.panning {
    None => state
    Some(pan) => {
      let next_viewport = pan.viewport_at(pointer) catch {
        @spatial.CoordinateError::NonFinite => return state
      }
      let start = pan.start_pointer()
      let did_move = state.interaction.did_move ||
        pointer.x() != start.x() ||
        pointer.y() != start.y()
      let new_interaction : InteractionState = {
        ..state.interaction,
        did_move,
      }
      { ..state, viewport: next_viewport, interaction: new_interaction }
    }
  }
}

///|
/// Zoom the viewport toward a typed cursor point.
pub fn update_zoom(
  state : CanvasState,
  delta : Double,
  anchor : ScreenPoint,
) -> CanvasState {
  if delta.is_nan() || delta.is_inf() {
    state
  } else {
    let factor = if delta > 0.0 { 0.9 } else { 1.0 / 0.9 }
    let old_scale = state.viewport.scale().to_double()
    let raw = old_scale * factor
    let new_scale_value = if raw < 0.1 {
      0.1
    } else if raw > 8.0 {
      8.0
    } else {
      raw
    }
    let new_scale = @spatial.Scale::from_double(value=new_scale_value) catch {
      @spatial.ScaleError::NonFinite | @spatial.ScaleError::NonPositive =>
        return state
    }
    let new_viewport = state.viewport.with_scale_around(
      anchor~,
      absolute_scale=new_scale,
    ) catch {
      @spatial.CoordinateError::NonFinite => return state
    }
    record_action(
      { ..state, viewport: new_viewport },
      SetViewport(new_viewport),
    )
  }
}

///|

///|
/// Dispatch a typed pointer-down event to pan or drag.
pub fn update_pointer_down(
  state : CanvasState,
  node_id : NodeId?,
  screen : ScreenPoint,
) -> CanvasState raise @spatial.CoordinateError {
  match node_id {
    None => update_pan_start(state, screen)
    Some(id) =>
      update_node_drag_start(state, id, state.viewport.screen_to_world(screen))
  }
}

///|
/// Start an edge-creation gesture from a specific output port.
pub fn update_connect_start(
  state : CanvasState,
  node_id : NodeId,
  port_id : String,
  pointer : WorldPoint,
) -> CanvasState {
  match find_node(state.nodes, node_id) {
    None => state
    Some(node) =>
      match port_type_by_id(node.outputs, port_id) {
        None => state
        Some(_) => {
          let conn = ConnectState::from_parts(
            from_node=node_id,
            from_port=port_id,
            cursor=pointer,
          )
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
pub fn update_connect_move(
  state : CanvasState,
  pointer : WorldPoint,
) -> CanvasState {
  match state.interaction.connecting {
    None => state
    Some(conn) => {
      let new_conn = ConnectState::from_parts(
        from_node=conn.from_node,
        from_port=conn.from_port,
        cursor=pointer,
      )
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
fn workflow_node_kind_from_key(key : String) -> WorkflowNodeKind {
  if key == "timer" {
    TimerTrigger
  } else if key == "http" {
    HttpRequest
  } else if key == "formatter" {
    DataFormatter
  } else if key == "condition" {
    ConditionalBranch
  } else if key == "loop" {
    Loop
  } else if key == "parallel" {
    Parallel
  } else {
    Custom("Custom step")
  }
}

///|
pub fn workflow_add_node(
  state : CanvasState,
  kind_key : String,
  position : WorldPoint,
) -> CanvasState {
  let node = make_workflow_node(
    NodeId(state.next_node_id.to_string()),
    workflow_node_kind_from_key(kind_key),
    position,
  )
  record_action(state, AddNode(node))
}

///|
/// Commit an in-flight connection if released over a compatible target port,
/// otherwise drop it. Rejected connection attempts retain existing logging.
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
/// Compute a drag preview at a typed world pointer position.
pub fn drag_preview_from_move(
  drag : @spatial.Drag[NodeId],
  pointer : WorldPoint,
) -> DragPreview raise @spatial.CoordinateError {
  let positions = drag.positions_at(pointer)
  let moved_positions = positions.map(item => {
    @spatial.ItemPosition::from_id_and_point(id=item.id, point=item.point)
  })
  { positions: moved_positions }
}

///|
fn drag_ids_for_node(state : CanvasState, node_id : NodeId) -> Array[NodeId] {
  if state.interaction.selected_nodes.iter().any(fn(id) { id == node_id }) {
    state.interaction.selected_nodes.copy()
  } else {
    [node_id]
  }
}

///|
fn update_node_drag_start(
  state : CanvasState,
  node_id : NodeId,
  pointer : WorldPoint,
) -> CanvasState {
  match find_node(state.nodes, node_id) {
    None => state
    Some(_) => {
      let positions = drag_ids_for_node(state, node_id).filter_map(drag_id => {
        match find_node(state.nodes, drag_id) {
          None => None
          Some(node) =>
            Some(
              @spatial.ItemPosition::from_id_and_point(
                id=drag_id,
                point=node.position(),
              ),
            )
        }
      })
      let snapshot : ReadOnlyArray[@spatial.ItemPosition[NodeId]] = ReadOnlyArray::from_array(
        positions[:],
      )
      let drag = @spatial.Drag::start(positions=snapshot, pointer~)
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
fn final_drag_positions(
  state : CanvasState,
  drag : @spatial.Drag[NodeId],
) -> Array[NodePosition] {
  drag
  .initial_ids()
  .filter_map(node_id => {
    match find_node(state.nodes, node_id) {
      None => None
      Some(node) =>
        Some(
          @spatial.ItemPosition::from_id_and_point(
            id=node.id,
            point=node.position(),
          ),
        )
    }
  })
}

///|
fn toggle_selection(nodes : Array[NodeId], id : NodeId) -> Array[NodeId] {
  if nodes.iter().any(fn(n) { n == id }) {
    nodes.filter(fn(n) { n != id })
  } else {
    [..nodes, id]
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
/// Handle pointer release. `node_id` is the canvas node id under the pointer,
/// or "" if released over the background.
pub fn update_pointer_up(
  state : CanvasState,
  node_id : String,
  target_port_id : String,
  additive : Bool,
) -> CanvasState {
  let hovered : NodeId? = if node_id == "" {
    None
  } else {
    Some(NodeId(node_id))
  }
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

///|
/// Handle browser interruption without committing a drag, connection, or click.
/// A moved pan has already changed the live viewport, so preserve it and record
/// one final viewport action before clearing the transient gesture state.
pub fn update_pointer_interrupt(state : CanvasState) -> CanvasState {
  let action_state = match state.interaction.panning {
    Some(_) if state.interaction.did_move =>
      record_action(state, SetViewport(state.viewport))
    _ => state
  }
  let new_interaction : InteractionState = {
    ..action_state.interaction,
    dragging: None,
    panning: None,
    connecting: None,
    pointer_down: false,
    did_move: false,
  }
  { ..action_state, interaction: new_interaction }
}
