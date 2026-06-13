// Whitebox integration tests for §P0b Phase 1: Lambda FFI editors driven
// through the workspace coordinator. Covers spec §12 tests 1, 2, 3, 4 —
// these need access to package-private symbols (`lambda_registry`,
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
  lambda_registry.clear()
  pretty_view_states.clear()
  last_created_handle.val = None
}

///|
fn drain_lambda_handle_after_direct_coordinator_destroy(
  handle : Int,
  h : LambdaHandle,
) -> Unit {
  h.companion.dispose_analysis_attachment()
  lambda_registry.remove(handle)
  pretty_view_states.remove(handle)
  if last_created_handle.val == Some(handle) {
    last_created_handle.val = None
  }
}

///|
test "spec §12 #1: each protected cell reads through read_protected" {
  reset_coordinator_for_phase1_tests()
  let handle = create_editor("test_agent_one")
  let h = lambda_registry.get(handle).unwrap()
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
  let h = lambda_registry.get(handle).unwrap()
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
  // We bypassed the FFI `destroy_editor` wrapper, so the analysis attachment
  // and FFI bookkeeping are still in place. Drain them so subsequent
  // tests don't trip over the lingering handle. We cannot route through
  // `destroy_editor(handle)` again because the coordinator has already
  // marked the registration alive=false.
  h.companion.dispose_analysis_attachment()
  lambda_registry.remove(handle)
  pretty_view_states.remove(handle)
  if last_created_handle.val == Some(handle) {
    last_created_handle.val = None
  }
}

///|
/// Phase 1b workstream 3 suite: the remaining composite Lambda accessors in
/// this slice now perform coordinator-mediated protected-read guards before
/// delegating to the existing editor implementation.
test "workstream 3: get_view_tree_json collapses to null after coordinator destroy" {
  reset_coordinator_for_phase1_tests()
  let handle = create_editor("view_tree_coord_destroy_agent")
  set_text(handle, "(x) => x")
  let alive_json = get_view_tree_json(handle)
  if alive_json == "null" {
    fail("expected live view tree JSON before coordinator destroy")
  }
  let h = lambda_registry.get(handle).unwrap()
  match coordinator.destroy_editor(h.editor_id) {
    Ok(_) => ()
    Err(report) => fail("coordinator destroy: \{report}")
  }
  assert_eq(get_view_tree_json(handle), "null")
  drain_lambda_handle_after_direct_coordinator_destroy(handle, h)
}

///|
test "workstream 3: compute_view_patches_json collapses to [] after coordinator destroy" {
  reset_coordinator_for_phase1_tests()
  let handle = create_editor("view_patches_coord_destroy_agent")
  set_text(handle, "(x) => x")
  let alive_json = compute_view_patches_json(handle)
  if alive_json == "[]" {
    fail("expected live view patch JSON before coordinator destroy")
  }
  let h = lambda_registry.get(handle).unwrap()
  match coordinator.destroy_editor(h.editor_id) {
    Ok(_) => ()
    Err(report) => fail("coordinator destroy: \{report}")
  }
  assert_eq(compute_view_patches_json(handle), "[]")
  drain_lambda_handle_after_direct_coordinator_destroy(handle, h)
}

///|
test "workstream 3: get_semantic_projection_json collapses to empty after coordinator destroy" {
  reset_coordinator_for_phase1_tests()
  let handle = create_editor("semantic_projection_coord_destroy_agent")
  set_text(handle, "let x = 1\nx")
  let empty = @lambda_semantic.SemanticProjection::empty().to_json().stringify()
  let alive_json = get_semantic_projection_json(handle)
  if alive_json == empty {
    fail("expected live semantic projection JSON before coordinator destroy")
  }
  let h = lambda_registry.get(handle).unwrap()
  match coordinator.destroy_editor(h.editor_id) {
    Ok(_) => ()
    Err(report) => fail("coordinator destroy: \{report}")
  }
  assert_eq(get_semantic_projection_json(handle), empty)
  drain_lambda_handle_after_direct_coordinator_destroy(handle, h)
}

///|
test "workstream 3: rename_semantic_node rejects after coordinator destroy" {
  reset_coordinator_for_phase1_tests()
  let handle = create_editor("semantic_rename_coord_destroy_agent")
  set_text(handle, "(x) => x")
  let h = lambda_registry.get(handle).unwrap()
  let body_id = match h.editor.get_proj_node() {
    Some(root) =>
      match root.children[0].id().to_json() {
        Json::Number(n, ..) => n.to_int()
        _ => fail("expected numeric node id")
      }
    None => fail("expected projection")
  }
  match coordinator.destroy_editor(h.editor_id) {
    Ok(_) => ()
    Err(report) => fail("coordinator destroy: \{report}")
  }
  inspect(
    rename_semantic_node(handle, body_id, "y", 0),
    content="error: editor unavailable",
  )
  drain_lambda_handle_after_direct_coordinator_destroy(handle, h)
}

///|
test "workstream 3: get_pretty_view_json collapses to null after coordinator destroy" {
  reset_coordinator_for_phase1_tests()
  let handle = create_editor("pretty_view_coord_destroy_agent")
  set_text(handle, "let x = 1\nx")
  let alive_json = get_pretty_view_json(handle)
  if alive_json == "null" {
    fail("expected live pretty view JSON before coordinator destroy")
  }
  let h = lambda_registry.get(handle).unwrap()
  match coordinator.destroy_editor(h.editor_id) {
    Ok(_) => ()
    Err(report) => fail("coordinator destroy: \{report}")
  }
  assert_eq(get_pretty_view_json(handle), "null")
  drain_lambda_handle_after_direct_coordinator_destroy(handle, h)
}

///|
test "workstream 3: compute_pretty_patches_json collapses to [] after coordinator destroy" {
  reset_coordinator_for_phase1_tests()
  let handle = create_editor("pretty_patches_coord_destroy_agent")
  set_text(handle, "let x = 1\nx")
  let alive_json = compute_pretty_patches_json(handle)
  if alive_json == "[]" {
    fail("expected live pretty patch JSON before coordinator destroy")
  }
  let h = lambda_registry.get(handle).unwrap()
  match coordinator.destroy_editor(h.editor_id) {
    Ok(_) => ()
    Err(report) => fail("coordinator destroy: \{report}")
  }
  assert_eq(compute_pretty_patches_json(handle), "[]")
  drain_lambda_handle_after_direct_coordinator_destroy(handle, h)
}

///|
test "spec §12 #3: read_protected after destroy returns EditorDestroyed" {
  reset_coordinator_for_phase1_tests()
  let handle = create_editor("test_agent_three")
  let h = lambda_registry.get(handle).unwrap()
  let id = h.editor_id
  let parser_source_cell = h.cells.parser_source
  destroy_editor(handle)
  // The handle is now removed from lambda_registry, but the registration
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
  let h_a = lambda_registry.get(handle_a).unwrap()
  let h_b = lambda_registry.get(handle_b).unwrap()
  match coordinator.read_protected(h_b.editor_id, h_a.cells.parser_ast) {
    Ok(_) => fail("expected CellNotInProtectedSurface")
    Err(report) => assert_eq(report.kind, @workspace.CellNotInProtectedSurface)
  }
  destroy_editor(handle_a)
  destroy_editor(handle_b)
}

///|
/// Phase 1b workstream 1 suite: `get_diagnostics_json` routes every
/// protected-cell read (parser_diagnostics, typecheck_output,
/// escalation_memo) through the coordinator. The three tests below cover
/// empty-source, typecheck-path, and parse-error-path entry points.
///
/// Empty-source guard regression check: pre-migration,
/// `h.editor.get_errors()` short-circuited to `[]` on empty doc text
/// (editor/sync_editor_parser.mbt:108) before reading the parser
/// diagnostics — empirically the parser produces spurious diagnostics on
/// `""` source that must be suppressed. The migration preserves that
/// semantic at the FFI boundary; calling `parser_diagnostics.format()`
/// unconditionally would surface those spurious errors.
test "workstream 1: get_diagnostics_json returns [] for empty source" {
  reset_coordinator_for_phase1_tests()
  let handle = create_editor("diag_empty_agent")
  // `create_editor` produces an editor with empty source — no `set_text`.
  assert_eq(get_diagnostics_json(handle), "[]")
  destroy_editor(handle)
}

///|
test "workstream 1: get_diagnostics_json collapses to [] after coordinator destroy (typecheck path)" {
  reset_coordinator_for_phase1_tests()
  let handle = create_editor("diag_coord_typecheck_agent")
  // `let x = y` parses cleanly but binds an unbound name, exercising the
  // typecheck branch (parse_errors.is_empty() == true).
  set_text(handle, "let x = y\n")
  let alive_json = get_diagnostics_json(handle)
  // Structural assertion — not just "non-empty". Proves the typecheck path
  // produced a diagnostic with the expected unbound-name message AND that
  // def_name routing is intact. Either substring missing means the
  // migrated typecheck read is producing something different from the
  // pre-migration baseline.
  if !alive_json.contains("unbound variable: y") {
    fail(
      "expected typecheck diagnostic for unbound `y` on alive editor, got \{alive_json}",
    )
  }
  if !alive_json.contains("\"def_name\":\"x\"") {
    fail("expected def_name=\"x\" on alive editor, got \{alive_json}")
  }
  let h = lambda_registry.get(handle).unwrap()
  let id = h.editor_id
  match coordinator.destroy_editor(id) {
    Ok(_) => ()
    Err(report) => fail("coordinator destroy: \{report}")
  }
  match lambda_registry.get(handle) {
    Some(_) => ()
    None =>
      fail(
        "expected lambda_registry to retain handle after direct coordinator destroy",
      )
  }
  // Post-destroy must collapse to "[]" via the Err arm of read_protected.
  assert_eq(get_diagnostics_json(handle), "[]")
  h.companion.dispose_analysis_attachment()
  lambda_registry.remove(handle)
  pretty_view_states.remove(handle)
  if last_created_handle.val == Some(handle) {
    last_created_handle.val = None
  }
}

///|
/// Companion to the typecheck-path test: parse-error sources go through
/// `parser_diagnostics`, the first protected cell read. Without that cell
/// also routing through the coordinator, a destroyed editor with stale
/// parse errors would leak them to the accessor before the typecheck/eval
/// guards fire.
test "workstream 1: get_diagnostics_json collapses to [] after coordinator destroy (parse-error path)" {
  reset_coordinator_for_phase1_tests()
  let handle = create_editor("diag_coord_parse_agent")
  // Trailing operator with no RHS — guaranteed parse error.
  set_text(handle, "let x = 1 +\n")
  let alive_json = get_diagnostics_json(handle)
  if !alive_json.contains("\"level\":\"error\"") {
    fail("expected parse-error diagnostic on alive editor, got \{alive_json}")
  }
  let h = lambda_registry.get(handle).unwrap()
  let id = h.editor_id
  match coordinator.destroy_editor(id) {
    Ok(_) => ()
    Err(report) => fail("coordinator destroy: \{report}")
  }
  assert_eq(get_diagnostics_json(handle), "[]")
  h.companion.dispose_analysis_attachment()
  lambda_registry.remove(handle)
  pretty_view_states.remove(handle)
  if last_created_handle.val == Some(handle) {
    last_created_handle.val = None
  }
}
