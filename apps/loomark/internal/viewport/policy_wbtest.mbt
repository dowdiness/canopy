///|
test "caret resize preserves a line exactly within the padded viewport" {
  assert_eq(caret_scroll_top(100.0, 170.0, 86.0, 200.0, 14.0, 16.0), 86.0)
}

///|
test "caret resize reveals a line below the viewport with bottom padding" {
  assert_eq(caret_scroll_top(270.0, 30.0, 86.0, 200.0, 14.0, 16.0), 116.0)
}

///|
test "caret resize reveals a line above the viewport with top padding" {
  assert_eq(caret_scroll_top(60.0, 30.0, 86.0, 200.0, 14.0, 16.0), 46.0)
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
