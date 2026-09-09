///|
test "demand regression: an edit during the quiet window postpones parsing" {
  let ready = test_state(
    true,
    Ready({ document_text: "a", html: @html.p("a"), empty: false }),
  )
  let first = preview_transition(
    ready,
    Input(1, "ab"),
    DocumentChanged(@text_change.ReplaceAll("ab")),
  )
  let second = preview_transition(
    first.state,
    Input(1, "abc"),
    DocumentChanged(@text_change.ReplaceAll("abc")),
  )
  assert_true(second.decision is NoCommand)
  let wake = preview_transition(
    second.state,
    Input(1, "abc"),
    Complete(Wakeup(1, first.state.wake_ticket)),
  )
  assert_true(wake.decision is ScheduleWake(_, _))
}

///|
test "demand regression: third edit cannot restore an exact delta" {
  let ready = test_state(
    false,
    Ready({ document_text: "a", html: @html.p("a"), empty: false }),
  )
  let first = preview_transition(
    ready,
    Input(1, "ab"),
    DocumentChanged(
      @text_change.ReplaceRange(start=1, delete_len=0, inserted="b"),
    ),
  )
  let second = preview_transition(
    first.state,
    Input(1, "abc"),
    DocumentChanged(
      @text_change.ReplaceRange(start=2, delete_len=0, inserted="c"),
    ),
  )
  let third = preview_transition(
    second.state,
    Input(1, "abcd"),
    DocumentChanged(
      @text_change.ReplaceRange(start=3, delete_len=0, inserted="d"),
    ),
  )
  assert_true(third.state.pending_change is None)
}

///|
test "demand regression: suspended preparation can be requested again" {
  let preparing = preview_transition(initial_state(), Input(1, "a"), Requested)
  let suspended = preview_transition(preparing.state, Input(1, "a"), Suspended)
  assert_true(suspended.state.phase is Unrequested)
  let requested = preview_transition(suspended.state, Input(1, "a"), Requested)
  assert_true(requested.decision is BeginPreparationAfterPaint(_, _))
}

///|
test "demand regression: composition prevents initial preparation" {
  let input = Input(1, "a", composing=true)
  let requested = preview_transition(initial_state(), input, Requested)
  assert_true(requested.decision is NoCommand)
}

///|
test "demand regression: stale preparation does not remain stuck preparing" {
  let preparing = preview_transition(initial_state(), Input(1, "a"), Requested)
  let stale = preview_transition(
    preparing.state,
    Input(1, "b"),
    Complete(Prepared(Input(1, "a"), Err(OutOfSync))),
  )
  assert_true(stale.decision is BeginPreparationAfterPaint(_, _))
  assert_true(stale.state.wake_ticket != preparing.state.wake_ticket)
}

///|
test "demand regression: failed output can retry equal text" {
  let failed = test_state(
    false,
    Failed(Some({ document_text: "a", html: @html.p("a"), empty: false })),
  )
  let retry = preview_transition(failed, Input(1, "a"), Requested)
  assert_true(retry.decision is BeginRefreshAfterPaint(_, _))
}
