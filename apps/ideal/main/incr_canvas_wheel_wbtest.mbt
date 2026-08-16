///|
fn incr_canvas_wheel_test_scale(value : Double) -> @spatial.Scale {
  try! @spatial.Scale::from_double(value~)
}

///|
fn incr_canvas_wheel_required_target(
  current_scale : @spatial.Scale,
  delta_y : Double,
  delta_mode : Int,
  ctrl_key : Bool,
  mac_like : Bool,
) -> @spatial.Scale raise {
  match
    incr_canvas_wheel_target_scale(
      current_scale, delta_y, delta_mode, ctrl_key, mac_like,
    ) {
    Some(scale) => scale
    None => fail("expected an admissible wheel target")
  }
}

///|
test "incr canvas wheel normalizes pixel line and page units" {
  let scale = incr_canvas_wheel_test_scale(1.0)
  let pixel = incr_canvas_wheel_required_target(scale, -50.0, 0, false, false)
  let line = incr_canvas_wheel_required_target(scale, -2.0, 1, false, false)
  let page = incr_canvas_wheel_required_target(scale, -0.1, 2, false, false)
  incr_canvas_assert_close(pixel.to_double(), line.to_double())
  incr_canvas_assert_close(pixel.to_double(), page.to_double())
}

///|
test "incr canvas wheel uses magnitude and mac-like pinch policy" {
  let scale = incr_canvas_wheel_test_scale(1.0)
  let small = incr_canvas_wheel_required_target(scale, -10.0, 0, false, false)
  let large = incr_canvas_wheel_required_target(scale, -100.0, 0, false, false)
  let pinch = incr_canvas_wheel_required_target(scale, -1.0, 0, true, true)
  let regular = incr_canvas_wheel_required_target(scale, -1.0, 0, false, false)
  assert_true(large.to_double() > small.to_double())
  assert_true(pinch.to_double() > regular.to_double())
  let huge_zoom_in = incr_canvas_wheel_required_target(
    scale, -1.0e308, 0, false, false,
  )
  let huge_zoom_out = incr_canvas_wheel_required_target(
    scale, 1.0e308, 0, false, false,
  )
  assert_eq(huge_zoom_in.to_double(), INCR_CANVAS_MAX_SCALE)
  assert_eq(huge_zoom_out.to_double(), INCR_CANVAS_MIN_SCALE)
  let huge_pinch_in = incr_canvas_wheel_required_target(
    scale, -1.0e308, 2, true, true,
  )
  let huge_pinch_out = incr_canvas_wheel_required_target(
    scale, 1.0e308, 2, true, true,
  )
  assert_eq(huge_pinch_in.to_double(), INCR_CANVAS_MAX_SCALE)
  assert_eq(huge_pinch_out.to_double(), INCR_CANVAS_MIN_SCALE)
}

///|
test "incr canvas wheel ignores active gestures and bounded no-ops" {
  let viewport = incr_canvas_test_viewport(0.0, 0.0, INCR_CANVAS_MAX_SCALE)
  let active = {
    ..IncrCanvasState::empty(),
    viewport,
    active_pointer_id: Some(4),
  }
  assert_incr_canvas_state_eq(
    incr_canvas_wheel(active, -100.0, 0, false, 10.0, 10.0),
    active,
  )
  let idle = { ..active, active_pointer_id: None }
  assert_incr_canvas_state_eq(
    incr_canvas_wheel(idle, -100.0, 0, false, 10.0, 10.0),
    idle,
  )
}
