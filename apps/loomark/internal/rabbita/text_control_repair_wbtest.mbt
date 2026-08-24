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
test "rejected Raw repair maps canonical lone CR to textarea LF offsets" {
  let selection = rejected_text_selection(
    "a\rb",
    "a\nbx",
    @dom_boundary.TextSelection(4, 4, @dom_boundary.NoDirection),
  )
  assert_eq(selection.start(), 3)
  assert_eq(selection.end(), 3)
}

///|
test "Raw fast source and composition state are browser-owned" {
  let coordinator = RawInputCoordinator::RawInputCoordinator()
  coordinator.set_fast_source("draft")
  assert_eq(coordinator.fast_source_value(), Some("draft"))
  assert_false(coordinator.fast_composing())
  coordinator.begin_fast_composition()
  assert_true(coordinator.fast_composing())
  coordinator.finish_fast_composition()
  assert_false(coordinator.fast_composing())
}

///|
test "Raw draft generations distinguish A to B to A and navigation cancellation" {
  let coordinator = RawInputCoordinator::RawInputCoordinator()
  let first_a = coordinator.install_fast_source("A")
  let _ = coordinator.install_fast_source("B")
  let latest_a = coordinator.install_fast_source("A")
  assert_false(coordinator.draft_is_current(first_a))
  assert_true(coordinator.draft_is_current(latest_a))
  coordinator.cancel_pending_for_navigation()
  assert_false(coordinator.draft_is_current(latest_a))
}

///|
test "Raw draft generation wraps without arithmetic overflow" {
  let coordinator = RawInputCoordinator::RawInputCoordinator()
  coordinator.draft_generation.val = 0xFFFFFFFFFFFFFFFFUL
  let wrapped = coordinator.install_fast_source("draft")
  assert_eq(wrapped, 0UL)
  assert_true(coordinator.draft_is_current(wrapped))
}

///|
test "Raw coordinator without telemetry keeps phase snapshots empty" {
  let coordinator = RawInputCoordinator::RawInputCoordinator()
  guard coordinator.phase_json() is None else {
    fail("standalone Raw coordinator must not expose phase telemetry")
  }
}
