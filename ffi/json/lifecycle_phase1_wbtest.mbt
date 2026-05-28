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
fn drain_json_handle_after_direct_coordinator_destroy(handle : Int) -> Unit {
  json_handles.remove(handle)
  json_view_states.remove(handle)
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

///|
/// Phase 1b workstream 2 — `json_get_errors` migration regressions. Each
/// test corresponds to one behavioral risk called out in spec §7.2.
///
/// Empty-doc guard: pre-migration, `SyncEditor::get_errors` short-circuited
/// to `[]` on empty source (editor/sync_editor_parser.mbt:108-110) before
/// reading parser diagnostics — the parser produces spurious diagnostics
/// on "" source that must be suppressed. The migration must preserve that
/// semantic at the FFI boundary; calling `parser_diagnostics.format()`
/// unconditionally would surface those spurious errors.
test "workstream 2 (json): json_get_errors returns [] for empty source" {
  reset_json_coordinator_for_phase1_tests()
  let handle = create_json_editor("json_diag_empty_agent")
  // `create_json_editor` produces an editor with empty source — no set_text.
  assert_eq(json_get_errors(handle), "[]")
  destroy_json_editor(handle)
}

///|
/// Parse-error path: malformed JSON input produces a non-empty array of
/// diagnostic strings via the migrated `coordinator.read_protected(parser_
/// diagnostics).format()` chain. Output must still be a valid JSON array
/// (consumers parse it).
test "workstream 2 (json): json_get_errors returns non-empty array for parse error" {
  reset_json_coordinator_for_phase1_tests()
  let handle = create_json_editor("json_diag_parse_agent")
  // Unclosed object — guaranteed parse error.
  json_set_text(handle, "{ invalid")
  let out = json_get_errors(handle)
  // Must be a JSON array (starts with `[`, ends with `]`).
  if !out.has_prefix("[") || !out.has_suffix("]") {
    fail("expected JSON array shape, got \{out}")
  }
  // Must be non-empty (not "[]").
  if out == "[]" {
    fail("expected non-empty diagnostics for parse-error input, got []")
  }
  destroy_json_editor(handle)
}

///|
/// Post-destroy path: after `coordinator.destroy_editor`, the accessor must
/// collapse to "[]" via the Err arm of `read_protected`. Pre-migration the
/// accessor read `ed.get_errors()` directly (bypassing the coordinator), so
/// a destroyed editor would have produced stale diagnostics from the
/// Derived cell rather than failing closed. This test pins the new
/// behavior.
test "workstream 2 (json): json_get_errors collapses to [] after coordinator destroy" {
  reset_json_coordinator_for_phase1_tests()
  let handle = create_json_editor("json_diag_destroy_agent")
  json_set_text(handle, "{ invalid")
  let alive = json_get_errors(handle)
  if alive == "[]" {
    fail("expected non-empty diagnostics pre-destroy, got []")
  }
  let h = json_handles.get(handle).unwrap()
  let id = h.editor_id
  match coordinator.destroy_editor(id) {
    Ok(_) => ()
    Err(report) => fail("coordinator destroy: \{report}")
  }
  // FFI bookkeeping retained — coordinator side is destroyed.
  match json_handles.get(handle) {
    Some(_) => ()
    None =>
      fail(
        "expected json_handles to retain handle after direct coordinator destroy",
      )
  }
  assert_eq(json_get_errors(handle), "[]")
  json_handles.remove(handle)
  json_view_states.remove(handle)
}

///|
/// Phase 1b JSON followup: remaining exported accessors route their
/// projection/source-map protected-cell reads through the coordinator before
/// delegating to the existing editor implementation.
test "workstream 3 (json): json_get_proj_node_json collapses to null after coordinator destroy" {
  reset_json_coordinator_for_phase1_tests()
  let handle = create_json_editor("json_proj_destroy_agent")
  json_set_text(handle, "{\"a\": 1}")
  let alive = json_get_proj_node_json(handle)
  if alive == "null" {
    fail("expected live projection JSON before coordinator destroy")
  }
  let h = json_handles.get(handle).unwrap()
  match coordinator.destroy_editor(h.editor_id) {
    Ok(_) => ()
    Err(report) => fail("coordinator destroy: \{report}")
  }
  assert_eq(json_get_proj_node_json(handle), "null")
  drain_json_handle_after_direct_coordinator_destroy(handle)
}

///|
test "workstream 3 (json): json_get_source_map_json collapses to [] after coordinator destroy" {
  reset_json_coordinator_for_phase1_tests()
  let handle = create_json_editor("json_source_map_destroy_agent")
  json_set_text(handle, "{\"a\": 1}")
  let alive = json_get_source_map_json(handle)
  if alive == "[]" {
    fail("expected live source map JSON before coordinator destroy")
  }
  let h = json_handles.get(handle).unwrap()
  match coordinator.destroy_editor(h.editor_id) {
    Ok(_) => ()
    Err(report) => fail("coordinator destroy: \{report}")
  }
  assert_eq(json_get_source_map_json(handle), "[]")
  drain_json_handle_after_direct_coordinator_destroy(handle)
}

///|
test "workstream 3 (json): json_get_view_tree_json collapses to null after coordinator destroy" {
  reset_json_coordinator_for_phase1_tests()
  let handle = create_json_editor("json_view_tree_destroy_agent")
  json_set_text(handle, "{\"a\": 1}")
  let alive = json_get_view_tree_json(handle)
  if alive == "null" {
    fail("expected live view tree JSON before coordinator destroy")
  }
  let h = json_handles.get(handle).unwrap()
  match coordinator.destroy_editor(h.editor_id) {
    Ok(_) => ()
    Err(report) => fail("coordinator destroy: \{report}")
  }
  assert_eq(json_get_view_tree_json(handle), "null")
  drain_json_handle_after_direct_coordinator_destroy(handle)
}

///|
test "workstream 3 (json): json_compute_view_patches_json collapses to [] after coordinator destroy" {
  reset_json_coordinator_for_phase1_tests()
  let handle = create_json_editor("json_view_patches_destroy_agent")
  json_set_text(handle, "{\"a\": 1}")
  let alive = json_compute_view_patches_json(handle)
  if alive == "[]" {
    fail("expected live view patch JSON before coordinator destroy")
  }
  let h = json_handles.get(handle).unwrap()
  match coordinator.destroy_editor(h.editor_id) {
    Ok(_) => ()
    Err(report) => fail("coordinator destroy: \{report}")
  }
  assert_eq(json_compute_view_patches_json(handle), "[]")
  drain_json_handle_after_direct_coordinator_destroy(handle)
}

///|
test "workstream 3 (json): json_apply_edit rejects after coordinator destroy" {
  reset_json_coordinator_for_phase1_tests()
  let handle = create_json_editor("json_apply_destroy_agent")
  json_set_text(handle, "{\"a\": 1}")
  let h = json_handles.get(handle).unwrap()
  let node_id = match h.editor.get_proj_node() {
    Some(root) =>
      match root.id().to_json() {
        Json::Number(n, ..) => n.to_int()
        _ => fail("expected numeric node id")
      }
    None => fail("expected projection")
  }
  match coordinator.destroy_editor(h.editor_id) {
    Ok(_) => ()
    Err(report) => fail("coordinator destroy: \{report}")
  }
  let op_json = "{\"op\":\"CommitEdit\",\"node_id\":" +
    node_id.to_string() +
    ",\"new_value\":\"2\"}"
  assert_eq(json_apply_edit(handle, op_json, 0), "error: editor unavailable")
  drain_json_handle_after_direct_coordinator_destroy(handle)
}
