// Whitebox integration tests for §P0b Phase 1b WS2: JSON FFI editors driven
// through the workspace coordinator. Covers spec §12 tests 1–4 (7-cell
// symmetric subset) — these need access to package-private symbols
// (`json_handles`, `coordinator`, `JsonHandle` fields), so they live in a
// `_wbtest.mbt`.
//
// §12 #5 (`ProtectedCellDisposed`) is workspace-generic and covered by
// `workspace/coordinator/coordinator_wbtest.mbt:33`.

///|
fn reset_json_coordinator_for_phase1_tests() -> Unit {
  let keys = json_handles.keys().to_array()
  for k in keys {
    json_handles.remove(k)
  }
  let vkeys = json_view_states.keys().to_array()
  for k in vkeys {
    json_view_states.remove(k)
  }
}

///|
test "spec §12 #1 (json): each protected cell reads through read_protected" {
  reset_json_coordinator_for_phase1_tests()
  let handle = create_json_editor("json_test_agent_one")
  let h = json_handles.get(handle).unwrap()
  let id = h.editor_id
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
  destroy_json_editor(handle)
}

///|
test "spec §12 #2 (json): destroy refused while depended-upon; succeeds after unregister_dep" {
  reset_json_coordinator_for_phase1_tests()
  let handle = create_json_editor("json_test_agent_two")
  let h = json_handles.get(handle).unwrap()
  let id = h.editor_id
  let parser_ast_id = h.cells.parser_ast.cell_id()
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
  json_handles.remove(handle)
  json_view_states.remove(handle)
}

///|
test "spec §12 #3 (json): read_protected after destroy returns EditorDestroyed" {
  reset_json_coordinator_for_phase1_tests()
  let handle = create_json_editor("json_test_agent_three")
  let h = json_handles.get(handle).unwrap()
  let id = h.editor_id
  let parser_source_cell = h.cells.parser_source
  destroy_json_editor(handle)
  match coordinator.read_protected(id, parser_source_cell) {
    Ok(_) => fail("expected EditorDestroyed")
    Err(report) => {
      assert_eq(report.kind, @workspace.EditorDestroyed)
      assert_eq(report.agent_id, "json_test_agent_three")
    }
  }
}

///|
test "spec §12 #4 (json): read_protected rejects cells from a different editor" {
  reset_json_coordinator_for_phase1_tests()
  let handle_a = create_json_editor("json_agent_alpha")
  let handle_b = create_json_editor("json_agent_beta")
  let h_a = json_handles.get(handle_a).unwrap()
  let h_b = json_handles.get(handle_b).unwrap()
  match coordinator.read_protected(h_b.editor_id, h_a.cells.parser_ast) {
    Ok(_) => fail("expected CellNotInProtectedSurface")
    Err(report) => assert_eq(report.kind, @workspace.CellNotInProtectedSurface)
  }
  destroy_json_editor(handle_a)
  destroy_json_editor(handle_b)
}
