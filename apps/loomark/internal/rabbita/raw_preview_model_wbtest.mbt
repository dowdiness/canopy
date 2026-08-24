///|
test "Raw Preview update adopts only a demanded current projection" {
  let stamp = projection_worker_client_test_stamp(1)
  let preview : NormalizedPreviewProjection = {
    source: "# Current\n",
    artifact: preview_artifact_test_fixture(),
  }
  let (next, decision) = update_raw_preview(
    Ready("# Current\n", stamp, preview),
    RawPreviewModel::enabled(),
    current_source="# Current\n",
    demanded=true,
    speculative=true,
  )
  assert_true(decision is RawPreviewDecision::Adopted)
  assert_true(next.artifact() is Some(_))
  let (stale, stale_decision) = update_raw_preview(
    Ready("# Stale\n", stamp, { ..preview, source: "# Stale\n" }),
    next,
    current_source="# Current\n",
    demanded=true,
    speculative=true,
  )
  assert_true(stale_decision is RawPreviewDecision::Rejected)
  assert_eq(stale.artifact(), next.artifact())
}

///|
test "Raw Preview failure recovers only while speculative demand remains" {
  let (next, decision) = update_raw_preview(
    Failed,
    RawPreviewModel::enabled(),
    current_source="# Current\n",
    demanded=true,
    speculative=true,
  )
  assert_true(next.artifact() is None)
  guard decision is RawPreviewDecision::Recover(source) else {
    fail("expected Raw Preview recovery decision")
  }
  assert_eq(source, "# Current\n")
  let (stopped, stopped_decision) = update_raw_preview(
    Failed,
    RawPreviewModel::enabled(),
    current_source="# Accepted\n",
    demanded=true,
    speculative=false,
  )
  assert_true(stopped.artifact() is None)
  assert_true(stopped_decision is RawPreviewDecision::Stopped)
  let (disabled, disabled_decision) = update_raw_preview(
    Failed,
    RawPreviewModel::disabled(),
    current_source="# Current\n",
    demanded=true,
    speculative=true,
  )
  assert_true(disabled is Disabled)
  assert_true(disabled_decision is RawPreviewDecision::Rejected)
}
