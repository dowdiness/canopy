///|
test "a partly scrolled range uses viewport-relative coordinates" {
  let content_range = @writing_focus.Range(30.25, 80.75)
  let viewport_range = @writing_focus.Range(60.0, 160.0)
  let visible_range = @writing_focus.calculate_visible_range(
    content_range, viewport_range,
  ).unwrap()
  assert_eq(visible_range.start, 0.0)
  assert_eq(visible_range.end, 20.75)
}

///|
test "offscreen and zero-height ranges have no visible part" {
  for
    (start, end, scroll, height) in [
      (0.0, 60.0, 60.0, 100.0),
      (160.0, 200.0, 60.0, 100.0),
      (30.0, 80.0, 60.0, 0.0),
    ] {
    let content_range = @writing_focus.Range(start, end)
    let viewport_range = @writing_focus.Range(scroll, scroll + height)
    assert_true(
      @writing_focus.calculate_visible_range(content_range, viewport_range)
      is None,
    )
  }
}

///|
test "unordered endpoints cannot construct a range" {
  let result : Result[@writing_focus.Range, @writing_focus.InvalidRange] = Ok(
    @writing_focus.Range(20.0, 10.0),
  ) catch {
    error => Err(error)
  }
  assert_true(result is Err(_))
}

///|
test "focus reaching a document edge does not end inside that edge" {
  let text = @writing_focus.TextLines("Before\n\nWriting")
  let last = text.focus_lines(15, 15).unwrap()
  let (start, end) = @writing_focus.focus_boundaries(last, 3, 0, None, None)
  assert_eq(start, @writing_focus.LineStart(2))
  assert_eq(end, @writing_focus.Position(@double.infinity))
  let first = text.focus_lines(0, 0).unwrap()
  let (start, end) = @writing_focus.focus_boundaries(first, 3, 0, None, None)
  assert_eq(start, @writing_focus.Position(0.0))
  assert_eq(end, @writing_focus.LineEnd(0))
}

///|
test "editing a focused paragraph preserves only its unaffected boundaries" {
  let text = @writing_focus.TextLines("Before\n\nWriting\n\nAfter")
  let lines = text.focus_lines(8, 8).unwrap()
  let measured_start = Some((lines.first, 80.0))
  let measured_end = Some((lines.last, 120.0))
  let (start, end) = @writing_focus.focus_boundaries(
    lines, 5, 2, measured_start, measured_end,
  )
  assert_eq(start, @writing_focus.Position(80.0))
  assert_eq(end, @writing_focus.LineEnd(2))
  let (start, end) = @writing_focus.focus_boundaries(
    lines, 5, 3, measured_start, measured_end,
  )
  assert_eq(start, @writing_focus.Position(80.0))
  assert_eq(end, @writing_focus.Position(120.0))
  let (start, end) = @writing_focus.focus_boundaries(
    lines, 5, 1, measured_start, measured_end,
  )
  assert_eq(start, @writing_focus.LineStart(2))
  assert_eq(end, @writing_focus.LineEnd(2))
}

///|
test "adding a following paragraph gives the former last paragraph a lower boundary" {
  let before = @writing_focus.TextLines("Before\n\nWriting")
    .focus_lines(15, 15)
    .unwrap()
  let after = @writing_focus.TextLines("Before\n\nWriting\n\nAfter")
    .focus_lines(8, 8)
    .unwrap()
  let (start, end) = @writing_focus.focus_boundaries(
    after,
    5,
    2,
    Some((before.first, 80.0)),
    None,
  )
  assert_eq(start, @writing_focus.Position(80.0))
  assert_eq(end, @writing_focus.LineEnd(2))
}

///|
test "paragraph positions are not reused across focus or layout changes" {
  let text = @writing_focus.TextLines("Before\n\nWriting\n\nAfter")
  let middle = text.focus_lines(8, 8).unwrap()
  let last = text.focus_lines(17, 17).unwrap()
  let (start, end) = @writing_focus.focus_boundaries(
    last,
    5,
    5,
    Some((middle.first, 80.0)),
    Some((middle.last, 120.0)),
  )
  assert_eq(start, @writing_focus.LineStart(4))
  assert_eq(end, @writing_focus.Position(@double.infinity))
  let (start, end) = @writing_focus.focus_boundaries(middle, 5, 5, None, None)
  assert_eq(start, @writing_focus.LineStart(2))
  assert_eq(end, @writing_focus.LineEnd(2))
}

///|
test "restoring rendered text replaces the former EOF with an interior boundary" {
  let rendered = @writing_focus.TextLines("Before\n\nWriting\n\nAfter")
  let truncated = rendered.replace_text("Before\n\nWriting").unwrap().text_lines
  let previous_lines = truncated.focus_lines(15, 15).unwrap()
  let restored_lines = rendered.focus_lines(8, 8).unwrap()
  let (start, end) = @writing_focus.focus_boundaries(
    restored_lines,
    rendered.lines().length(),
    rendered.lines().length(),
    Some((previous_lines.first, 80.0)),
    None,
  )
  assert_eq(start, @writing_focus.Position(80.0))
  assert_eq(end, @writing_focus.LineEnd(2))
}
