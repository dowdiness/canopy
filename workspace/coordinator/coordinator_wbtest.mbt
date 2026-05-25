// Whitebox tests for workspace/coordinator. These need package-internal
// access to construct `ProtectedRead` directly (bypassing the public
// `ProtectedCell::from_derived` factory), so they live here rather than in
// `coordinator_test.mbt`.

///|
/// Mode-1 fail-fast (spec §13 D4): a `ProtectedRead` whose cell was never
/// rooted via `Derived::watch()` is a factory contract violation. Constructed
/// via the internal `ProtectedRead::ProtectedRead` constructor to bypass
/// `ProtectedCell::from_derived`'s priming.
test "panic register_editor aborts if any protected cell has gc_root_count == 0" {
  let coord = Coordinator::new()
  let rt = coord.runtime()
  let d = @incr.Derived::Derived(rt, fn() { 1 }, label="rogue")
  let pread = ProtectedRead::ProtectedRead(
    cell_id=d.id(),
    label="rogue",
    is_disposed=fn() { false },
    dispose=fn() {  },
  )
  let _ = coord.register_editor("agent", [pread])
}

///|
/// Spec §12 #5: defense-in-depth against out-of-band `Watch::dispose`. Under
/// normal flow, the coordinator destroys the editor before any watch is
/// disposed. If a caller bypasses the gateway and disposes a watch
/// directly, the next `read_protected` must surface
/// `AbortKind::ProtectedCellDisposed` rather than the underlying
/// `Watch::read` abort. We trigger the out-of-band path by calling the
/// dispose closure field directly — legal here because the test lives in
/// the same package as `ProtectedCell`.
test "spec §12 #5: read_protected catches out-of-band Watch dispose" {
  let coord = Coordinator::new()
  let rt = coord.runtime()
  let d = @incr.Derived::Derived(rt, fn() { 7 }, label="probe")
  let pcell = ProtectedCell::from_derived("probe", d)
  let id = coord.register_editor("agent", [pcell.erase()])
  (pcell.dispose)()
  match coord.read_protected(id, pcell) {
    Ok(_) => fail("expected ProtectedCellDisposed")
    Err(report) => assert_eq(report.kind, ProtectedCellDisposed)
  }
}

///|
/// Spec §12 #6: verify the `Err(CycleError) → AbortKind::CycleDetected`
/// mapping (not loom's cycle-detection algorithm itself, which is covered
/// by incr's own test suite). A self-referential `Derived::compute` closure
/// can't surface real `Err(CycleError)` through `Watch::read` today —
/// incr's memo machinery wraps the inner abort in its compute-body catch
/// handler, so the outer `Watch::read` receives a hard abort rather than
/// `Err(CycleError)`. To isolate the mapping concern, hand-build a
/// `ProtectedCell` whose `read` closure directly returns
/// `Err(CycleError::new(...))`. The cell_id points at a real,
/// watch-rooted Derived so the mode-1 fail-fast passes.
test "spec §12 #6: read_protected maps Err(CycleError) to CycleDetected" {
  let coord = Coordinator::new()
  let rt = coord.runtime()
  let anchor = @incr.Derived::Derived(rt, fn() { 0 }, label="anchor")
  // Explicit watch+prime so `register_editor`'s mode-1 check sees
  // gc_root_count > 0 for `anchor.id()`. Kept alive by the local binding.
  let watch = anchor.watch()
  let _ = watch.read()
  let cell_id = anchor.id()
  let synthetic_cycle = @incr.CycleError::new(cell_id, [cell_id], [
    Some("synthetic_cycle"),
  ])
  let pcell : ProtectedCell[Int] = ProtectedCell::ProtectedCell(
    cell_id~,
    label="synthetic_cycle",
    read=fn() { Err(synthetic_cycle) },
    is_disposed=fn() { false },
    dispose=fn() {  },
  )
  let id = coord.register_editor("agent", [pcell.erase()])
  match coord.read_protected(id, pcell) {
    Ok(_) => fail("expected CycleDetected")
    Err(report) => {
      assert_eq(report.kind, CycleDetected)
      assert_true(report.domain_tag is Some(_))
    }
  }
}
