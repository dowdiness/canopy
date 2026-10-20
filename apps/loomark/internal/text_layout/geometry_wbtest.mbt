///|
test "a glyph locates the top of its line box" {
  // 17 px glyphs in 27 px lines sit 5 px below the line's top.
  assert_eq(line_box_top(32.0 + 5.0 + 8.5, 32.0, 27.0), 32.0)
  assert_eq(line_box_top(32.0 + 27.0 * 3.0 + 5.0 + 8.5, 32.0, 27.0), 113.0)
  // A taller fallback glyph starts above its line but is centred within it.
  assert_eq(line_box_top(32.0 + 27.0 + 13.5, 32.0, 27.0), 59.0)
}
