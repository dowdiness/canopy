///|
test "a partly scrolled shade sits in the viewport and keeps its content top" {
  let content_range = @writing_focus.Range(30.25, 80.75)
  let viewport_range = @writing_focus.Range(60.0, 160.0)
  let placement = @writing_focus.calculate_shade_placement(
    content_range, viewport_range,
  ).unwrap()
  assert_eq(placement.top_in_viewport, 0.0)
  assert_eq(placement.top_in_content, 60.0)
  assert_eq(placement.height, 20.75)
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
      @writing_focus.calculate_shade_placement(content_range, viewport_range)
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
