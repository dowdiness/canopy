///| Smoke tests for SyncEditor history accessors (Phase 0).

///|
test "fresh SyncEditor produces empty causal snapshot" {
  let se = @probe.new_test_editor("alice")
  let snap = se.causal_snapshot()
  inspect(snap.op_count(), content="0")
  @debug.debug_inspect(snap.frontier(), content="[]")
}

///|
test "two SyncEditors have distinct construction identities" {
  let a = @probe.new_test_editor("alice")
  let b = @probe.new_test_editor("bob")
  // Same instance always returns the same identity.
  inspect(a.identity() == a.identity(), content="true")
  // Distinct instances have distinct identities.
  inspect(a.identity() == b.identity(), content="false")
}
