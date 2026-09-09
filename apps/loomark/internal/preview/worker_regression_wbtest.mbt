///|
test "worker ACK uses request identity rather than parser output counter" {
  let server = WorkerServer::WorkerServer()
  let response = server.dispatch_text(
    "{\"type\":\"preview\",\"generation\":3,\"sequence\":40,\"source\":\"# A\"}",
  )
  assert_true(response.contains("\"blocks\""))
  assert_true(
    server
    .dispatch_text(
      "{\"type\":\"ack\",\"generation\":2,\"sequence\":40,\"accepted\":true}",
    )
    .contains("stale ack"),
  )
  assert_true(
    server
    .dispatch_text(
      "{\"type\":\"ack\",\"generation\":3,\"sequence\":40,\"accepted\":true}",
    )
    .contains("\"ack\""),
  )
  assert_true(
    server
    .dispatch_text(
      "{\"type\":\"preview\",\"generation\":3,\"sequence\":80,\"source\":\"# B\",\"edit\":{\"start\":2,\"delete_len\":1,\"inserted\":\"B\"}}",
    )
    .contains("\"blocks\""),
  )
}

///|
test "remote reuse distinguishes equal nodes from duplicate indexes" {
  let server = WorkerServer::WorkerServer()
  let client = PreviewEngine::PreviewEngine()
  assert_true(client.activate_generation(1))
  let input = Input(1, "Same.\n\nSame.\n")
  let packet = server.dispatch_text(
    "{\"type\":\"preview\",\"generation\":1,\"sequence\":0,\"source\":\"Same.\\n\\nSame.\\n\"}",
  )
  guard client.worker_output(input, 0, packet) is Ok(output) else {
    fail("first")
  }
  assert_true(client.accept(output))
  let before = client.accepted_render.unwrap().lazy_keys.copy()
  guard client.worker_output(
      input, 1, "{\"type\":\"preview\",\"generation\":1,\"sequence\":1,\"blocks\":[{\"reuse\":0},{\"reuse\":1}]}",
    )
    is Ok(next) else {
    fail("distinct equal nodes must reuse")
  }
  assert_true(client.accept(next))
  assert_eq(client.accepted_render.unwrap().lazy_keys, before)
  assert_true(
    client.worker_output(
      input, 2, "{\"type\":\"preview\",\"generation\":1,\"sequence\":2,\"blocks\":[{\"reuse\":0},{\"reuse\":0}]}",
    )
    is Err(_),
  )
  assert_eq(client.accepted_render.unwrap().lazy_keys, before)
}

///|
test "busy refresh coalesces changes and stale completion schedules latest input" {
  let old = Input(1, "A")
  let state = test_state(
    true,
    Ready({ document_text: "A", html: @html.p("A"), empty: false }),
  )
  let changed = preview_transition(
    state,
    Input(1, "B"),
    DocumentChanged(@text_change.ReplaceAll("B")),
  )
  let started = preview_transition(
    changed.state,
    Input(1, "B"),
    Complete(Wakeup(1, changed.state.wake_ticket)),
  )
  assert_true(started.state.busy)
  let newer = preview_transition(
    started.state,
    Input(1, "C"),
    DocumentChanged(@text_change.ReplaceAll("C")),
  )
  assert_true(newer.decision is NoCommand)
  let complete = preview_transition(
    newer.state,
    Input(1, "C"),
    Complete(Refreshed(old, Err(Unusable))),
  )
  assert_false(complete.state.busy)
  assert_true(complete.decision is ScheduleWake(_, _))
}

///|
test "zero-based ordered list DTO remains equivalent" {
  let engine = PreviewEngine::PreviewEngine()
  guard engine.prepare("0. zero\n1. one\n") is Ok(_) else { fail("prepare") }
  guard engine.state is Healthy(updates~, ..) else { fail("healthy") }
  let root = updates.document_update().document().root()
  let remote = decode_node(encode_node(root))
  let local = @rabbita_testing.server_side_render(() => render(root))
  let other = @rabbita_testing.server_side_render(() => {
    render_remote_node(remote)
  })
  assert_eq(local, other)
}
