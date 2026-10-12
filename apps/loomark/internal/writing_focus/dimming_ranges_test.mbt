///|
test "moving focus preserves unchanged fades and reverses only the newly focused range" {
  let timing : @writing_focus.FadeTiming = {
    from_opacity: 0.0,
    to_opacity: 0.5,
    duration_ms: 220.0,
    easing: "linear",
  }
  let active = @writing_focus.ActiveFade::Running(
    timing,
    start_time_ms=100.0,
    current_time_ms=80.0,
    playback_rate=1.0,
  )
  let previous : Array[(@writing_focus.Range, @writing_focus.OpacitySample)] = [
    (@writing_focus.Range(0.0, 400.0), Animating(0.3, active)),
  ]
  let ranges = @writing_focus.calculate_dimming_ranges(
    @writing_focus.Range(100.0, 200.0),
    previous[:],
    Some(180.0),
    animate=true,
  )
  let (before_focus, before_fade) = ranges[0]
  let (focused_range, focused_fade) = ranges[1]
  let (_, after_fade) = ranges[2]
  assert_eq(before_focus.end, 100.0)
  assert_true(before_fade is Continue(_))
  assert_eq(focused_range.start, 100.0)
  assert_eq(focused_range.end, 200.0)
  guard focused_fade is Start(reversal) else {
    fail("Only the new focus reverses")
  }
  assert_eq(reversal.from_opacity, 0.3)
  assert_eq(reversal.to_opacity, 0.0)
  assert_true(after_fade is Continue(_))
}

///|
test "settled regions do not retain every previous focus boundary" {
  let previous : Array[(@writing_focus.Range, @writing_focus.OpacitySample)] = [
    (@writing_focus.Range(0.0, 100.0), Still(0.5)),
    (@writing_focus.Range(100.0, 200.0), Still(0.5)),
    (@writing_focus.Range(200.0, 300.0), Still(0.5)),
  ]
  let ranges = @writing_focus.calculate_dimming_ranges(
    @writing_focus.Range(300.0, 400.0),
    previous[:],
    None,
    animate=true,
  )
  let (settled_range, _) = ranges[0]
  assert_eq(settled_range.start, 0.0)
  assert_eq(settled_range.end, 300.0)
}
