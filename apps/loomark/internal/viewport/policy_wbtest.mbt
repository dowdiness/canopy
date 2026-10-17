///|
test "a line exactly within the readable area stays put" {
  assert_eq(fitted_top(14.0, 170.0, 14.0, 184.0), 14.0)
}

///|
test "a line below the readable area moves up to its bottom" {
  assert_eq(fitted_top(184.0, 30.0, 14.0, 184.0), 154.0)
}

///|
test "a line above the readable area moves down to its top" {
  assert_eq(fitted_top(-26.0, 30.0, 14.0, 184.0), 14.0)
}

///|
test "line reference locates characters, line ends, and empty lines" {
  let text = "ab\n\ncd\n"
  assert_eq(line_reference(text, 0), Some((0, 0)))
  // The end of a line uses the character before the line break.
  assert_eq(line_reference(text, 2), Some((1, 0)))
  // The empty line and the end of the text count lines below "b" and "d".
  assert_eq(line_reference(text, 3), Some((1, 1)))
  assert_eq(line_reference(text, 4), Some((4, 0)))
  assert_eq(line_reference(text, 7), Some((5, 1)))
  // Leading empty lines count upward from the first character.
  assert_eq(line_reference("\n\nab", 0), Some((2, -2)))
  assert_eq(line_reference("\n\nab", 1), Some((2, -1)))
  assert_eq(line_reference("\n\n", 1), None)
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
  assert_true(bottom_bar_obscured(380.0, 844.0, 844.0))
  // A small unobscured window or hardware-keyboard viewport keeps its controls.
  assert_false(bottom_bar_obscured(360.0, 360.0, 360.0))
  assert_false(bottom_bar_obscured(844.0, 844.0, 844.0))
}

///|
test "bottom bar tolerates subpixel height differences" {
  assert_false(bottom_bar_obscured(843.5, 844.0, 844.0))
  assert_false(bottom_bar_obscured(843.0, 844.0, 844.0))
  assert_true(bottom_bar_obscured(842.9, 844.0, 844.0))
}

///|
test "content resizing hides the bar until keyboard height recovers" {
  for
    (height, hidden) in [
      (448.0, true),
      (420.0, true),
      (635.0, false),
      (448.0, true),
    ]
    baseline = 635.0 {
    let next = viewport_baseline_height(
      baseline, 800.0, 360.0, height, 800.0, 360.0,
    )
    assert_eq(bottom_bar_obscured(height, height, next), hidden)
    continue next
  }
}

///|
test "window height resizing is not mistaken for a keyboard" {
  for
    (height, outer, hidden) in [
      (335.0, 500.0, false),
      (735.0, 900.0, false),
      (448.0, 900.0, true),
      // Growing the window while the keyboard remains open preserves the deficit.
      (548.0, 1000.0, true),
      (835.0, 1000.0, false),
    ]
    baseline = 635.0, previous_outer = 800.0 {
    let next = viewport_baseline_height(
      baseline, previous_outer, 360.0, height, outer, 360.0,
    )
    assert_eq(bottom_bar_obscured(height, height, next), hidden)
    continue next, outer
  }
}

///|
test "browser controls and width changes do not retain a keyboard estimate" {
  for
    (height, outer, width, hidden) in [
      (664.0, 800.0, 360.0, false),
      (635.0, 800.0, 360.0, false),
      (448.0, 800.0, 360.0, true),
      (243.0, 360.0, 800.0, false),
      (635.0, 800.0, 360.0, false),
    ]
    baseline = 635.0, previous_outer = 800.0, previous_width = 360.0 {
    let next = viewport_baseline_height(
      baseline, previous_outer, previous_width, height, outer, width,
    )
    assert_eq(bottom_bar_obscured(height, height, next), hidden)
    continue next, outer, width
  }
}

///|
test "unavailable outer height resets rather than retaining keyboard occlusion" {
  assert_eq(
    viewport_baseline_height(635.0, 800.0, 360.0, 448.0, 0.0, 360.0),
    448.0,
  )
  assert_eq(
    viewport_baseline_height(635.0, 0.0, 360.0, 448.0, 800.0, 360.0),
    448.0,
  )
}

///|
test "a glyph locates the top of its line box" {
  // 17 px glyphs in 27 px lines sit 5 px below the line's top.
  assert_eq(line_box_top(32.0 + 5.0 + 8.5, 32.0, 27.0), 32.0)
  assert_eq(line_box_top(32.0 + 27.0 * 3.0 + 5.0 + 8.5, 32.0, 27.0), 113.0)
  // A taller fallback glyph starts above its line but is centred within it.
  assert_eq(line_box_top(32.0 + 27.0 + 13.5, 32.0, 27.0), 59.0)
}

///|
test "Split maps reading position across unequal scroll ranges" {
  assert_eq(
    split_scroll_top(300.0, 800.0, 200.0, 0.0, 1200.0, 400.0),
    Some(400.0),
  )
  assert_eq(
    split_scroll_top(800.0, 1200.0, 400.0, 0.0, 800.0, 200.0),
    Some(600.0),
  )
}

///|
test "Split leaves non-scrolling panes and subpixel echoes unchanged" {
  assert_eq(split_scroll_top(0.0, 200.0, 200.0, 40.0, 800.0, 200.0), None)
  assert_eq(split_scroll_top(300.0, 800.0, 200.0, 0.0, 400.0, 400.0), None)
  assert_eq(split_scroll_top(300.0, 800.0, 200.0, 399.5, 1200.0, 400.0), None)
  assert_eq(
    split_scroll_top(300.0, 800.0, 200.0, 399.0, 1200.0, 400.0),
    Some(400.0),
  )
}
