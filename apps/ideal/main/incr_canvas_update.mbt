///|
fn sync_incr_canvas(model : Model) -> Model {
  let snapshot = model.incr_tap.snapshot()
  let canvas = sync_incr_canvas_state(model.incr_canvas, snapshot)
  { ..model, incr_canvas: canvas }
}

///|
fn handle_incr_canvas(
  emit : Emit[Msg],
  msg : Msg,
  model : Model,
) -> (Cmd, Model)? {
  let _ = emit
  match msg {
    IncrCanvas(canvas_msg) => {
      let current = sync_incr_canvas(model)
      let state = match canvas_msg {
        PointerDown(x, y, pointer_id) =>
          incr_canvas_pointer_down(
            current.incr_canvas,
            current.incr_tap.snapshot(),
            x,
            y,
            pointer_id,
          )
        PointerMove(x, y, pointer_id) =>
          incr_canvas_pointer_move(current.incr_canvas, x, y, pointer_id)
        PointerUp(pointer_id) | PointerCancel(pointer_id) =>
          incr_canvas_pointer_up(current.incr_canvas, pointer_id)
        CaptureLost(pointer_id) =>
          incr_canvas_capture_lost_for_pointer(current.incr_canvas, pointer_id)
        Wheel(delta, x, y) => incr_canvas_zoom(current.incr_canvas, delta, x, y)
      }
      Some((none, { ..current, incr_canvas: state }))
    }
    _ => None
  }
}
