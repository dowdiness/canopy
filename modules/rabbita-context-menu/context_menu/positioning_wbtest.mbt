///|
#cfg(target="js")
test "panel placement applies offsets before clamping to either viewport edge" {
  assert_eq(clamp_panel_coordinate(98.0, 4.0, 30.0, 100.0, 8.0), 62.0)
  assert_eq(clamp_panel_coordinate(10.0, -5.0, 30.0, 100.0, 8.0), 8.0)
  assert_eq(clamp_panel_coordinate(10.0, 5.0, 30.0, 100.0, 8.0), 15.0)
}

///|
#cfg(target="js")
test "oversized panels stay at the viewport margin" {
  assert_eq(clamp_panel_coordinate(50.0, 0.0, 120.0, 100.0, 8.0), 8.0)
}

///|
#cfg(target="js")
test "negative margins and non-finite measured extents retain browser semantics" {
  assert_eq(clamp_panel_coordinate(-10.0, 0.0, 30.0, 100.0, -8.0), 0.0)
  for extent in [0.0 / 0.0, 1.0 / 0.0, -1.0 / 0.0] {
    assert_eq(clamp_panel_coordinate(98.0, 4.0, extent, 100.0, 8.0), 92.0)
  }
}

///|
#cfg(target="js")
test "invalid positioning numbers propagate instead of becoming valid coordinates" {
  let nan = 0.0 / 0.0
  assert_true(clamp_panel_coordinate(nan, 0.0, 30.0, 100.0, 8.0).is_nan())
  assert_true(clamp_panel_coordinate(10.0, 0.0, 30.0, 100.0, nan).is_nan())
  assert_true(clamp_panel_coordinate(10.0, 0.0, 30.0, nan, 8.0).is_nan())
}
