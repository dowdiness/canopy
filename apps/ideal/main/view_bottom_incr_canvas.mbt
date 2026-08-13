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
#cfg(target="js")
extern "js" fn incr_canvas_offset_x(event : @dom.MouseEvent) -> Double = "(event) => event.offsetX"

///|
#cfg(target="js")
extern "js" fn incr_canvas_offset_y(event : @dom.MouseEvent) -> Double = "(event) => event.offsetY"

///|
#cfg(target="js")
extern "js" fn incr_canvas_wheel_offset_x(event : @dom.WheelEvent) -> Double = "(event) => event.offsetX"

///|
#cfg(target="js")
extern "js" fn incr_canvas_wheel_offset_y(event : @dom.WheelEvent) -> Double = "(event) => event.offsetY"

///|
fn incr_canvas_pointer_id(event : @dom.MouseEvent) -> Int? {
  event.to_pointer_event().map(pointer => pointer.get_pointer_id())
}

///|
fn incr_canvas_pointer_is_claimed(event : @dom.MouseEvent) -> Bool {
  match (event.to_pointer_event(), event.current_target().to_option()) {
    (Some(pointer), Some(target)) =>
      match target.to_element() {
        Some(element) =>
          incr_canvas_pointer_claim_matches(
            element.get_attribute(INCR_CANVAS_ACTIVE_POINTER_ATTRIBUTE),
            Some(pointer.get_pointer_id()),
          )
        None => false
      }
    _ => false
  }
}

///|
fn incr_canvas_try_claim_pointer(event : @dom.MouseEvent) -> Bool {
  match (event.to_pointer_event(), event.current_target().to_option()) {
    (Some(pointer), Some(target)) =>
      match target.to_element() {
        Some(element) =>
          match element.get_attribute(INCR_CANVAS_ACTIVE_POINTER_ATTRIBUTE) {
            Some(_) => false
            None => {
              element.set_attribute(
                INCR_CANVAS_ACTIVE_POINTER_ATTRIBUTE,
                pointer.get_pointer_id().to_string(),
              )
              true
            }
          }
        None => false
      }
    _ => false
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
fn incr_canvas_handle_lost_pointer_capture(
  scheduler : &@rabbita_cmd.Scheduler,
  dispatch : Emit[Msg],
  event : @dom.Event,
) -> Unit {
  match event.to_pointer_event() {
    Some(pointer) => {
      let pointer_id = pointer.get_pointer_id()
      incr_canvas_clear_pointer_claim(event, pointer_id)
      scheduler.add(dispatch(IncrCanvas(CaptureLost(Some(pointer_id)))))
    }
    None => ()
  }
}

///|
fn incr_canvas_capture_listener_cmd(
  element : @dom.Element,
  dispatch : Emit[Msg],
) -> @rabbita_cmd.Cmd {
  @rabbita_cmd.custom_cmd(scheduler => {
    element.add_event_listener("lostpointercapture", event => {
      incr_canvas_handle_lost_pointer_capture(scheduler, dispatch, event)
    })
  })
}

///|
fn incr_canvas_set_pointer_capture(
  event : @dom.MouseEvent,
  dispatch : Emit[Msg],
) -> @rabbita_cmd.Cmd {
  match event.to_pointer_event() {
    Some(pointer) =>
      match event.current_target().to_option() {
        Some(target) =>
          match target.to_element() {
            Some(element) => {
              let listener_cmd = if element.get_attribute(
                  "data-incr-capture-listener",
                )
                is None {
                element.set_attribute("data-incr-capture-listener", "true")
                incr_canvas_capture_listener_cmd(element, dispatch)
              } else {
                @rabbita_cmd.none
              }
              element.set_pointer_capture(pointer.get_pointer_id())
              listener_cmd
            }
            None => @rabbita_cmd.none
          }
        None => @rabbita_cmd.none
      }
    None => @rabbita_cmd.none
  }
}

///|
fn incr_canvas_release_pointer_capture(event : @dom.MouseEvent) -> Unit {
  match event.to_pointer_event() {
    Some(pointer) =>
      match event.current_target().to_option() {
        Some(target) =>
          match target.to_element() {
            Some(element) => {
              let pointer_id = pointer.get_pointer_id()
              if element.get_attribute(INCR_CANVAS_ACTIVE_POINTER_ATTRIBUTE) ==
                Some(pointer_id.to_string()) {
                if element.has_pointer_capture(pointer_id) {
                  element.release_pointer_capture(pointer_id)
                }
                element.remove_attribute(INCR_CANVAS_ACTIVE_POINTER_ATTRIBUTE)
              }
            }
            None => ()
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
    let x = incr_canvas_offset_x(event)
    let y = incr_canvas_offset_y(event)
    let pointer_id = incr_canvas_pointer_id(event)
    let admitted = incr_canvas_screen_point(x, y) is Some(_) &&
      pointer_id is Some(_)
    if admitted && incr_canvas_try_claim_pointer(event) {
      @rabbita_cmd.batch([
        incr_canvas_set_pointer_capture(event, dispatch),
        dispatch(IncrCanvas(PointerDown(x, y, pointer_id))),
      ])
    } else {
      @rabbita_cmd.none
    }
  })
  .on_pointermove(event => {
    if incr_canvas_pointer_is_claimed(event) {
      dispatch(
        IncrCanvas(
          PointerMove(
            incr_canvas_offset_x(event),
            incr_canvas_offset_y(event),
            incr_canvas_pointer_id(event),
          ),
        ),
      )
    } else {
      @rabbita_cmd.none
    }
  })
  .on_pointerup(event => {
    event.prevent_default()
    if incr_canvas_pointer_is_claimed(event) {
      incr_canvas_release_pointer_capture(event)
      dispatch(IncrCanvas(PointerUp(incr_canvas_pointer_id(event))))
    } else {
      @rabbita_cmd.none
    }
  })
  .on_pointercancel(event => {
    event.prevent_default()
    if incr_canvas_pointer_is_claimed(event) {
      incr_canvas_release_pointer_capture(event)
      dispatch(IncrCanvas(PointerCancel(incr_canvas_pointer_id(event))))
    } else {
      @rabbita_cmd.none
    }
  })
  .on_wheel(event => {
    event.prevent_default()
    dispatch(
      IncrCanvas(
        Wheel(
          event.get_delta_y(),
          incr_canvas_wheel_offset_x(event),
          incr_canvas_wheel_offset_y(event),
        ),
      ),
    )
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
