///|
test "canvas input geometry preserves fractional positions" {
  match context_menu_anchor(12.5, 30.25) {
    Some(anchor) => {
      assert_eq(anchor.x, 12.5F)
      assert_eq(anchor.y, 30.25F)
    }
    None => fail("finite fractional menu anchors should be retained")
  }
  match canvas_relative_screen_point(12.5, 30.25, 1.25, 2.5) {
    Some(point) => {
      assert_eq(point.x(), 11.25)
      assert_eq(point.y(), 27.75)
    }
    None => fail("finite fractional local points should be retained")
  }
}

///|
test "canvas input numeric conversions reject overflow" {
  assert_true(context_menu_anchor(1.0e100, 0.0) is None)
  assert_true(canvas_relative_screen_point(1.0e308, 0.0, -1.0e308, 0.0) is None)
}
