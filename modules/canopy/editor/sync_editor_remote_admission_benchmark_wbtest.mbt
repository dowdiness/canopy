///|
struct RemoteAdmissionBenchmarkFixture {
  source : @text.TextState
  target : SyncEditor[@probe.TestExpr]
  incoming : @text.SyncMessage
}

///|
fn remote_admission_benchmark_fixture(
  history_operations : Int,
  visible_utf16_units : Int,
  fixture_id : String,
) -> RemoteAdmissionBenchmarkFixture raise Failure {
  guard history_operations >= visible_utf16_units else {
    fail("visible length exceeds resident history")
  }
  let hidden_operations = history_operations - visible_utf16_units
  guard hidden_operations % 2 == 0 else {
    fail("hidden benchmark history must be insert/delete pairs")
  }
  let source = try! @text.TextState::new(fixture_id + "-source")
  let target = try! @probe.new_test_editor(fixture_id + "-target")
  if visible_utf16_units > 0 {
    try! source.insert(@text.Pos::at(0), "x".repeat(visible_utf16_units))
  }
  for _ in 0..<(hidden_operations / 2) {
    try! source.insert(@text.Pos::at(visible_utf16_units), "z")
    try! source.delete(@text.Pos::at(visible_utf16_units))
  }
  let setup_limits = try! @sync.Limits::Limits(
    max_encoded_bytes=256 * 1024 * 1024,
    max_decoded_operations=history_operations,
  )
  let initial = try! target.authority.doc
    .sync()
    .apply_with_limits(try! source.sync().export_all(), setup_limits)
  guard initial.applied_operations() == history_operations else {
    fail("benchmark fixture produced the wrong resident history size")
  }
  try! target.sync_parser_from_coherent_seed()
  let target_version = target.get_version()
  try! source.insert(@text.Pos::at(visible_utf16_units), "q")
  { source, target, incoming: try! source.sync().export_since(target_version) }
}

///|
fn measure_segmented_remote_admission(
  history_operations : Int,
  visible_utf16_units : Int,
  fixture_id : String,
) -> (Double, Double, Double) raise Failure {
  let segmented = remote_admission_benchmark_fixture(
    history_operations, visible_utf16_units, fixture_id,
  )
  segmented.target.ensure_parser_healthy()
  segmented.target.reject_projection_observer_reentry()
  let transition_start = @bench.monotonic_clock_start()
  let transition = match
    segmented.target.authority.admit_transition_with_tracking(
      segmented.incoming,
      None,
    ) {
    Ok(transition) => transition
    Err(_) => fail("benchmark transition production failed")
  }
  let transition_us = @bench.monotonic_clock_end(transition_start)
  let authority_advanced = transition.version_after() !=
    transition.version_before()
  guard authority_advanced else {
    fail("benchmark transition did not advance authority")
  }
  segmented.target.observe_authority_acceptance()
  let preparation_start = @bench.monotonic_clock_start()
  let parser_source = segmented.target.projection.parser
    .source()
    .read_or_abort()
  let prepared = match transition.availability() {
    @text.TextEffectAvailability::Exact(effects) =>
      prepare_text_admission(parser_source, effects)
    @text.TextEffectAvailability::SnapshotRequired =>
      fail("warm one-operation benchmark required a snapshot")
    @text.TextEffectAvailability::Unavailable =>
      fail("warm one-operation benchmark transition was unavailable")
  }
  let preparation_us = @bench.monotonic_clock_end(preparation_start)
  let reconciliation_start = @bench.monotonic_clock_start()
  segmented.target.settle_prepared_text_admission(
    parser_source,
    prepared,
    transition.version_after(),
    authority_advanced,
  )
  let report = transition.finish() catch {
    _ => fail("segmented benchmark transition finish failed")
  }
  let reconciliation_us = @bench.monotonic_clock_end(reconciliation_start)
  guard report.applied_operations() == 1 &&
    segmented.target.get_text() == segmented.source.text() else {
    fail("segmented benchmark reconciliation did not converge")
  }
  (transition_us, preparation_us, reconciliation_us)
}

///|
fn measure_whole_remote_admission(
  history_operations : Int,
  visible_utf16_units : Int,
  fixture_id : String,
) -> Double raise Failure {
  let whole = remote_admission_benchmark_fixture(
    history_operations, visible_utf16_units, fixture_id,
  )
  let whole_call_start = @bench.monotonic_clock_start()
  let whole_report = whole.target.admit(whole.incoming) catch {
    _ => fail("whole-call benchmark admission failed")
  }
  let whole_call_us = @bench.monotonic_clock_end(whole_call_start)
  guard whole_report.applied_operations() == 1 &&
    whole.target.get_text() == whole.source.text() else {
    fail("whole-call benchmark reconciliation did not converge")
  }
  whole_call_us
}

///|
fn benchmark_remote_admission_phase_case(
  b : @bench.T,
  history_operations : Int,
  visible_utf16_units : Int,
) -> Unit {
  let label = history_operations.to_string() +
    "-" +
    visible_utf16_units.to_string()
  let (transition_us, preparation_us, reconciliation_us) = try! measure_segmented_remote_admission(
    history_operations,
    visible_utf16_units,
    "remote-admission-segmented-" + label,
  )
  b.keep((transition_us, preparation_us, reconciliation_us))
  println(
    "{\"mode\":\"phases\",\"H\":" +
    history_operations.to_string() +
    ",\"L\":" +
    visible_utf16_units.to_string() +
    ",\"transition_us\":" +
    transition_us.to_string() +
    ",\"preparation_us\":" +
    preparation_us.to_string() +
    ",\"reconciliation_us\":" +
    reconciliation_us.to_string() +
    "}",
  )
}

///|
fn benchmark_remote_admission_whole_case(
  b : @bench.T,
  history_operations : Int,
  visible_utf16_units : Int,
) -> Unit {
  let label = history_operations.to_string() +
    "-" +
    visible_utf16_units.to_string()
  let whole_call_us = try! measure_whole_remote_admission(
    history_operations,
    visible_utf16_units,
    "remote-admission-whole-" + label,
  )
  b.keep(whole_call_us)
  println(
    "{\"mode\":\"whole\",\"H\":" +
    history_operations.to_string() +
    ",\"L\":" +
    visible_utf16_units.to_string() +
    ",\"whole_call_us\":" +
    whole_call_us.to_string() +
    "}",
  )
}

///|
test "perf: remote admission whole H=0 L=0" (b : @bench.T) {
  benchmark_remote_admission_whole_case(b, 0, 0)
}

///|
test "perf: remote admission whole H=1000 L=0" (b : @bench.T) {
  benchmark_remote_admission_whole_case(b, 1000, 0)
}

///|
test "perf: remote admission whole H=10000 L=0" (b : @bench.T) {
  benchmark_remote_admission_whole_case(b, 10000, 0)
}

///|
test "perf: remote admission whole H=100000 L=0" (b : @bench.T) {
  benchmark_remote_admission_whole_case(b, 100000, 0)
}

///|
test "perf: remote admission whole H=100000 L=2000" (b : @bench.T) {
  benchmark_remote_admission_whole_case(b, 100000, 2000)
}

///|
test "perf: remote admission whole H=100000 L=10000" (b : @bench.T) {
  benchmark_remote_admission_whole_case(b, 100000, 10000)
}

///|
test "perf: remote admission whole H=100000 L=50000" (b : @bench.T) {
  benchmark_remote_admission_whole_case(b, 100000, 50000)
}

///|
test "perf: remote admission phases H=0 L=0" (b : @bench.T) {
  benchmark_remote_admission_phase_case(b, 0, 0)
}

///|
test "perf: remote admission phases H=1000 L=0" (b : @bench.T) {
  benchmark_remote_admission_phase_case(b, 1000, 0)
}

///|
test "perf: remote admission phases H=10000 L=0" (b : @bench.T) {
  benchmark_remote_admission_phase_case(b, 10000, 0)
}

///|
test "perf: remote admission phases H=100000 L=0" (b : @bench.T) {
  benchmark_remote_admission_phase_case(b, 100000, 0)
}

///|
test "perf: remote admission phases H=100000 L=2000" (b : @bench.T) {
  benchmark_remote_admission_phase_case(b, 100000, 2000)
}

///|
test "perf: remote admission phases H=100000 L=10000" (b : @bench.T) {
  benchmark_remote_admission_phase_case(b, 100000, 10000)
}

///|
test "perf: remote admission phases H=100000 L=50000" (b : @bench.T) {
  benchmark_remote_admission_phase_case(b, 100000, 50000)
}
