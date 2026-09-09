///|
// Reuse the original lifecycle command harness: mutable fields belong only to
// the test's imperative event-dispatch shell, not the lifecycle reducer.
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
#warnings("-alert_unstable")
fn render_lifecycle_state(state : State) -> String {
  @rabbita_testing.server_side_render(() => state.view())
}

///|
async test "hidden commands preserve parser and latest arbitrary edits catch up once" {
  let engine = PreviewEngine::PreviewEngine()
  assert_true(engine.activate_generation(1))
  guard engine.prepare_owned(1, "# Previous\n") is Some(Ok(output)) else {
    fail("prepare")
  }
  assert_true(engine.accept(output))
  guard engine.state is Healthy(parser=retained, ..) else { fail("healthy") }
  let harness = LifecycleCmdHarness::{
    engine,
    state: test_state(
      false,
      Ready(completed_preview(Input(1, "# Previous\n"), output)),
    ),
    current: Input(1, "# Previous\n"),
  }
  for source in ["# A\n", "# B界\n", "# Latest😀\n"] {
    harness.current = Input(1, source)
    let (state, command) = engine.document_changed(
      harness.state,
      harness.current,
      @text_change.ReplaceAll(source),
      harness.emit(),
    )
    harness.state = state
    @rabbita_testing.run_cmd(command)
    guard engine.state is Healthy(parser~, source=stored, ..) else {
      fail("lost cache")
    }
    assert_true(physical_equal(parser, retained))
    assert_eq(stored, "# Previous\n")
  }
  let (requested, _) = engine.request(
    harness.state,
    harness.current,
    harness.emit(),
  )
  harness.state = requested
  // Drive the scalar event after the paint boundary; browser tests cover the
  // actual requestAnimationFrame/timer wiring.
  let (awake, command) = engine.update(
    harness.state,
    harness.current,
    { kind: Wakeup(1, requested.wake_ticket) },
    harness.emit(),
  )
  harness.state = awake
  @rabbita_testing.run_cmd(command)
  guard engine.state is Healthy(parser~, source~, ..) else { fail("catch up") }
  assert_true(physical_equal(parser, retained))
  assert_eq(source, "# Latest😀\n")
  assert_false(harness.state.dirty)
  let html = render_lifecycle_state(harness.state)
  assert_true(html.contains("Latest😀"))
  assert_false(html.contains("Previous"))
}

///|
async test "one exact edit survives hidden demand and retains unaffected lazy key" {
  let engine = PreviewEngine::PreviewEngine()
  assert_true(engine.activate_generation(1))
  let old = "Alpha.\n\nBeta.\n"
  guard engine.prepare_owned(1, old) is Some(Ok(output)) else {
    fail("prepare")
  }
  assert_true(engine.accept(output))
  let key = engine.accepted_render.unwrap().lazy_keys[0]
  let pos = old.find("Beta").unwrap()
  let change = @text_change.ReplaceRange(start=pos, delete_len=1, inserted="Z")
  let current = Input(1, change.apply(old).unwrap())
  let harness = LifecycleCmdHarness::{
    engine,
    state: test_state(false, Ready(completed_preview(Input(1, old), output))),
    current,
  }
  let (dirty, command) = engine.document_changed(
    harness.state,
    current,
    change,
    harness.emit(),
  )
  harness.state = dirty
  @rabbita_testing.run_cmd(command)
  let (requested, _) = engine.request(harness.state, current, harness.emit())
  let (awake, catchup) = engine.update(
    requested,
    current,
    { kind: Wakeup(1, requested.wake_ticket) },
    harness.emit(),
  )
  harness.state = awake
  @rabbita_testing.run_cmd(catchup)
  assert_true(render_lifecycle_state(harness.state).contains("Zeta"))
  assert_eq(engine.accepted_render.unwrap().lazy_keys[0], key)
}

///|
async test "stale generation and superseded same-generation wake have no effect" {
  let engine = PreviewEngine::PreviewEngine()
  let old = Input(1, "old")
  assert_true(engine.activate_generation(1))
  let pending = preview_transition(
    test_state(
      true,
      Ready({ document_text: "a", html: @html.p("a"), empty: false }),
    ),
    old,
    DocumentChanged(@text_change.ReplaceAll("old")),
  )
  let suspended = preview_transition(pending.state, old, Suspended)
  let requested = preview_transition(suspended.state, old, Requested)
  let obsolete = preview_transition(
    requested.state,
    old,
    Complete(Wakeup(1, pending.state.wake_ticket)),
  )
  assert_true(obsolete.decision is NoCommand)
  assert_true(obsolete.state.wake_scheduled)
  assert_true(engine.activate_generation(2))
  let (state, command) = engine.update(
    initial_state(),
    Input(2, "new"),
    { kind: Wakeup(1, pending.state.wake_ticket) },
    lifecycle_emit(),
  )
  @rabbita_testing.run_cmd(command)
  assert_true(state.phase is Unrequested)
  assert_true(engine.state is NoPair)
}

///|
test "equal-text ABA catchup reuses healthy parser without demanding edit history" {
  let engine = PreviewEngine::PreviewEngine()
  guard engine.prepare("# A\n") is Ok(output) else { fail("prepare") }
  assert_true(engine.accept(output))
  guard engine.state is Healthy(parser=before, ..) else { fail("healthy") }
  let count = before.snapshot().read_or_abort().reuse_count
  guard engine.catch_up("# A\n", None) is Ok(current) else { fail("ABA") }
  assert_true(engine.accept(current))
  guard engine.state is Healthy(parser=after, source~, ..) else {
    fail("healthy")
  }
  assert_true(physical_equal(before, after))
  assert_eq(after.snapshot().read_or_abort().reuse_count, count)
  assert_eq(source, "# A\n")
}

///|
test "Preview view preserves stale output and distinguishes first failure" {
  let failed = render_lifecycle_state(test_state(true, Failed(None)))
  assert_true(failed.contains("role=\"alert\""))
  let stale = render_lifecycle_state(
    test_state(
      true,
      Failed(
        Some({
          document_text: "old",
          html: @html.p("Previous preview"),
          empty: false,
        }),
      ),
    ),
  )
  assert_true(stale.contains("Showing the last completed preview."))
  assert_true(stale.contains("Previous preview"))
}

///|
async test "stale preparation command recovers latest source without dropping healthy cache" {
  let engine = PreviewEngine::PreviewEngine()
  assert_true(engine.activate_generation(1))
  let a = Input(1, "# Candidate A\n")
  let b = Input(1, "# Current B\n")
  let requested = preview_transition(initial_state(), a, Requested)
  let begun = preview_transition(
    requested.state,
    a,
    Complete(BeginPreparation(1, requested.state.wake_ticket)),
  )
  guard engine.prepare_owned(1, a.document_text) is Some(Ok(output)) else {
    fail("prepare A")
  }
  guard engine.state is Healthy(parser=retained, ..) else { fail("healthy A") }
  let retry = preview_transition(
    begun.state,
    b,
    Complete(Prepared(a, Ok(output))),
  )
  assert_true(retry.decision is BeginPreparationAfterPaint(_, _))
  let harness = LifecycleCmdHarness::{ engine, state: retry.state, current: b }
  @rabbita_testing.run_cmd(
    harness.emit()({ kind: BeginPreparation(1, retry.state.wake_ticket) }),
  )
  assert_true(harness.state.phase is Ready(_))
  guard engine.state is Healthy(parser~, source~, ..) else { fail("healthy B") }
  assert_true(physical_equal(parser, retained))
  assert_eq(source, b.document_text)
  assert_true(render_lifecycle_state(harness.state).contains("Current B"))
  assert_false(render_lifecycle_state(harness.state).contains("Candidate A"))
}

///|
test "stale same-generation completion leaves the current candidate admissible" {
  let engine = PreviewEngine::PreviewEngine()
  assert_true(engine.activate_generation(1))
  let a = Input(1, "# A\n")
  let b = Input(1, "# B\n")
  guard engine.prepare_owned(1, a.document_text) is Some(Ok(output_a)) else {
    fail("A")
  }
  assert_true(engine.accept(output_a))
  let dirty = preview_transition(
    test_state(true, Ready(completed_preview(a, output_a))),
    b,
    DocumentChanged(@text_change.ReplaceAll(b.document_text)),
  )
  guard engine.catch_up_owned(1, b.document_text, None) is Some(Ok(output_b)) else {
    fail("B")
  }
  let stale = preview_transition(
    dirty.state,
    b,
    Complete(Refreshed(a, Ok(output_a))),
  )
  assert_true(stale.decision is NoCommand)
  assert_eq(stale.state.wake_ticket, dirty.state.wake_ticket)
  assert_true(stale.state.wake_scheduled)
  assert_false(stale.state.busy)
  assert_eq(stale.state.pending_change, None)
  let (accepted, _) = engine.update(
    stale.state,
    b,
    { kind: Refreshed(b, Ok(output_b)) },
    lifecycle_emit(),
  )
  assert_true(
    accepted.phase is Ready(preview) && preview.document_text == b.document_text,
  )
}

///|
test "equal-input ABA preparation remains admissible after intermediate document text" {
  let engine = PreviewEngine::PreviewEngine()
  assert_true(engine.activate_generation(1))
  let a = Input(1, "# A\n")
  let requested = preview_transition(initial_state(), a, Requested)
  let begun = preview_transition(
    requested.state,
    a,
    Complete(BeginPreparation(1, requested.state.wake_ticket)),
  )
  guard engine.prepare_owned(1, a.document_text) is Some(Ok(output)) else {
    fail("A")
  }
  let b = preview_transition(
    begun.state,
    Input(1, "# B\n"),
    DocumentChanged(@text_change.ReplaceAll("# B\n")),
  )
  let aba = preview_transition(
    b.state,
    a,
    DocumentChanged(@text_change.ReplaceAll(a.document_text)),
  )
  let (accepted, _) = engine.update(
    aba.state,
    a,
    { kind: Prepared(a, Ok(output)) },
    lifecycle_emit(),
  )
  assert_true(
    accepted.phase is Ready(preview) && preview.document_text == a.document_text,
  )
}
