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
