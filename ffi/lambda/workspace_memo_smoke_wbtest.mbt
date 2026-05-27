// Whitebox integration test for the §P0b first real workspace memo.
// Proves end-to-end that Coordinator::register_dep / unregister_dep /
// destroy_editor gateway / read_protected hold against real Lambda
// editor cells built by the production `assemble_lambda_handle`
// factory + global `coordinator` singleton.
//
// Per spec §3.7, each test manually drives full teardown (unregister
// every registered dep, dispose the watch, bypass-destroy each editor,
// drain FFI bookkeeping) so correctness does not depend on coordinator
// state being empty at test start.
//
// Spec: docs/superpowers/specs/2026-05-28-p0b-first-workspace-memo-design.md

///|
test "smoke 5.1: sanity sum equals known value across two editors" {
  reset_coordinator_for_phase1_tests()
  let handle_a = create_editor("smoke_5_1_a")
  let handle_b = create_editor("smoke_5_1_b")
  let h_a = lambda_handles.get(handle_a).unwrap()
  let h_b = lambda_handles.get(handle_b).unwrap()

  // Build the workspace memo on the coordinator's runtime.
  let sum_d : @incr.Derived[Int] = @incr.Derived(coordinator.runtime(), fn() {
    let sa = match
      coordinator.read_protected(h_a.editor_id, h_a.cells.parser_source) {
      Ok(s) => s
      Err(r) => abort("workspace memo smoke 5.1 read h_a: \{r}")
    }
    let sb = match
      coordinator.read_protected(h_b.editor_id, h_b.cells.parser_source) {
      Ok(s) => s
      Err(r) => abort("workspace memo smoke 5.1 read h_b: \{r}")
    }
    sa.length() + sb.length()
  })
  let w = sum_d.watch()
  coordinator.register_dep(
    sum_d.id(),
    h_a.editor_id,
    h_a.cells.parser_source.cell_id(),
  )
  coordinator.register_dep(
    sum_d.id(),
    h_b.editor_id,
    h_b.cells.parser_source.cell_id(),
  )

  // Drive the editors to known sources.
  h_a.editor.set_text("abc")
  h_b.editor.set_text("defgh")
  assert_eq(w.read().unwrap(), 3 + 5)

  // Teardown per spec §3.7 (bypass-destroy + FFI drain).
  coordinator.unregister_dep(
    sum_d.id(),
    h_a.editor_id,
    h_a.cells.parser_source.cell_id(),
  )
  coordinator.unregister_dep(
    sum_d.id(),
    h_b.editor_id,
    h_b.cells.parser_source.cell_id(),
  )
  w.dispose()
  match coordinator.destroy_editor(h_a.editor_id) {
    Ok(_) => ()
    Err(r) => fail("teardown destroy h_a: \{r}")
  }
  h_a.companion.dispose_analysis_attachment()
  lambda_handles.remove(handle_a)
  view_states.remove(handle_a)
  pretty_view_states.remove(handle_a)
  match coordinator.destroy_editor(h_b.editor_id) {
    Ok(_) => ()
    Err(r) => fail("teardown destroy h_b: \{r}")
  }
  h_b.companion.dispose_analysis_attachment()
  lambda_handles.remove(handle_b)
  view_states.remove(handle_b)
  pretty_view_states.remove(handle_b)
  if last_created_handle.val == Some(handle_b) {
    last_created_handle.val = None
  }
}

///|
test "smoke 5.2: mutation in editor A invalidates workspace memo and recomputes" {
  reset_coordinator_for_phase1_tests()
  let handle_a = create_editor("smoke_5_2_a")
  let handle_b = create_editor("smoke_5_2_b")
  let h_a = lambda_handles.get(handle_a).unwrap()
  let h_b = lambda_handles.get(handle_b).unwrap()

  let sum_d : @incr.Derived[Int] = @incr.Derived(coordinator.runtime(), fn() {
    let sa = match
      coordinator.read_protected(h_a.editor_id, h_a.cells.parser_source) {
      Ok(s) => s
      Err(r) => abort("workspace memo smoke 5.2 read h_a: \{r}")
    }
    let sb = match
      coordinator.read_protected(h_b.editor_id, h_b.cells.parser_source) {
      Ok(s) => s
      Err(r) => abort("workspace memo smoke 5.2 read h_b: \{r}")
    }
    sa.length() + sb.length()
  })
  let w = sum_d.watch()
  coordinator.register_dep(
    sum_d.id(),
    h_a.editor_id,
    h_a.cells.parser_source.cell_id(),
  )
  coordinator.register_dep(
    sum_d.id(),
    h_b.editor_id,
    h_b.cells.parser_source.cell_id(),
  )

  // Prime with initial values.
  h_a.editor.set_text("ab")
  h_b.editor.set_text("cd")
  assert_eq(w.read().unwrap(), 2 + 2)

  // Mutate editor A's source; the workspace memo must recompute on next read.
  h_a.editor.set_text("abcdef")
  assert_eq(w.read().unwrap(), 6 + 2)

  // Teardown per spec §3.7.
  coordinator.unregister_dep(
    sum_d.id(),
    h_a.editor_id,
    h_a.cells.parser_source.cell_id(),
  )
  coordinator.unregister_dep(
    sum_d.id(),
    h_b.editor_id,
    h_b.cells.parser_source.cell_id(),
  )
  w.dispose()
  match coordinator.destroy_editor(h_a.editor_id) {
    Ok(_) => ()
    Err(r) => fail("teardown destroy h_a: \{r}")
  }
  h_a.companion.dispose_analysis_attachment()
  lambda_handles.remove(handle_a)
  view_states.remove(handle_a)
  pretty_view_states.remove(handle_a)
  match coordinator.destroy_editor(h_b.editor_id) {
    Ok(_) => ()
    Err(r) => fail("teardown destroy h_b: \{r}")
  }
  h_b.companion.dispose_analysis_attachment()
  lambda_handles.remove(handle_b)
  view_states.remove(handle_b)
  pretty_view_states.remove(handle_b)
  if last_created_handle.val == Some(handle_b) {
    last_created_handle.val = None
  }
}

///|
test "smoke 5.3: destroy_editor refused while workspace memo dep is live" {
  reset_coordinator_for_phase1_tests()
  let handle_a = create_editor("smoke_5_3_a")
  let handle_b = create_editor("smoke_5_3_b")
  let h_a = lambda_handles.get(handle_a).unwrap()
  let h_b = lambda_handles.get(handle_b).unwrap()

  let sum_d : @incr.Derived[Int] = @incr.Derived(coordinator.runtime(), fn() {
    let sa = match
      coordinator.read_protected(h_a.editor_id, h_a.cells.parser_source) {
      Ok(s) => s
      Err(r) => abort("workspace memo smoke 5.3 read h_a: \{r}")
    }
    let sb = match
      coordinator.read_protected(h_b.editor_id, h_b.cells.parser_source) {
      Ok(s) => s
      Err(r) => abort("workspace memo smoke 5.3 read h_b: \{r}")
    }
    sa.length() + sb.length()
  })
  let w = sum_d.watch()
  coordinator.register_dep(
    sum_d.id(),
    h_a.editor_id,
    h_a.cells.parser_source.cell_id(),
  )
  coordinator.register_dep(
    sum_d.id(),
    h_b.editor_id,
    h_b.cells.parser_source.cell_id(),
  )

  h_a.editor.set_text("hi")
  h_b.editor.set_text("world")
  let pre_sum = w.read().unwrap()

  // Destroy must refuse with the precise AbortReport shape spec §5.3 asserts.
  match coordinator.destroy_editor(h_a.editor_id) {
    Ok(_) => fail("expected DestroyWhileDependedUpon, got Ok")
    Err(report) => {
      assert_eq(report.kind, @workspace.DestroyWhileDependedUpon)
      assert_eq(report.editor_id, h_a.editor_id)
      @debug.assert_eq(report.cell_id, Some(sum_d.id()))
    }
  }

  // Editor A must still be alive — re-read the memo and assert the sum is unchanged.
  assert_eq(w.read().unwrap(), pre_sum)

  // Stronger aliveness: mutate editor A AFTER the refused destroy and assert
  // the memo recomputes from the new source. This is what "still alive" must
  // mean operationally — accepting writes and propagating invalidation. A
  // bare value-equality reread alone would also pass if the editor were
  // half-dead (e.g., reads served from a frozen cache).
  h_a.editor.set_text("hello-after-refused-destroy")
  assert_eq(w.read().unwrap(), 27 + 5)

  // Teardown per spec §3.7.
  coordinator.unregister_dep(
    sum_d.id(),
    h_a.editor_id,
    h_a.cells.parser_source.cell_id(),
  )
  coordinator.unregister_dep(
    sum_d.id(),
    h_b.editor_id,
    h_b.cells.parser_source.cell_id(),
  )
  w.dispose()
  match coordinator.destroy_editor(h_a.editor_id) {
    Ok(_) => ()
    Err(r) => fail("teardown destroy h_a: \{r}")
  }
  h_a.companion.dispose_analysis_attachment()
  lambda_handles.remove(handle_a)
  view_states.remove(handle_a)
  pretty_view_states.remove(handle_a)
  match coordinator.destroy_editor(h_b.editor_id) {
    Ok(_) => ()
    Err(r) => fail("teardown destroy h_b: \{r}")
  }
  h_b.companion.dispose_analysis_attachment()
  lambda_handles.remove(handle_b)
  view_states.remove(handle_b)
  pretty_view_states.remove(handle_b)
  if last_created_handle.val == Some(handle_b) {
    last_created_handle.val = None
  }
}

///|
test "smoke 5.4: clean teardown sequence — each step returns Ok" {
  reset_coordinator_for_phase1_tests()
  let handle_a = create_editor("smoke_5_4_a")
  let handle_b = create_editor("smoke_5_4_b")
  let h_a = lambda_handles.get(handle_a).unwrap()
  let h_b = lambda_handles.get(handle_b).unwrap()

  let sum_d : @incr.Derived[Int] = @incr.Derived(coordinator.runtime(), fn() {
    let sa = match
      coordinator.read_protected(h_a.editor_id, h_a.cells.parser_source) {
      Ok(s) => s
      Err(r) => abort("workspace memo smoke 5.4 read h_a: \{r}")
    }
    let sb = match
      coordinator.read_protected(h_b.editor_id, h_b.cells.parser_source) {
      Ok(s) => s
      Err(r) => abort("workspace memo smoke 5.4 read h_b: \{r}")
    }
    sa.length() + sb.length()
  })
  let w = sum_d.watch()
  coordinator.register_dep(
    sum_d.id(),
    h_a.editor_id,
    h_a.cells.parser_source.cell_id(),
  )
  coordinator.register_dep(
    sum_d.id(),
    h_b.editor_id,
    h_b.cells.parser_source.cell_id(),
  )
  h_a.editor.set_text("x")
  h_b.editor.set_text("yz")
  let _ = w.read().unwrap() // prime

  // Teardown — every step's outcome asserted.
  coordinator.unregister_dep(
    sum_d.id(),
    h_a.editor_id,
    h_a.cells.parser_source.cell_id(),
  )
  coordinator.unregister_dep(
    sum_d.id(),
    h_b.editor_id,
    h_b.cells.parser_source.cell_id(),
  )
  w.dispose()

  // After unregister + dispose, destroy must succeed.
  match coordinator.destroy_editor(h_a.editor_id) {
    Ok(_) => ()
    Err(report) =>
      fail("expected Ok destroying h_a after unregister, got \{report}")
  }
  match coordinator.destroy_editor(h_b.editor_id) {
    Ok(_) => ()
    Err(report) =>
      fail("expected Ok destroying h_b after unregister, got \{report}")
  }

  // Drain FFI bookkeeping so leaks don't pollute later tests.
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
