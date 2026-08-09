///|
test "rejected insertion maps a non-BMP UTF-16 text cursor back to accepted source" {
  let selection = rejected_text_selection(
    "A😀B",
    "A😀XB",
    @dom_boundary.TextSelection(4, 4, @dom_boundary.NoDirection),
  )
  inspect(selection.start(), content="3")
  inspect(selection.end(), content="3")
}

///|
test "rejected replacement maps a range around the accepted span" {
  let selection = rejected_text_selection(
    "abcdef",
    "abXef",
    @dom_boundary.TextSelection(2, 3, @dom_boundary.Backward),
  )
  inspect(selection.start(), content="2")
  inspect(selection.end(), content="4")
  guard selection.direction() is @dom_boundary.Backward else {
    fail("expected selection direction to be preserved")
  }
}

///|
test "rejected Raw repair maps canonical CRLF to textarea LF offsets" {
  let selection = rejected_text_selection(
    "a\r\nb",
    "a\nbx",
    @dom_boundary.TextSelection(4, 4, @dom_boundary.NoDirection),
  )
  assert_eq(selection.start(), 3)
  assert_eq(selection.end(), 3)
}

///|
test "Raw coordinator without telemetry keeps phase snapshots empty" {
  let coordinator = RawInputCoordinator::RawInputCoordinator(None)
  guard coordinator.phase_json() is None else {
    fail("standalone Raw coordinator must not expose phase telemetry")
  }
}
