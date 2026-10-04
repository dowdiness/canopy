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
test "pinch zoom does not drive editor layout" {
  assert_true(follows_visual_viewport(1.0))
  assert_false(follows_visual_viewport(2.0))
  assert_false(follows_visual_viewport(0.5))
}
