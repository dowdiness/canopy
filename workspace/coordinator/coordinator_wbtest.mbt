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
