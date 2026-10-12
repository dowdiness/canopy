///|
fn dimming_timing() -> @writing_focus.FadeTiming {
  { from_opacity: 0.0, to_opacity: 0.5, duration_ms: 220.0, easing: "linear", }
}

///|
test "leaving writing reverses dimming from the currently visible opacity" {
  let previous = @writing_focus.ActiveFade::Running(
    dimming_timing(),
    start_time_ms=100.0,
    current_time_ms=80.0,
    playback_rate=1.0,
  )
  let samples : Array[(@writing_focus.Range, @writing_focus.OpacitySample)] = [
    (@writing_focus.Range(0.0, 100.0), Animating(0.3, previous)),
  ]
  let ranges = @writing_focus.calculate_dimming_ranges(
    @writing_focus.Range(0.0, @double.infinity),
    samples[:],
    Some(180.0),
    animate=true,
  )
  guard ranges is [(range, Start(timing))] else {
    fail("A changed target must start a new fade")
  }
  assert_eq((range.start, range.end), (0.0, 100.0))
  assert_eq(timing.from_opacity, 0.3)
  assert_eq(timing.to_opacity, 0.0)
}

///|
test "an unchanged target preserves the original trajectory and deadline" {
  let previous = @writing_focus.ActiveFade::Running(
    dimming_timing(),
    start_time_ms=100.0,
    current_time_ms=80.0,
    playback_rate=1.0,
  )
  let samples : Array[(@writing_focus.Range, @writing_focus.OpacitySample)] = [
    (@writing_focus.Range(0.0, 100.0), Animating(0.3, previous)),
  ]
  let ranges = @writing_focus.calculate_dimming_ranges(
    @writing_focus.Range(100.0, @double.infinity),
    samples[:],
    Some(180.0),
    animate=true,
  )
  guard ranges is [(range, Continue(Running(timing, start_time_ms~, ..)))] else {
    fail("An unchanged target must not restart")
  }
  assert_eq((range.start, range.end), (0.0, 100.0))
  assert_eq(timing.from_opacity, 0.0)
  assert_eq(start_time_ms, 100.0)
  assert_eq(timing.duration_ms, 220.0)
}

///|
test "an expired fade is settled instead of being continued" {
  let previous = @writing_focus.ActiveFade::Running(
    dimming_timing(),
    start_time_ms=100.0,
    current_time_ms=80.0,
    playback_rate=2.0,
  )
  let samples : Array[(@writing_focus.Range, @writing_focus.OpacitySample)] = [
    (@writing_focus.Range(0.0, 100.0), Animating(0.3, previous)),
  ]
  let ranges = @writing_focus.calculate_dimming_ranges(
    @writing_focus.Range(100.0, @double.infinity),
    samples[:],
    Some(210.0),
    animate=true,
  )
  guard ranges is [(range, SetOpacity(opacity))] else {
    fail("A finished fade must not be recreated")
  }
  assert_eq((range.start, range.end), (0.0, 100.0))
  assert_eq(opacity, 0.5)
}

///|
test "a pending fade retains its trajectory before a start time exists" {
  let previous = @writing_focus.ActiveFade::Pending(
    dimming_timing(),
    current_time_ms=Some(0.0),
    playback_rate=1.0,
  )
  let samples : Array[(@writing_focus.Range, @writing_focus.OpacitySample)] = [
    (@writing_focus.Range(0.0, 100.0), Animating(0.5, previous)),
  ]
  let ranges = @writing_focus.calculate_dimming_ranges(
    @writing_focus.Range(100.0, @double.infinity),
    samples[:],
    Some(9000.0),
    animate=true,
  )
  guard ranges is [(range, Continue(Pending(timing, current_time_ms~, ..)))] else {
    fail("A pending fade is not a finished fade")
  }
  assert_eq((range.start, range.end), (0.0, 100.0))
  assert_eq(current_time_ms, Some(0.0))
  assert_eq(timing.from_opacity, 0.0)
}

///|
test "reduced motion settles even an in-flight fade" {
  let previous = @writing_focus.ActiveFade::Running(
    dimming_timing(),
    start_time_ms=100.0,
    current_time_ms=80.0,
    playback_rate=1.0,
  )
  let samples : Array[(@writing_focus.Range, @writing_focus.OpacitySample)] = [
    (@writing_focus.Range(0.0, 100.0), Animating(0.3, previous)),
  ]
  let ranges = @writing_focus.calculate_dimming_ranges(
    @writing_focus.Range(100.0, @double.infinity),
    samples[:],
    Some(180.0),
    animate=false,
  )
  guard ranges is [(range, SetOpacity(opacity))] else {
    fail("Motion suppression must cancel a running fade")
  }
  assert_eq((range.start, range.end), (0.0, 100.0))
  assert_eq(opacity, 0.5)
}
