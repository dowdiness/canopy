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
fn drain_markdown_handle_after_direct_coordinator_destroy(handle : Int) -> Unit {
  markdown_handles.remove(handle)
  markdown_view_states.remove(handle)
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

///|
/// Phase 1b workstream 2 — `markdown_compute_view_patches_json` migration
/// regressions. Each test corresponds to one behavioral risk called out in
/// spec §7.2.
///
/// Initial-render path: a fresh editor with non-empty source should emit a
/// FullTree patch carrying a non-null root. Regression check that the
/// `coordinator.read_protected(cached_proj_node)` → assemble manually →
/// FullTree pipeline produces the same Some-root shape that the
/// pre-migration `@editor.compute_view_patches` did.
test "workstream 2 (md): compute_view_patches initial render emits FullTree with root" {
  reset_markdown_coordinator_for_phase1_tests()
  let handle = create_markdown_editor("md_view_initial_agent")
  markdown_set_text(handle, "# Hello\n\nWorld\n")
  let out = markdown_compute_view_patches_json(handle)
  if !out.contains("\"FullTree\"") {
    fail("expected initial render to emit FullTree patch, got \{out}")
  }
  // The root should not be null — a populated markdown document projects to
  // a ViewNode. (Empty doc would be {"FullTree":{"root":null}}; we just
  // wrote two blocks.)
  if out.contains("\"root\":null") {
    fail(
      "expected non-null root on initial render of non-empty doc, got \{out}",
    )
  }
  destroy_markdown_editor(handle)
}

///|
/// Incremental-diff path: a second call after a structural change must emit
/// targeted patches (`UpdateNode` / `ReplaceNode` / `InsertChild` /
/// `RemoveChild`), not a fresh `FullTree`. The `state.previous` carry-over
/// from the first call is what makes this possible; if the rewrite ever
/// loses the carry-over, this test catches it.
test "workstream 2 (md): compute_view_patches second call emits incremental patches" {
  reset_markdown_coordinator_for_phase1_tests()
  let handle = create_markdown_editor("md_view_incr_agent")
  markdown_set_text(handle, "# Hello\n")
  let _ = markdown_compute_view_patches_json(handle)
  markdown_set_text(handle, "# Hello world\n")
  let second = markdown_compute_view_patches_json(handle)
  // Second call must NOT be a FullTree — that would mean the diff path
  // didn't trigger.
  if second.contains("\"FullTree\"") {
    fail(
      "expected incremental patch on second call after edit, got FullTree: \{second}",
    )
  }
  // At least one of the incremental patch tags must appear.
  let has_incremental = second.contains("\"UpdateNode\"") ||
    second.contains("\"ReplaceNode\"") ||
    second.contains("\"InsertChild\"") ||
    second.contains("\"RemoveChild\"")
  if !has_incremental {
    fail(
      "expected UpdateNode / ReplaceNode / InsertChild / RemoveChild patch, got \{second}",
    )
  }
  destroy_markdown_editor(handle)
}

///|
/// Post-destroy path: after `coordinator.destroy_editor`, the accessor must
/// collapse to "[]" via the Err arm of every `read_protected` call. The
/// pre-migration body called `@editor.compute_view_patches` directly on
/// `ed`, bypassing the coordinator — destroyed-editor reads would have
/// returned stale Derived state. This test pins the new behavior.
test "workstream 2 (md): compute_view_patches collapses to [] after coordinator destroy" {
  reset_markdown_coordinator_for_phase1_tests()
  let handle = create_markdown_editor("md_view_destroy_agent")
  markdown_set_text(handle, "# Pre-destroy\n")
  let alive = markdown_compute_view_patches_json(handle)
  // Sanity-check that we got something pre-destroy (FullTree from initial
  // render); confirms the test setup is wired correctly.
  if !alive.contains("\"FullTree\"") {
    fail("expected pre-destroy initial render to emit FullTree, got \{alive}")
  }
  let h = markdown_handles.get(handle).unwrap()
  let id = h.editor_id
  match coordinator.destroy_editor(id) {
    Ok(_) => ()
    Err(report) => fail("coordinator destroy: \{report}")
  }
  // FFI bookkeeping retained — coordinator side is destroyed, but the
  // handle entry stays so subsequent calls still hit the protected-read
  // path (and that path's Err arm produces "[]").
  match markdown_handles.get(handle) {
    Some(_) => ()
    None =>
      fail(
        "expected markdown_handles to retain handle after direct coordinator destroy",
      )
  }
  assert_eq(markdown_compute_view_patches_json(handle), "[]")
  markdown_handles.remove(handle)
  markdown_view_states.remove(handle)
}

///|
/// Phase 1b Markdown followup: exported operations that consult projection /
/// source-map state guard those protected reads through the coordinator before
/// delegating to the existing companion implementation.
test "workstream 3 (md): markdown_export_text collapses to empty after coordinator destroy" {
  reset_markdown_coordinator_for_phase1_tests()
  let handle = create_markdown_editor("md_export_destroy_agent")
  markdown_set_text(handle, "# Pre-destroy\n")
  let alive = markdown_export_text(handle)
  if alive == "" {
    fail("expected exported markdown before coordinator destroy")
  }
  let h = markdown_handles.get(handle).unwrap()
  match coordinator.destroy_editor(h.editor_id) {
    Ok(_) => ()
    Err(report) => fail("coordinator destroy: \{report}")
  }
  assert_eq(markdown_export_text(handle), "")
  drain_markdown_handle_after_direct_coordinator_destroy(handle)
}

///|
test "workstream 3 (md): markdown_apply_edit rejects after coordinator destroy" {
  reset_markdown_coordinator_for_phase1_tests()
  let handle = create_markdown_editor("md_apply_destroy_agent")
  markdown_set_text(handle, "# Pre-destroy\n")
  let h = markdown_handles.get(handle).unwrap()
  match coordinator.destroy_editor(h.editor_id) {
    Ok(_) => ()
    Err(report) => fail("coordinator destroy: \{report}")
  }
  let out = markdown_apply_edit(handle, "commit_edit", 0, "after", 0, 1)
  if !out.contains("\"status\":\"error\"") ||
    !out.contains("\"message\":\"editor unavailable\"") {
    fail("expected editor-unavailable error after destroy, got \{out}")
  }
  drain_markdown_handle_after_direct_coordinator_destroy(handle)
}
