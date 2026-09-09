///|
fn lifecycle_emit() -> @cmd.Emit[Event] {
  @cmd.Emit(_ => @cmd.none)
}

///|
fn test_state(demanded : Bool, phase : Phase) -> State {
  { ..initial_state(), demanded, phase }
}

///|
test "hidden text does not advance parser and demand schedules one wake" {
  let engine = PreviewEngine::PreviewEngine()
  let old = Input(1, "# old\n")
  let state = test_state(
    false,
    Ready({
      document_text: old.document_text,
      html: @html.p("old"),
      empty: false,
    }),
  )
  let change = @text_change.ReplaceRange(start=2, delete_len=3, inserted="new")
  let (hidden, command) = engine.document_changed(
    state,
    Input(1, "# new\n"),
    change,
    lifecycle_emit(),
  )
  assert_true(hidden.dirty)
  assert_true(hidden.pending_change is Some(_))
  ignore(command)
  assert_true(engine.state is NoPair)
  let (demanded, wake) = engine.request(
    hidden,
    Input(1, "# new\n"),
    lifecycle_emit(),
  )
  assert_true(demanded.wake_scheduled)
  assert_true(demanded.pending_change is Some(_))
  ignore(wake)
}

///|
test "second edit degrades to latest source replacement" {
  let state = test_state(
    true,
    Ready({ document_text: "a", html: @html.p("a"), empty: false }),
  )
  let first = @text_change.ReplaceRange(start=1, delete_len=0, inserted="b")
  let second = @text_change.ReplaceRange(start=0, delete_len=1, inserted="c")
  let one = preview_transition(state, Input(1, "ab"), DocumentChanged(first))
  let two = preview_transition(
    one.state,
    Input(1, "cb"),
    DocumentChanged(second),
  )
  assert_true(one.state.pending_change is Some(_))
  assert_true(two.state.pending_change is None)
}

///|
test "stale wake and composition cannot catch up" {
  let state = test_state(
    true,
    Ready({ document_text: "a", html: @html.p("a"), empty: false }),
  )
  let pending = preview_transition(
    state,
    Input(1, "ab"),
    DocumentChanged(@text_change.ReplaceAll("ab")),
  )
  let stale = preview_transition(
    pending.state,
    Input(1, "ab"),
    Complete(Wakeup(1, pending.state.wake_ticket - 1)),
  )
  assert_true(stale.decision is NoCommand)
  let composing = preview_transition(
    pending.state,
    Input(1, "ab", composing=true),
    CompositionStarted,
  )
  assert_false(composing.state.wake_scheduled)
}

///|
test "preparation is after paint and resolves current input" {
  let state = test_state(false, Unrequested)
  let current = Input(7, "latest")
  let transition = preview_transition(state, current, Requested)
  assert_true(transition.decision is BeginPreparationAfterPaint(7, _))
  let next = preview_transition(
    transition.state,
    current,
    Complete(BeginPreparation(7, transition.state.wake_ticket)),
  )
  assert_true(next.decision is Prepare(_))
}

///|
test "failure retains previous preview" {
  let previous = { document_text: "old", html: @html.p("old"), empty: false }
  let state = test_state(true, Ready(previous))
  let transition = preview_transition(
    state,
    Input(1, "new"),
    Complete(Refreshed(Input(1, "new"), Err(TransitionFailed))),
  )
  guard transition.state.phase is Failed(Some(retained)) else {
    fail("last preview lost")
  }
  assert_eq(retained.document_text, "old")
}
