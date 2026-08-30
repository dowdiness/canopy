///|
fn lifecycle_emit() -> @cmd.Emit[Event] {
  @cmd.Emit(_ => @cmd.none)
}

///|
#warnings("-alert_unstable")
fn render_lifecycle_state(state : State) -> String {
  @rabbita_testing.server_side_render(() => state.view())
}

///|
test "request exposes Preparing before cold preparation" {
  let engine = PreviewEngine::PreviewEngine()
  let input = Input(1, "# Current\n")
  let (initial, _) = engine.activate(input)
  let (preparing, command) = engine.request(initial, input, lifecycle_emit())
  let rendered = render_lifecycle_state(preparing)
  assert_true(rendered.contains("role=\"status\""))
  assert_true(rendered.contains("Preparing preview…"))
  ignore(command)
}

///|
test "older activation completion cannot affect current Preview state" {
  let engine = PreviewEngine::PreviewEngine()
  let state : State = { phase: Preparing }
  let stale = Input(1, "# Old document\n")
  let current = Input(2, "# Current document\n")
  let (after, _) = engine.update(
    state,
    current,
    { kind: Prepared(stale, Err(OutOfSync)) },
    lifecycle_emit(),
  )
  assert_true(after == state)
}

///|
test "same-activation stale Parser completion cannot affect current Input" {
  let engine = PreviewEngine::PreviewEngine()
  assert_true(engine.activate_generation(1))
  let input_a = Input(1, "# Candidate A\n")
  guard engine.prepare_owned(1, input_a.document_text) is Some(Ok(output)) else {
    fail("candidate A should prepare")
  }
  let (ready, _) = engine.update(
    { phase: Preparing },
    input_a,
    { kind: Prepared(input_a, Ok(output)) },
    lifecycle_emit(),
  )
  let input_b = Input(1, "# Current B\n")
  for result in [Ok(()), Err(Unusable)] {
    let (after, _) = engine.update(
      ready,
      input_b,
      { kind: ParserAdvanced(input_a, true, result) },
      lifecycle_emit(),
    )
    assert_true(after == ready)
  }
}

///|
test "A-B-A admits an equal-input preparation and Parser completion" {
  let engine = PreviewEngine::PreviewEngine()
  assert_true(engine.activate_generation(1))
  let first_a = Input(1, "# A\n")
  guard engine.prepare_owned(1, first_a.document_text) is Some(Ok(output)) else {
    fail("first A should prepare")
  }
  let preparing : State = { phase: Preparing }
  let input_b = Input(1, "# B\n")
  let (after_b, _) = engine.document_changed(
    preparing,
    input_b,
    @text_change.ReplaceAll(input_b.document_text),
    lifecycle_emit(),
  )
  let current_a = Input(1, "# A\n")
  let (after_a, _) = engine.document_changed(
    after_b,
    current_a,
    @text_change.ReplaceAll(current_a.document_text),
    lifecycle_emit(),
  )
  assert_true(first_a != input_b)
  assert_true(first_a == current_a)
  let (ready, _) = engine.update(
    after_a,
    current_a,
    { kind: Prepared(first_a, Ok(output)) },
    lifecycle_emit(),
  )
  assert_true(ready.phase is Ready(_))

  let (after_success, _) = engine.update(
    ready,
    current_a,
    { kind: ParserAdvanced(first_a, false, Ok(())) },
    lifecycle_emit(),
  )
  assert_true(after_success == ready)

  let (after_failure, _) = engine.update(
    ready,
    current_a,
    { kind: ParserAdvanced(first_a, false, Err(TransitionFailed)) },
    lifecycle_emit(),
  )
  assert_true(after_failure.phase is Failed(Some(_)))
}

///|
test "preparation completed for stale text converges on current Input" {
  let engine = PreviewEngine::PreviewEngine()
  assert_true(engine.activate_generation(1))
  let input_a = Input(1, "# Candidate A\n")
  guard engine.prepare_owned(1, input_a.document_text) is Some(Ok(output)) else {
    fail("candidate A should prepare")
  }
  let input_b = Input(1, "# Current B\n")
  let (state, _) = engine.update(
    { phase: Preparing },
    input_b,
    { kind: Prepared(input_a, Ok(output)) },
    lifecycle_emit(),
  )
  assert_true(state.phase is Failed(None))
}

///|
test "pure reducer decides stale preparation recovery without PreviewEngine" {
  let input_a = Input(1, "# Candidate A\n")
  let current_b = Input(1, "# Current B\n")
  let transition = preview_transition(
    { phase: Preparing },
    current_b,
    Complete(Prepared(input_a, Err(OutOfSync))),
  )
  assert_true(transition.state.phase is Failed(None))
  assert_true(
    transition.decision is DiscardAndScheduleRefresh(input) &&
    input == current_b,
  )
}

///|
priv struct LifecycleCmdHarness {
  engine : PreviewEngine
  mut state : State
  mut current : Input
}

///|
fn LifecycleCmdHarness::emit(self : LifecycleCmdHarness) -> @cmd.Emit[Event] {
  @cmd.Emit(event => {
    @cmd.custom_cmd(scheduler => {
      let (state, command) = self.engine.update(
        self.state,
        self.current,
        event,
        self.emit(),
      )
      self.state = state
      scheduler.add(command)
    })
  })
}

///|
async test "stale preparation command converges current Preview to Ready" {
  let engine = PreviewEngine::PreviewEngine()
  let input_a = Input(1, "# Candidate A\n")
  let (initial, activate_command) = engine.activate(input_a)
  @rabbita_testing.run_cmd(activate_command)
  let harness = LifecycleCmdHarness::{
    engine,
    state: initial,
    current: input_a,
  }
  let (preparing, _) = engine.request(initial, input_a, harness.emit())
  harness.state = preparing
  let (still_preparing, preparation_command) = engine.update(
    harness.state,
    harness.current,
    { kind: BeginPreparation(input_a.generation) },
    harness.emit(),
  )
  harness.state = still_preparing
  let current_b = Input(1, "# Current B\n")
  let make_preparation_stale = @cmd.custom_cmd(_ => harness.current = current_b)

  @rabbita_testing.run_cmd(
    @cmd.batch([preparation_command, make_preparation_stale]),
  )

  assert_true(harness.state.phase is Ready(_))
  let rendered = render_lifecycle_state(harness.state)
  assert_true(rendered.contains("Current B"))
  assert_false(rendered.contains("Candidate A"))
}

///|
test "Preview view distinguishes initial failure and retained stale Preview" {
  let failed = render_lifecycle_state({ phase: Failed(None) })
  assert_true(failed.contains("role=\"alert\""))
  assert_true(failed.contains("Preview could not be prepared."))

  let stale = render_lifecycle_state({
    phase: Failed(
      Some({
        document_text: "# Previous\n",
        html: @html.p("Previous preview"),
        empty: false,
      }),
    ),
  })
  assert_true(stale.contains("Showing the last completed preview."))
  assert_true(stale.contains("Previous preview"))
}
