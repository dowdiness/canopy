///|
test "disposed engine rejects activation and queued owned work" {
  let engine = PreviewEngine::PreviewEngine()
  assert_true(engine.activate_generation(1))
  guard engine.prepare_owned(1, "# Before") is Some(Ok(output)) else {
    fail("prepare")
  }
  engine.dispose()
  engine.dispose()
  assert_false(engine.owns(1))
  assert_false(engine.activate_generation(2))
  assert_true(engine.prepare_owned(1, "# Late") is None)
  assert_true(engine.catch_up_owned(2, "# Other", None) is None)
  assert_false(engine.accept(output))
  assert_true(engine.state is Broken)
  assert_true(engine.pending_render is None)
  assert_true(engine.accepted_render is None)
}
