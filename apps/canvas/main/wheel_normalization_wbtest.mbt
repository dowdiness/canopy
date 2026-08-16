///|
fn canvas_wheel_test_scale(value : Double) -> @spatial.Scale {
  try! @spatial.Scale::from_double(value~)
}

///|
fn canvas_wheel_required_target(
  current_scale : @spatial.Scale,
  delta_y : Double,
  delta_mode : Int,
  ctrl_key : Bool,
  mac_like : Bool,
  min_scale~ : Double,
  max_scale~ : Double,
) -> @spatial.Scale raise {
  match
    canvas_wheel_target_scale(
      current_scale,
      delta_y,
      delta_mode,
      ctrl_key,
      mac_like,
      min_scale~,
      max_scale~,
    ) {
    Some(scale) => scale
    None => fail("expected an admissible wheel target")
  }
}

///|
fn canvas_wheel_assert_close(actual : Double, expected : Double) -> Unit raise {
  guard actual.is_close(
    expected,
    relative_tolerance=1.0e-9,
    absolute_tolerance=1.0e-9,
  ) else {
    fail("wheel scale values are not close")
  }
}

///|
test "canvas wheel rejects zero, unknown units, and non-finite deltas" {
  let scale = canvas_wheel_test_scale(1.0)
  assert_true(
    canvas_wheel_target_scale(
      scale,
      0.0,
      0,
      false,
      false,
      min_scale=0.1,
      max_scale=8.0,
    )
    is None,
  )
  assert_true(
    canvas_wheel_target_scale(
      scale,
      -1.0,
      9,
      false,
      false,
      min_scale=0.1,
      max_scale=8.0,
    )
    is None,
  )
  for delta in [0.0 / 0.0, 1.0 / 0.0, -1.0 / 0.0] {
    assert_true(
      canvas_wheel_target_scale(
        scale,
        delta,
        0,
        false,
        false,
        min_scale=0.1,
        max_scale=8.0,
      )
      is None,
    )
  }
}

///|
test "canvas wheel magnitude changes zoom continuously" {
  let scale = canvas_wheel_test_scale(1.0)
  let small = canvas_wheel_required_target(
    scale,
    -10.0,
    0,
    false,
    false,
    min_scale=0.1,
    max_scale=8.0,
  )
  let large = canvas_wheel_required_target(
    scale,
    -100.0,
    0,
    false,
    false,
    min_scale=0.1,
    max_scale=8.0,
  )
  assert_true(small.to_double() > 1.0)
  assert_true(large.to_double() > small.to_double())
}

///|
test "canvas wheel pixel line and page units are equivalent" {
  let scale = canvas_wheel_test_scale(1.0)
  let pixel = canvas_wheel_required_target(
    scale,
    -50.0,
    0,
    false,
    false,
    min_scale=0.1,
    max_scale=8.0,
  )
  let line = canvas_wheel_required_target(
    scale,
    -2.0,
    1,
    false,
    false,
    min_scale=0.1,
    max_scale=8.0,
  )
  let page = canvas_wheel_required_target(
    scale,
    -0.1,
    2,
    false,
    false,
    min_scale=0.1,
    max_scale=8.0,
  )
  canvas_wheel_assert_close(pixel.to_double(), line.to_double())
  canvas_wheel_assert_close(pixel.to_double(), page.to_double())
}

///|
test "canvas wheel ctrl pinch is mac-like only" {
  let scale = canvas_wheel_test_scale(1.0)
  let plain = canvas_wheel_required_target(
    scale,
    -1.0,
    0,
    false,
    false,
    min_scale=0.1,
    max_scale=8.0,
  )
  let mac_pinch = canvas_wheel_required_target(
    scale,
    -1.0,
    0,
    true,
    true,
    min_scale=0.1,
    max_scale=8.0,
  )
  let other_platform = canvas_wheel_required_target(
    scale,
    -1.0,
    0,
    true,
    false,
    min_scale=0.1,
    max_scale=8.0,
  )
  assert_true(mac_pinch.to_double() > plain.to_double())
  canvas_wheel_assert_close(other_platform.to_double(), plain.to_double())
}

///|
test "canvas wheel opposite deltas approximately round trip" {
  let scale = canvas_wheel_test_scale(1.0)
  let zoomed = canvas_wheel_required_target(
    scale,
    -50.0,
    0,
    false,
    false,
    min_scale=0.1,
    max_scale=8.0,
  )
  let returned = canvas_wheel_required_target(
    zoomed,
    50.0,
    0,
    false,
    false,
    min_scale=0.1,
    max_scale=8.0,
  )
  canvas_wheel_assert_close(returned.to_double(), 1.0)
}

///|
test "canvas wheel target scale clamps at host bounds" {
  let scale = canvas_wheel_test_scale(7.9)
  let maxed = canvas_wheel_required_target(
    scale,
    -100.0,
    0,
    false,
    false,
    min_scale=0.1,
    max_scale=8.0,
  )
  assert_eq(maxed.to_double(), 8.0)
  let repeated = canvas_wheel_required_target(
    maxed,
    -100.0,
    0,
    false,
    false,
    min_scale=0.1,
    max_scale=8.0,
  )
  assert_eq(repeated.to_double(), maxed.to_double())

  let huge_zoom_in = canvas_wheel_required_target(
    canvas_wheel_test_scale(1.0),
    -1.0e308,
    0,
    false,
    false,
    min_scale=0.1,
    max_scale=8.0,
  )
  let huge_zoom_out = canvas_wheel_required_target(
    canvas_wheel_test_scale(1.0),
    1.0e308,
    0,
    false,
    false,
    min_scale=0.1,
    max_scale=8.0,
  )
  assert_eq(huge_zoom_in.to_double(), 8.0)
  assert_eq(huge_zoom_out.to_double(), 0.1)

  let huge_pinch_in = canvas_wheel_required_target(
    canvas_wheel_test_scale(1.0),
    -1.0e308,
    2,
    true,
    true,
    min_scale=0.1,
    max_scale=8.0,
  )
  let huge_pinch_out = canvas_wheel_required_target(
    canvas_wheel_test_scale(1.0),
    1.0e308,
    2,
    true,
    true,
    min_scale=0.1,
    max_scale=8.0,
  )
  assert_eq(huge_pinch_in.to_double(), 8.0)
  assert_eq(huge_pinch_out.to_double(), 0.1)
}
