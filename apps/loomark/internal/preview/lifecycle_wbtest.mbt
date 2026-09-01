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
test "suspend fences preparation before after-paint work" {
  let engine = PreviewEngine::PreviewEngine()
  let input = Input(1, "# Current\n")
  let (initial, _) = engine.activate(input)
  let (preparing, _) = engine.request(initial, input, lifecycle_emit())
  assert_true(preparing.phase is Preparing)
  assert_true(preparing.demanded)
  let (suspended, command) = engine.suspend(preparing, input)
  assert_true(suspended.phase is Unrequested)
  assert_false(suspended.demanded)
  let delayed = preview_transition(
    suspended,
    input,
    Complete(BeginPreparation(input.generation)),
  )
  assert_true(delayed.state == suspended)
  assert_true(delayed.decision is NoCommand)
  ignore(command)
}

///|
test "suspended Preview advances Parser and catches up once requested" {
  let engine = PreviewEngine::PreviewEngine()
  let previous = Input(1, "# Previous\n")
  let visible : State = {
    demanded: true,
    phase: Ready({
      document_text: previous.document_text,
      html: @html.p("Previous"),
      empty: false,
    }),
  }
  let (suspended, _) = engine.suspend(visible, previous)
  let current = Input(1, "# Current\n")
  let change = @text_change.TextChange::ReplaceAll(current.document_text)
  let changed = preview_transition(suspended, current, DocumentChanged(change))
  assert_true(changed.decision is Apply(_, _, _))
  let advanced = preview_transition(
    changed.state,
    current,
    Complete(ParserAdvanced(current, false, Ok(()))),
  )
  assert_true(advanced.decision is NoCommand)
  let delayed = preview_transition(
    advanced.state,
    current,
    Complete(RefreshRequested(current)),
  )
  assert_true(delayed.decision is NoCommand)
  let requested = preview_transition(advanced.state, current, Requested)
  assert_true(requested.decision is Refresh(input) && input == current)
}

///|
test "older activation completion cannot affect current Preview state" {
  let engine = PreviewEngine::PreviewEngine()
  let state : State = { phase: Preparing, demanded: true }
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
    { phase: Preparing, demanded: true },
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
  let preparing : State = { phase: Preparing, demanded: true }
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
    { phase: Preparing, demanded: true },
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
    { phase: Preparing, demanded: true },
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
async test "suspended Parser catches Preview up to the latest Document text" {
  let engine = PreviewEngine::PreviewEngine()
  let previous = Input(1, "# Previous\n")
  assert_true(engine.activate_generation(previous.generation))
  guard engine.prepare_owned(previous.generation, previous.document_text)
    is Some(Ok(output)) else {
    fail("previous Preview should prepare")
  }
  assert_true(engine.accept(output))
  let visible : State = {
    demanded: true,
    phase: Ready(completed_preview(previous, output)),
  }
  let (suspended, _) = engine.suspend(visible, previous)
  let harness = LifecycleCmdHarness::{
    engine,
    state: suspended,
    current: Input(1, "# Current\n"),
  }
  let (changed, apply_command) = engine.document_changed(
    harness.state,
    harness.current,
    @text_change.TextChange::ReplaceAll(harness.current.document_text),
    harness.emit(),
  )
  harness.state = changed
  @rabbita_testing.run_cmd(apply_command)
  guard engine.state is Healthy(source~, ..) else {
    fail("suspended Parser should stay healthy")
  }
  assert_eq(source, harness.current.document_text)
  let (requested, refresh_command) = engine.request(
    harness.state,
    harness.current,
    harness.emit(),
  )
  harness.state = requested
  @rabbita_testing.run_cmd(refresh_command)
  let rendered = render_lifecycle_state(harness.state)
  assert_true(rendered.contains("Current"))
  assert_false(rendered.contains("Previous"))
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
  let failed = render_lifecycle_state({ phase: Failed(None), demanded: true })
  assert_true(failed.contains("role=\"alert\""))
  assert_true(failed.contains("Preview could not be prepared."))

  let stale = render_lifecycle_state({
    demanded: true,
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
