// Host-local registry tests: behavior independent of language handles
// (plan Step 1). Language-typed concerns — protected-cell bundles,
// companions, pretty view states — are tested in their ffi/<L> packages.
// Whitebox so assertions can inspect the priv view_states map directly
// instead of widening the public API for tests.

///|
test "view_state get-or-create returns the same state for the same handle" {
  let reg : HostRegistry[String] = HostRegistry::HostRegistry()
  let s1 = reg.view_state(7)
  s1.set_had_errors(true)
  // Same handle → same state object (mutation is visible through re-fetch).
  assert_true(reg.view_state(7).had_errors)
  // Different handle → fresh state.
  assert_false(reg.view_state(8).had_errors)
}

///|
test "remove drops the handle and its view state" {
  let reg : HostRegistry[String] = HostRegistry::HostRegistry()
  reg.insert(1, "h1")
  reg.view_state(1).set_had_errors(true)
  reg.remove(1)
  assert_false(reg.contains(1))
  assert_false(reg.view_states.contains(1))
  // A re-created state is fresh, not the stale pre-remove one.
  assert_false(reg.view_state(1).had_errors)
}

///|
test "clear drops all handles and view states" {
  let reg : HostRegistry[String] = HostRegistry::HostRegistry()
  reg.insert(1, "a")
  reg.insert(2, "b")
  let _ = reg.view_state(1)
  assert_eq(reg.size(), 2)
  reg.clear()
  assert_eq(reg.size(), 0)
  assert_false(reg.view_states.contains(1))
}

///|
test "destroy refusal leaves bookkeeping intact; success removes it" {
  let coordinator = @workspace.Coordinator::new()
  let rt = coordinator.runtime()
  let d = @incr.Derived::Derived(rt, fn() { 1 }, label="host_test_cell")
  let pcell = @workspace.ProtectedCell::from_derived("host_test_cell", d)
  let editor_id = coordinator.register_editor("host_test_agent", [pcell.erase()])
  let reg : HostRegistry[String] = HostRegistry::HostRegistry()
  reg.insert(editor_id.0, "handle")
  reg.view_state(editor_id.0).set_had_errors(true)

  // Refusal path: a workspace dep edge points at the editor.
  let ws_cell = @incr.Derived::Derived(rt, fn() { 0 }, label="host_test_ws")
  coordinator.register_dep(ws_cell.id(), editor_id, d.id())
  assert_false(reg.destroy(coordinator, editor_id, "host_test_destroy"))
  assert_true(reg.contains(editor_id.0))
  assert_true(reg.view_states.contains(editor_id.0))
  // The retained view state is the same object, not a recreated one.
  assert_true(reg.view_state(editor_id.0).had_errors)

  // Success path: edge released → destroy proceeds, bookkeeping removed.
  coordinator.unregister_dep(ws_cell.id(), editor_id, d.id())
  assert_true(reg.destroy(coordinator, editor_id, "host_test_destroy"))
  assert_false(reg.contains(editor_id.0))
  assert_false(reg.view_states.contains(editor_id.0))
}

///|
test "destroy of an unknown editor id refuses and keeps bookkeeping" {
  let coordinator = @workspace.Coordinator::new()
  let reg : HostRegistry[String] = HostRegistry::HostRegistry()
  reg.insert(99, "phantom")
  assert_false(
    reg.destroy(
      coordinator,
      @workspace.EditorId(99),
      "host_test_unknown_destroy",
    ),
  )
  assert_true(reg.contains(99))
}
