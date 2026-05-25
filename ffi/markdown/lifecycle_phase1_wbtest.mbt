// Whitebox integration tests for §P0b Phase 1b WS2: Markdown FFI editors
// driven through the workspace coordinator. Covers spec §12 tests 1–4
// (7-cell symmetric subset) — these need access to package-private
// symbols (`markdown_handles`, `coordinator`, `MarkdownHandle` fields), so
// they live in a `_wbtest.mbt`.
//
// §12 #5 (`ProtectedCellDisposed`) is workspace-generic and covered by
// `workspace/coordinator/coordinator_wbtest.mbt:33`.

///|
fn reset_markdown_coordinator_for_phase1_tests() -> Unit {
  // Force-clear FFI-side bookkeeping. Going through public
  // `destroy_markdown_editor` would route through
  // `coordinator.destroy_editor`, which can refuse
  // (DestroyWhileDependedUpon) and leave the entry behind — fragile if a
  // prior test panicked mid-flow and left a stale dep. Coordinator-side
  // registrations stay around with alive=true; each new test gets a fresh
  // EditorId from the monotonic counter so leakage cannot affect
  // correctness, only memory.
  let keys = markdown_handles.keys().to_array()
  for k in keys {
    markdown_handles.remove(k)
  }
  let vkeys = markdown_view_states.keys().to_array()
  for k in vkeys {
    markdown_view_states.remove(k)
  }
}

///|
test "spec §12 #1 (md): each protected cell reads through read_protected" {
  reset_markdown_coordinator_for_phase1_tests()
  let handle = create_markdown_editor("md_test_agent_one")
  let h = markdown_handles.get(handle).unwrap()
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
  destroy_markdown_editor(handle)
}

///|
test "spec §12 #2 (md): destroy refused while depended-upon; succeeds after unregister_dep" {
  reset_markdown_coordinator_for_phase1_tests()
  let handle = create_markdown_editor("md_test_agent_two")
  let h = markdown_handles.get(handle).unwrap()
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
  markdown_handles.remove(handle)
  markdown_view_states.remove(handle)
}

///|
test "spec §12 #3 (md): read_protected after destroy returns EditorDestroyed" {
  reset_markdown_coordinator_for_phase1_tests()
  let handle = create_markdown_editor("md_test_agent_three")
  let h = markdown_handles.get(handle).unwrap()
  let id = h.editor_id
  let parser_source_cell = h.cells.parser_source
  destroy_markdown_editor(handle)
  match coordinator.read_protected(id, parser_source_cell) {
    Ok(_) => fail("expected EditorDestroyed")
    Err(report) => {
      assert_eq(report.kind, @workspace.EditorDestroyed)
      assert_eq(report.agent_id, "md_test_agent_three")
    }
  }
}

///|
test "spec §12 #4 (md): read_protected rejects cells from a different editor" {
  reset_markdown_coordinator_for_phase1_tests()
  let handle_a = create_markdown_editor("md_agent_alpha")
  let handle_b = create_markdown_editor("md_agent_beta")
  let h_a = markdown_handles.get(handle_a).unwrap()
  let h_b = markdown_handles.get(handle_b).unwrap()
  match coordinator.read_protected(h_b.editor_id, h_a.cells.parser_ast) {
    Ok(_) => fail("expected CellNotInProtectedSurface")
    Err(report) => assert_eq(report.kind, @workspace.CellNotInProtectedSurface)
  }
  destroy_markdown_editor(handle_a)
  destroy_markdown_editor(handle_b)
}
