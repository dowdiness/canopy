///|
test "Raw Preview queue retains one active and only the latest pending source" {
  let state = RawPreviewQueueState::initial()
  let (state, first) = state.request("# One\n")
  assert_eq(first, RawPreviewQueueDecision::Dispatch("# One\n"))
  let (state, second) = state.request("# Two\n")
  assert_eq(second, RawPreviewQueueDecision::Wait)
  let (state, third) = state.request("# Three\n")
  assert_eq(third, RawPreviewQueueDecision::Wait)
  let (state, next) = state.complete("# One\n")
  assert_eq(next, RawPreviewQueueDecision::Dispatch("# Three\n"))
  let (_, done) = state.complete("# Three\n")
  assert_eq(done, RawPreviewQueueDecision::Wait)
}

///|
test "Raw Preview error callback drops failed queue and restarts current source" {
  let runtime = RawPreviewRuntime::new_in_process("raw-preview-recovery")
  let stamp = projection_worker_client_test_stamp(1)
  let (queue, _) = runtime.queue.request("# Active\n")
  let (queue, _) = queue.request("# Obsolete\n")
  runtime.queue = queue
  runtime.worker.seeded = true
  runtime.worker.source = "# Obsolete\n"
  runtime.worker.current_stamp = Some(stamp)
  runtime.worker.expected_request_id = Some(1)
  let coordinator = RawInputCoordinator::RawInputCoordinator()
  coordinator.set_fast_source("# Current\n")
  let editor = try! @markdown.MarkdownEditor(
    agent_id="raw-preview-error-callback",
    source="# Accepted\n",
  )
  let model = {
    ..test_model(try! editor.snapshot(), editor.version()),
    split_preview_open: true,
  }
  let emit : @cmd.Emit[DriverEvent] = @cmd.Emit(_ => @rabbita_runtime.none)
  let (_, _) = update_raw_preview_msg(
    ProjectionCompleted(
      1, stamp, "{\"schema_version\":\"1\",\"request_id\":1,\"kind\":\"error\",\"error\":{\"kind\":\"timeout\",\"detail\":\"timed out\"}}",
      "# Active\n",
    ),
    model,
    coordinator,
    Some(runtime),
    emit,
  )
  assert_false(runtime.worker.disposed)
  assert_eq(runtime.worker.restart_count, 1)
  assert_eq(runtime.queue.active, Some("# Current\n"))
  assert_eq(runtime.queue.latest, None)
}

///|
test "Raw Preview malformed success does not reset the restart budget" {
  let runtime = RawPreviewRuntime::new_in_process("raw-preview-mismatch")
  let stamp = projection_worker_client_test_stamp(3)
  let (queue, _) = runtime.queue.request("# Active\n")
  runtime.queue = queue
  runtime.worker.current_stamp = Some(stamp)
  runtime.worker.expected_request_id = Some(1)
  runtime.worker.restart_count = 1
  let dispatch = new_projection_worker_dispatcher()
  let raw = dispatch(
    projection_worker_request(
      1,
      projection_worker_seed_command("raw-preview-mismatch", "# Different\n", 3),
    ),
  )
  let emit : @cmd.Emit[DriverEvent] = @cmd.Emit(_ => @rabbita_runtime.none)
  let (claimed, result, _) = runtime.complete(1, stamp, raw, "# Active\n", emit)
  assert_true(claimed)
  assert_true(result is Some(Failed))
  assert_eq(runtime.worker.restart_count, 1)
  ignore(runtime.recover("# Current\n", emit))
  assert_true(runtime.worker.disposed)
}

///|
test "Raw Preview queue ignores duplicate and stale completion" {
  let state = RawPreviewQueueState::initial()
  let (state, _) = state.request("# Active\n")
  let (state, _) = state.request("# Superseded\n")
  let (state, duplicate) = state.request("# Active\n")
  assert_eq(duplicate, RawPreviewQueueDecision::Wait)
  let (state, stale) = state.complete("# Stale\n")
  assert_eq(stale, RawPreviewQueueDecision::Wait)
  let (_, completed) = state.complete("# Active\n")
  assert_eq(completed, RawPreviewQueueDecision::Wait)
}
