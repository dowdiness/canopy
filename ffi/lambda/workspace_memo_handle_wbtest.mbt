// Whitebox integration test for the §P0b workspace memo lifecycle API.
// Proves Coordinator::register_workspace_memo + WorkspaceMemoHandle drive
// register_dep / unregister_dep / destroy_editor gateway / read_protected
// end-to-end against real Lambda editor cells via the global `coordinator`.
//
// Spec: docs/superpowers/specs/2026-05-28-p0b-workspace-memo-lifecycle-api-design.md

///|
test "wmh A1: sanity sum equals known value across two editors" {
  reset_coordinator_for_phase1_tests()
  let handle_a = create_editor("wmh_a1_a")
  let handle_b = create_editor("wmh_a1_b")
  let h_a = lambda_handles.get(handle_a).unwrap()
  let h_b = lambda_handles.get(handle_b).unwrap()
  let sum_d : @incr.Derived[Int] = @incr.Derived(coordinator.runtime(), fn() {
    let sa = match
      coordinator.read_protected(h_a.editor_id, h_a.cells.parser_source) {
      Ok(s) => s
      Err(r) => abort("wmh A1 read h_a: \{r}")
    }
    let sb = match
      coordinator.read_protected(h_b.editor_id, h_b.cells.parser_source) {
      Ok(s) => s
      Err(r) => abort("wmh A1 read h_b: \{r}")
    }
    sa.length() + sb.length()
  })
  let handle = match coordinator.register_workspace_memo(sum_d, [
    (h_a.editor_id, h_a.cells.parser_source.cell_id()),
    (h_b.editor_id, h_b.cells.parser_source.cell_id()),
  ]) {
    Ok(h) => h
    Err(r) => fail("register_workspace_memo: \{r}")
  }
  h_a.editor.set_text("abc")
  h_b.editor.set_text("defgh")
  assert_eq(handle.read().unwrap(), 3 + 5)
  handle.dispose()
  match coordinator.destroy_editor(h_a.editor_id) {
    Ok(_) => ()
    Err(r) => fail("teardown destroy h_a: \{r}")
  }
  match coordinator.destroy_editor(h_b.editor_id) {
    Ok(_) => ()
    Err(r) => fail("teardown destroy h_b: \{r}")
  }
  h_a.companion.dispose_analysis_attachment()
  lambda_handles.remove(handle_a)
  view_states.remove(handle_a)
  pretty_view_states.remove(handle_a)
  h_b.companion.dispose_analysis_attachment()
  lambda_handles.remove(handle_b)
  view_states.remove(handle_b)
  pretty_view_states.remove(handle_b)
  if last_created_handle.val == Some(handle_b) {
    last_created_handle.val = None
  }
}
