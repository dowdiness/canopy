// Unit tests for workspace/coordinator. See plan §PR3.3.

///|
test "Coordinator types are constructible" {
  let coord = Coordinator::new()
  let _ : @incr.Runtime = coord.runtime()
}

///|
/// `Runtime::set_on_change` is single-occupancy (spec §6.1, claimed by
/// `Coordinator::new`). Later tests in this file MUST NOT install their own
/// on_change listeners or they will overwrite the coordinator's stub.
test "Coordinator::new claims the on_change slot without aborting" {
  let coord = Coordinator::new()
  let rt = coord.runtime()
  // No assertion: this just verifies the slot is in use and the second
  // assignment overwrites cleanly. Phase 2 multiplexes registered listeners.
  rt.set_on_change(fn() {  })
}

///|
test "register_editor returns a fresh EditorId and stores the registration" {
  let coord = Coordinator::new()
  let rt = coord.runtime()
  let d = @incr.Derived::Derived(rt, fn() { 42 }, label="probe")
  let pcell = ProtectedCell::from_derived("probe_label", d)
  let id = coord.register_editor("agent_x", [pcell.erase()])
  assert_eq(id, EditorId(0))
  let id2 = coord.register_editor("agent_y", [])
  assert_eq(id2, EditorId(1))
}

///|
test "read_protected reads through the typed cell" {
  let coord = Coordinator::new()
  let rt = coord.runtime()
  let d = @incr.Derived::Derived(rt, fn() { 99 }, label="probe")
  let pcell = ProtectedCell::from_derived("probe", d)
  let id = coord.register_editor("agent", [pcell.erase()])
  match coord.read_protected(id, pcell) {
    Ok(v) => assert_eq(v, 99)
    Err(report) => fail("expected Ok, got \{report}")
  }
}

///|
test "read_protected rejects a cell not in editor's protected set" {
  let coord = Coordinator::new()
  let rt = coord.runtime()
  let d_a = @incr.Derived::Derived(rt, fn() { 1 }, label="a")
  let d_b = @incr.Derived::Derived(rt, fn() { 2 }, label="b")
  let pa = ProtectedCell::from_derived("a", d_a)
  let pb = ProtectedCell::from_derived("b", d_b)
  let id_a = coord.register_editor("a", [pa.erase()])
  match coord.read_protected(id_a, pb) {
    Ok(_) => fail("expected CellNotInProtectedSurface")
    Err(r) => assert_eq(r.kind, CellNotInProtectedSurface)
  }
}

///|
test "register_dep + unregister_dep round trip" {
  let coord = Coordinator::new()
  let rt = coord.runtime()
  let editor_cell = @incr.Derived::Derived(rt, fn() { 1 }, label="ec")
  let ws_cell = @incr.Derived::Derived(rt, fn() { 2 }, label="ws")
  let pe = ProtectedCell::from_derived("ec", editor_cell)
  let id = coord.register_editor("agent", [pe.erase()])
  coord.register_dep(ws_cell.id(), id, editor_cell.id())
  // Idempotent: a second call with the same edge is a no-op.
  coord.register_dep(ws_cell.id(), id, editor_cell.id())
  coord.unregister_dep(ws_cell.id(), id, editor_cell.id())
  // Idempotent: a second remove is a no-op.
  coord.unregister_dep(ws_cell.id(), id, editor_cell.id())
}

///|
test "destroy_editor refuses while a dep edge points at this editor" {
  let coord = Coordinator::new()
  let rt = coord.runtime()
  let d = @incr.Derived::Derived(rt, fn() { 1 }, label="ec")
  let pe = ProtectedCell::from_derived("ec", d)
  let id = coord.register_editor("agent", [pe.erase()])
  let ws_cell = @incr.Derived::Derived(rt, fn() { 0 }, label="ws")
  coord.register_dep(ws_cell.id(), id, d.id())
  match coord.destroy_editor(id) {
    Ok(_) => fail("expected DestroyWhileDependedUpon")
    Err(r) => assert_eq(r.kind, DestroyWhileDependedUpon)
  }
  coord.unregister_dep(ws_cell.id(), id, d.id())
  match coord.destroy_editor(id) {
    Ok(_) => ()
    Err(r) => fail("expected Ok after unregister_dep, got \{r}")
  }
}

///|
test "read_protected after destroy returns EditorDestroyed with full context" {
  let coord = Coordinator::new()
  let rt = coord.runtime()
  let d = @incr.Derived::Derived(rt, fn() { 7 }, label="ec")
  let pe = ProtectedCell::from_derived("ec", d)
  let id = coord.register_editor("test_agent", [pe.erase()])
  match coord.destroy_editor(id) {
    Ok(_) => ()
    Err(r) => fail("destroy: \{r}")
  }
  // After destroy: registration stays (alive=false) so error carries
  // agent_id + cell_label, not the bare-handle path.
  match coord.read_protected(id, pe) {
    Ok(_) => fail("expected EditorDestroyed")
    Err(r) => {
      assert_eq(r.kind, EditorDestroyed)
      assert_eq(r.agent_id, "test_agent")
    }
  }
}
