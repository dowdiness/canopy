// Whitebox integration tests for §P0b Phase 1: Lambda FFI editors driven
// through the workspace coordinator. Covers spec §12 tests 1, 2, 3, 4 —
// these need access to package-private symbols (`lambda_handles`,
// `coordinator`, `LambdaHandle` fields), so they live in a `_wbtest.mbt`.
//
// §12 #5 (`ProtectedCellDisposed`) and §12 #6 (`CycleDetected` mapping)
// live in `workspace/coordinator/coordinator_wbtest.mbt` — they only
// exercise coordinator-side behavior and don't need the Lambda surface.

///|
fn reset_coordinator_for_phase1_tests() -> Unit {
  // Force-clear the FFI side. Going through public `destroy_editor`
  // would route through `coordinator.destroy_editor`, which can refuse
  // (DestroyWhileDependedUpon, EditorDestroyed) and leave the entry
  // behind — fragile if a prior test panicked mid-flow and left a
  // stale dep or an already-disposed registration. Mirrors
  // `clear_lambda_handles` in `destroy_editor_wbtest.mbt`. Coordinator-
  // side registrations stay around with alive=true and may leak Watch
  // roots, but each new test gets a fresh EditorId from the monotonic
  // counter, so leakage cannot affect correctness — only memory.
  let keys = lambda_handles.keys().to_array()
  for k in keys {
    lambda_handles.remove(k)
  }
  let vkeys = view_states.keys().to_array()
  for k in vkeys {
    view_states.remove(k)
  }
  let pvkeys = pretty_view_states.keys().to_array()
  for k in pvkeys {
    pretty_view_states.remove(k)
  }
  last_created_handle.val = None
}

///|
test "spec §12 #1: each protected cell reads through read_protected" {
  reset_coordinator_for_phase1_tests()
  let handle = create_editor("test_agent_one")
  let h = lambda_handles.get(handle).unwrap()
  let id = h.editor_id
  // Spec compliance: every cell wired into the bundle must reach
  // `read_protected` with Ok(_) on a freshly-created editor. Reading
  // all 10 (not a spot-check) guarantees a wiring defect on any single
  // cell fails this test instead of slipping past.
  match coordinator.read_protected(id, h.cells.parser_syntax_tree) {
    Ok(_) => ()
    Err(report) => fail("parser_syntax_tree: \{report}")
  }
  match coordinator.read_protected(id, h.cells.parser_ast) {
    Ok(_) => ()
    Err(report) => fail("parser_ast: \{report}")
  }
  match coordinator.read_protected(id, h.cells.parser_source) {
    Ok(s) => assert_eq(s, "")
    Err(report) => fail("parser_source: \{report}")
  }
  match coordinator.read_protected(id, h.cells.parser_diagnostics) {
    Ok(_) => ()
    Err(report) => fail("parser_diagnostics: \{report}")
  }
  match coordinator.read_protected(id, h.cells.cached_proj_node) {
    Ok(_) => ()
    Err(report) => fail("cached_proj_node: \{report}")
  }
  match coordinator.read_protected(id, h.cells.registry_memo) {
    Ok(_) => ()
    Err(report) => fail("registry_memo: \{report}")
  }
  match coordinator.read_protected(id, h.cells.source_map_memo) {
    Ok(_) => ()
    Err(report) => fail("source_map_memo: \{report}")
  }
  match coordinator.read_protected(id, h.cells.proj_memo) {
    Ok(_) => ()
    Err(report) => fail("proj_memo: \{report}")
  }
  match coordinator.read_protected(id, h.cells.escalation_memo) {
    Ok(_) => ()
    Err(report) => fail("escalation_memo: \{report}")
  }
  match coordinator.read_protected(id, h.cells.typecheck_output) {
    Ok(_) => ()
    Err(report) => fail("typecheck_output: \{report}")
  }
  destroy_editor(handle)
}

///|
test "spec §12 #2: destroy refused while depended-upon; succeeds after unregister_dep" {
  reset_coordinator_for_phase1_tests()
  let handle = create_editor("test_agent_two")
  let h = lambda_handles.get(handle).unwrap()
  let id = h.editor_id
  let parser_ast_id = h.cells.parser_ast.cell_id()
  // Synthetic workspace memo id — register_dep only stores edges by
  // CellId. Using parser_ast_id on both sides keeps the test free of
  // any real workspace memo, which Phase 1 doesn't ship.
  let synth_id = parser_ast_id
  coordinator.register_dep(synth_id, id, parser_ast_id)
  match coordinator.destroy_editor(id) {
    Ok(_) => fail("expected DestroyWhileDependedUpon")
    Err(report) => assert_eq(report.kind, @workspace.DestroyWhileDependedUpon)
  }
  coordinator.unregister_dep(synth_id, id, parser_ast_id)
  match coordinator.destroy_editor(id) {
    Ok(_) => ()
    Err(report) => fail("expected Ok after unregister_dep, got \{report}")
  }
  // We bypassed the FFI `destroy_editor` wrapper, so the typecheck scope
  // and FFI bookkeeping are still in place. Drain them so subsequent
  // tests don't trip over the lingering handle. We cannot route through
  // `destroy_editor(handle)` again because the coordinator has already
  // marked the registration alive=false.
  h.typecheck.scope.dispose()
  lambda_handles.remove(handle)
  view_states.remove(handle)
  pretty_view_states.remove(handle)
  if last_created_handle.val == Some(handle) {
    last_created_handle.val = None
  }
}

///|
test "spec §12 #3: read_protected after destroy returns EditorDestroyed" {
  reset_coordinator_for_phase1_tests()
  let handle = create_editor("test_agent_three")
  let h = lambda_handles.get(handle).unwrap()
  let id = h.editor_id
  let parser_source_cell = h.cells.parser_source
  destroy_editor(handle)
  // The handle is now removed from lambda_handles, but the registration
  // in the coordinator stays (alive=false) so the error carries agent_id.
  match coordinator.read_protected(id, parser_source_cell) {
    Ok(_) => fail("expected EditorDestroyed")
    Err(report) => {
      assert_eq(report.kind, @workspace.EditorDestroyed)
      assert_eq(report.agent_id, "test_agent_three")
    }
  }
}

///|
test "spec §12 #4: read_protected rejects cells from a different editor" {
  reset_coordinator_for_phase1_tests()
  let handle_a = create_editor("agent_alpha")
  let handle_b = create_editor("agent_beta")
  let h_a = lambda_handles.get(handle_a).unwrap()
  let h_b = lambda_handles.get(handle_b).unwrap()
  match coordinator.read_protected(h_b.editor_id, h_a.cells.parser_ast) {
    Ok(_) => fail("expected CellNotInProtectedSurface")
    Err(report) => assert_eq(report.kind, @workspace.CellNotInProtectedSurface)
  }
  destroy_editor(handle_a)
  destroy_editor(handle_b)
}
