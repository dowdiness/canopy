// Tests that parent_runtime? threads through SyncEditor::new_generic to the
// underlying Parser, so editors can share a single @incr.Runtime.

///|
// Identity check: allocate a Signal on each runtime and compare the runtime_id
// field of the resulting CellId. CellId.runtime_id is the public per-runtime
// counter allocated in @incr/cells/internal/kernel/state.mbt via
// @kernel.alloc_runtime_id(). Two cells from the same runtime share the same
// runtime_id; cells from different runtimes have distinct runtime_id values.
test "SyncEditor::new_generic threads parent_runtime through to Parser" {
  let shared = @incr.Runtime::new()
  let (editor, _) = @lambda.new_lambda_editor("test", parent_runtime=shared)
  let parser_rt = editor.parser_runtime()
  // Allocate a Signal on each runtime to read their CellId.runtime_id.
  let sig_shared = @incr.Signal::new(shared, 0, label="probe_shared")
  let sig_parser = @incr.Signal::new(parser_rt, 0, label="probe_parser")
  assert_true(sig_shared.id().runtime_id == sig_parser.id().runtime_id)
}

///|
// Regression guard: without parent_runtime, each editor gets its own runtime.
test "SyncEditor::new_generic without parent_runtime allocates private runtime" {
  let (editor_a, _) = @lambda.new_lambda_editor("a")
  let (editor_b, _) = @lambda.new_lambda_editor("b")
  let rt_a = editor_a.parser_runtime()
  let rt_b = editor_b.parser_runtime()
  let sig_a = @incr.Signal::new(rt_a, 0, label="probe_a")
  let sig_b = @incr.Signal::new(rt_b, 0, label="probe_b")
  assert_true(sig_a.id().runtime_id != sig_b.id().runtime_id)
}
