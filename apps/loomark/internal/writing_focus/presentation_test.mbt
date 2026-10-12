///|
test "first presentation settles without animation" {
  let writing : @writing_focus.Presentation = {
    range: @writing_focus.Range(80.0, 120.0),
    engaged: true,
    reduced_motion: false,
  }
  match writing.dimming(None, geometry_changed=false) {
    @writing_focus.Dimming::Immediate(range) => {
      assert_eq(range.start, 80.0)
      assert_eq(range.end, 120.0)
    }
    _ => fail("initial writing focus must settle immediately")
  }
  let reading = { ..writing, engaged: false, }
  match reading.dimming(None, geometry_changed=true) {
    @writing_focus.Dimming::Immediate(range) => {
      assert_eq(range.start, 0.0)
      assert_eq(range.end, @double.infinity)
    }
    _ => fail("initial reading must leave the whole document clear")
  }
}

///|
test "selection fades but geometry changes settle even at the same coordinates" {
  let previous : @writing_focus.Presentation = {
    range: @writing_focus.Range(80.0, 120.0),
    engaged: true,
    reduced_motion: false,
  }
  assert_true(
    previous.dimming(Some(previous), geometry_changed=false)
    is @writing_focus.Dimming::Unchanged,
  )
  let moved = { ..previous, range: @writing_focus.Range(120.0, 180.0), }
  match moved.dimming(Some(previous), geometry_changed=false) {
    @writing_focus.Dimming::Animated(range) => {
      assert_eq(range.start, 120.0)
      assert_eq(range.end, 180.0)
    }
    _ => fail("selection movement must animate")
  }
  for current in [previous, moved] {
    match current.dimming(Some(previous), geometry_changed=true) {
      @writing_focus.Dimming::Immediate(range) => {
        assert_eq(range.start, current.range.start)
        assert_eq(range.end, current.range.end)
      }
      _ => fail("source or layout changes must settle without a selection fade")
    }
  }
}

///|
test "entering and leaving writing fade even when geometry changes" {
  let writing : @writing_focus.Presentation = {
    range: @writing_focus.Range(80.0, 120.0),
    engaged: true,
    reduced_motion: false,
  }
  let reading = { ..writing, engaged: false, }
  for geometry_changed in [false, true] {
    match writing.dimming(Some(reading), geometry_changed~) {
      @writing_focus.Dimming::Animated(range) => {
        assert_eq(range.start, 80.0)
        assert_eq(range.end, 120.0)
      }
      _ => fail("entering writing must fade around the selected text")
    }
    match reading.dimming(Some(writing), geometry_changed~) {
      @writing_focus.Dimming::Animated(range) => {
        assert_eq(range.start, 0.0)
        assert_eq(range.end, @double.infinity)
      }
      _ => fail("leaving writing must fade back to a clear document")
    }
  }
  let moved_while_reading = {
    ..reading,
    range: @writing_focus.Range(120.0, 180.0),
  }
  assert_true(
    moved_while_reading.dimming(Some(reading), geometry_changed=false)
    is @writing_focus.Dimming::Unchanged,
  )
}

///|
test "reduced motion takes precedence over selection and engagement fades" {
  let previous : @writing_focus.Presentation = {
    range: @writing_focus.Range(80.0, 120.0),
    engaged: true,
    reduced_motion: false,
  }
  let reduced = { ..previous, reduced_motion: true, }
  let moved = { ..reduced, range: @writing_focus.Range(120.0, 180.0), }
  let reading = { ..reduced, engaged: false, }
  for current in [reduced, moved, reading] {
    for geometry_changed in [false, true] {
      match current.dimming(Some(previous), geometry_changed~) {
        @writing_focus.Dimming::Immediate(range) =>
          if current.engaged {
            assert_eq(range.start, current.range.start)
            assert_eq(range.end, current.range.end)
          } else {
            assert_eq(range.start, 0.0)
            assert_eq(range.end, @double.infinity)
          }
        _ => fail("reduced motion must settle every presentation change")
      }
    }
  }
  match previous.dimming(Some(reduced), geometry_changed=false) {
    @writing_focus.Dimming::Animated(range) => {
      assert_eq(range.start, 80.0)
      assert_eq(range.end, 120.0)
    }
    _ => fail("restoring motion must re-evaluate the current presentation")
  }
}
