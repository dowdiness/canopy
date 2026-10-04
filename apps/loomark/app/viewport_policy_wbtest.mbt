///|
test "caret resize preserves a line exactly within the padded viewport" {
  assert_eq(caret_scroll_top(100.0, 270.0, 86.0, 200.0, 14.0, 16.0), 86.0)
}

///|
test "caret resize reveals a line below the viewport with bottom padding" {
  assert_eq(caret_scroll_top(270.0, 300.0, 86.0, 200.0, 14.0, 16.0), 116.0)
}

///|
test "caret resize reveals a line above the viewport with top padding" {
  assert_eq(caret_scroll_top(60.0, 90.0, 86.0, 200.0, 14.0, 16.0), 46.0)
}

///|
test "viewport placement follows normal pans but preserves zoom panning" {
  assert_eq(viewport_layout_top(32.0, 1.0, 0.0, 844.0, 380.0), 32.0)
  assert_eq(viewport_layout_top(120.0, 2.0, 464.0, 844.0, 380.0), 464.0)
}

///|
test "height recovery clears the obsolete zoomed viewport offset" {
  assert_eq(viewport_layout_top(120.0, 2.0, 464.0, 844.0, 700.0), 144.0)
  assert_eq(viewport_layout_top(120.0, 2.0, 464.0, 844.0, 844.0), 0.0)
}

///|
test "bottom bar hides for a reduced visual viewport, not a small window" {
  assert_true(bottom_bar_obscured(380.0, 844.0))
  // A small unobscured window or hardware-keyboard viewport keeps its controls.
  assert_false(bottom_bar_obscured(360.0, 360.0))
  assert_false(bottom_bar_obscured(844.0, 844.0))
}

///|
test "bottom bar tolerates subpixel height differences" {
  assert_false(bottom_bar_obscured(843.5, 844.0))
  assert_false(bottom_bar_obscured(843.0, 844.0))
  assert_true(bottom_bar_obscured(842.9, 844.0))
}
