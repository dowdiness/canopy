///|
fn incr_canvas_screen_position(
  state : IncrCanvasState,
  id : @incr.CellId,
) -> @spatial.ScreenPoint? {
  match state.positions.get(id) {
    Some(world) =>
      Some(
        state.viewport.world_to_screen(world) catch {
          @spatial.CoordinateError::NonFinite => return None
        },
      )
    None => None
  }
}

///|
fn incr_canvas_cell_id(id : @incr.CellId) -> String {
  "cell_" + id.runtime_id.to_string() + "_" + id.id.to_string()
}

///|
fn incr_canvas_node_label(node : @visualizer.RecomputeSnapshotNode) -> String {
  match node.label {
    Some(label) => label
    None => "cell " + node.id.id.to_string()
  }
}

///|
fn incr_canvas_status(
  snapshot : @visualizer.RecomputeSnapshot,
  id : @incr.CellId,
) -> @visualizer.VisualNodeStatus {
  match snapshot.events.filter(event => event.cell_id == id).last() {
    Some(event) =>
      match event.phase {
        @visualizer.RecomputePhase::Entering =>
          @visualizer.VisualNodeStatus::Active
        @visualizer.RecomputePhase::Completed =>
          if event.backdated {
            @visualizer.VisualNodeStatus::Neutral
          } else {
            @visualizer.VisualNodeStatus::Changed
          }
        @visualizer.RecomputePhase::Aborted =>
          @visualizer.VisualNodeStatus::Failed
      }
    None => @visualizer.VisualNodeStatus::Neutral
  }
}

///|
fn append_incr_canvas_edge(
  buf : StringBuilder,
  state : IncrCanvasState,
  edge : @visualizer.RecomputeSnapshotEdge,
) -> Unit {
  match
    (
      incr_canvas_screen_position(state, edge.from),
      incr_canvas_screen_position(state, edge.to),
    ) {
    (Some(from), Some(to)) =>
      buf.write_string(
        "<line class=\"incr-canvas-edge\" x1=\"\{from.x()}\" y1=\"\{from.y()}\" x2=\"\{to.x()}\" y2=\"\{to.y()}\" />",
      )
    _ => ()
  }
}

///|
fn append_incr_canvas_node(
  buf : StringBuilder,
  state : IncrCanvasState,
  snapshot : @visualizer.RecomputeSnapshot,
  node : @visualizer.RecomputeSnapshotNode,
) -> Unit {
  match incr_canvas_screen_position(state, node.id) {
    Some(center) => {
      let status = incr_canvas_status(snapshot, node.id)
      let selected = state.selected.contains(node.id)
      let stroke = if selected { "#b090e0" } else { status.stroke() }
      let label = @history_render.escape_html_string(
        incr_canvas_node_label(node),
      )
      let cell_id = @history_render.escape_html_string(
        incr_canvas_cell_id(node.id),
      )
      let half_width = INCR_CANVAS_NODE_WIDTH / 2.0
      let half_height = INCR_CANVAS_NODE_HEIGHT / 2.0
      buf.write_string(
        "<g class=\"incr-canvas-node\" data-cell-id=\"\{cell_id}\" transform=\"translate(\{center.x()} \{center.y()})\"><rect x=\"\{0.0 - half_width}\" y=\"\{0.0 - half_height}\" width=\"\{INCR_CANVAS_NODE_WIDTH}\" height=\"\{INCR_CANVAS_NODE_HEIGHT}\" rx=\"6\" fill=\"\{status.fill()}\" stroke=\"\{stroke}\" /><text x=\"0\" y=\"5\" text-anchor=\"middle\">\{label}</text></g>",
      )
    }
    None => ()
  }
}

///|
/// Render the Ideal-local interactive graph. The SVG is deliberately small
/// and local: positions belong to `IncrCanvasState`, while nodes and edges are
/// read directly from the current `RecomputeSnapshot`.
fn render_incr_canvas_svg(
  state : IncrCanvasState,
  snapshot : @visualizer.RecomputeSnapshot,
) -> String {
  let buf = StringBuilder::new()
  buf.write_string(
    "<svg class=\"incr-canvas-svg\" width=\"100%\" height=\"220\" role=\"img\" aria-label=\"Interactive Incr dependency graph\" style=\"pointer-events:none\">",
  )
  for edge in snapshot.edges {
    append_incr_canvas_edge(buf, state, edge)
  }
  for node in snapshot.nodes {
    append_incr_canvas_node(buf, state, snapshot, node)
  }
  buf.write_string("</svg>")
  buf.to_string()
}

///|
const INCR_CANVAS_ACTIVE_POINTER_ATTRIBUTE : String = "data-incr-active-pointer-id"

///|
fn incr_canvas_screen_point_from_target(
  target : @dom.EventTarget,
  client_x : Double,
  client_y : Double,
) -> @spatial.ScreenPoint? {
  guard target.to_element() is Some(element) else { return None }
  let rect = element.get_bounding_client_rect()
  incr_canvas_screen_point(
    client_x - rect.get_left(),
    client_y - rect.get_top(),
  )
}

///|
fn incr_canvas_screen_point_from_pointer_event(
  event : @dom.PointerEvent,
) -> @spatial.ScreenPoint? {
  match event.current_target().to_option() {
    Some(target) =>
      incr_canvas_screen_point_from_target(
        target,
        event.get_client_x(),
        event.get_client_y(),
      )
    None => None
  }
}

///|
fn incr_canvas_screen_point_from_wheel_event(
  event : @dom.WheelEvent,
) -> @spatial.ScreenPoint? {
  match event.current_target().to_option() {
    Some(target) =>
      incr_canvas_screen_point_from_target(
        target,
        event.get_client_x(),
        event.get_client_y(),
      )
    None => None
  }
}

///|
fn incr_canvas_pointer_id(event : @dom.PointerEvent) -> Int {
  event.get_pointer_id()
}

///|
fn incr_canvas_pointer_is_claimed(event : @dom.PointerEvent) -> Bool {
  match event.current_target().to_option() {
    Some(target) =>
      match target.to_element() {
        Some(element) =>
          incr_canvas_pointer_claim_matches(
            element.get_attribute(INCR_CANVAS_ACTIVE_POINTER_ATTRIBUTE),
            Some(event.get_pointer_id()),
          )
        None => false
      }
    None => false
  }
}

///|
fn incr_canvas_try_claim_pointer(event : @dom.PointerEvent) -> Bool {
  match event.current_target().to_option() {
    Some(target) =>
      match target.to_element() {
        Some(element) =>
          match element.get_attribute(INCR_CANVAS_ACTIVE_POINTER_ATTRIBUTE) {
            Some(_) => false
            None => {
              element.set_attribute(
                INCR_CANVAS_ACTIVE_POINTER_ATTRIBUTE,
                event.get_pointer_id().to_string(),
              )
              true
            }
          }
        None => false
      }
    None => false
  }
}

///|
fn incr_canvas_clear_pointer_claim(
  event : @dom.Event,
  pointer_id : Int,
) -> Unit {
  match event.current_target().to_option() {
    Some(target) =>
      match target.to_element() {
        Some(element) =>
          if element.get_attribute(INCR_CANVAS_ACTIVE_POINTER_ATTRIBUTE) ==
            Some(pointer_id.to_string()) {
            element.remove_attribute(INCR_CANVAS_ACTIVE_POINTER_ATTRIBUTE)
          }
        None => ()
      }
    None => ()
  }
}

///|
fn incr_canvas_set_pointer_capture(
  event : @dom.PointerEvent,
) -> Unit raise @dom.DOMExceptionError {
  match event.current_target().to_option() {
    Some(target) =>
      match target.to_element() {
        Some(element) => element.set_pointer_capture(event.get_pointer_id())
        None => ()
      }
    None => ()
  }
}

///|
fn incr_canvas_release_pointer_capture(event : @dom.PointerEvent) -> Unit {
  match event.current_target().to_option() {
    Some(target) =>
      match target.to_element() {
        Some(element) => {
          let pointer_id = event.get_pointer_id()
          if element.get_attribute(INCR_CANVAS_ACTIVE_POINTER_ATTRIBUTE) ==
            Some(pointer_id.to_string()) {
            if element.has_pointer_capture(pointer_id) {
              element.release_pointer_capture(pointer_id) catch {
                @dom.DOMExceptionError(..) => ()
              }
            }
            element.remove_attribute(INCR_CANVAS_ACTIVE_POINTER_ATTRIBUTE)
          }
        }
        None => ()
      }
    None => ()
  }
}

///|
fn incr_canvas_pointer_attrs(dispatch : Emit[Msg]) -> @html.Attrs {
  @html.Attrs::build()
  .on_pointerdown(event => {
    event.prevent_default()
    match incr_canvas_screen_point_from_pointer_event(event) {
      Some(screen) => {
        let pointer_id = incr_canvas_pointer_id(event)
        if incr_canvas_try_claim_pointer(event) {
          try {
            incr_canvas_set_pointer_capture(event)
            dispatch(
              IncrCanvas(PointerDown(screen.x(), screen.y(), Some(pointer_id))),
            )
          } catch {
            @dom.DOMExceptionError(..) => {
              incr_canvas_clear_pointer_claim(event.as_event(), pointer_id)
              @rabbita_cmd.none
            }
          }
        } else {
          @rabbita_cmd.none
        }
      }
      None => @rabbita_cmd.none
    }
  })
  .on_pointermove(event => {
    if incr_canvas_pointer_is_claimed(event) {
      match incr_canvas_screen_point_from_pointer_event(event) {
        Some(screen) =>
          dispatch(
            IncrCanvas(
              PointerMove(
                screen.x(),
                screen.y(),
                Some(incr_canvas_pointer_id(event)),
              ),
            ),
          )
        None => @rabbita_cmd.none
      }
    } else {
      @rabbita_cmd.none
    }
  })
  .on_pointerup(event => {
    event.prevent_default()
    if incr_canvas_pointer_is_claimed(event) {
      incr_canvas_release_pointer_capture(event)
      dispatch(IncrCanvas(PointerUp(Some(incr_canvas_pointer_id(event)))))
    } else {
      @rabbita_cmd.none
    }
  })
  .on_pointercancel(event => {
    event.prevent_default()
    if incr_canvas_pointer_is_claimed(event) {
      incr_canvas_release_pointer_capture(event)
      dispatch(IncrCanvas(PointerCancel(Some(incr_canvas_pointer_id(event)))))
    } else {
      @rabbita_cmd.none
    }
  })
  .on_lostpointercapture(event => {
    let pointer_id = event.get_pointer_id()
    incr_canvas_clear_pointer_claim(event.as_event(), pointer_id)
    dispatch(IncrCanvas(CaptureLost(Some(pointer_id))))
  })
  .on_wheel(event => {
    event.prevent_default()
    match incr_canvas_screen_point_from_wheel_event(event) {
      Some(screen) =>
        dispatch(IncrCanvas(Wheel(event.get_delta_y(), screen.x(), screen.y())))
      None => @rabbita_cmd.none
    }
  })
}

///|
fn incr_canvas_interaction_attrs(
  dispatch : Emit[Msg],
  state : IncrCanvasState,
) -> @html.Attrs {
  let attrs = incr_canvas_pointer_attrs(dispatch)
  match state.active_pointer_id {
    Some(pointer_id) =>
      attrs.data_set("incr-reducer-pointer-id", pointer_id.to_string())
    None => attrs
  }
}

///|
#warnings("-alert_xss_vulnerable")
fn view_incr_canvas_panel(dispatch : Emit[Msg], model : Model) -> Html {
  let snapshot = model.incr_tap.snapshot()
  let svg = if model.workspace.bottom_visible {
    render_incr_canvas_svg(model.incr_canvas, snapshot)
  } else {
    ""
  }
  // Use a distinct outer tag from the raw-innerHTML SVG panels. Rabbita then
  // replaces the subtree when switching tabs instead of trying to patch a
  // stale innerHTML property in place.
  @html.div(
    class="bottom-content incr-canvas-content",
    attrs=bottom_panel_attrs(IncrCanvas),
    [
      @html.div(class="incr-canvas-meta", [
        @html.text(
          "\{snapshot.nodes.length()} cells — drag nodes, pan the background, scroll to zoom",
        ),
      ]),
      @html.div(class="incr-canvas-stage", [
        @html.div(
          class="incr-canvas-interaction",
          attrs=incr_canvas_interaction_attrs(dispatch, model.incr_canvas),
          [
            @html.div(
              class="incr-canvas-svg-host",
              attrs=@html.Attrs::build().inner_html(svg),
              ([] : Array[Html]),
            ),
          ],
        ),
      ]),
    ],
  )
}
