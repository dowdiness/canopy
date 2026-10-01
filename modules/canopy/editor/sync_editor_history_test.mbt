///|
test "fresh SyncEditor produces empty causal snapshot" {
  let se = try! @probe.new_test_editor("alice")
  let snap = se.causal_snapshot()
  inspect(snap.op_count(), content="0")
  @debug.debug_inspect(snap.frontier(), content="[]")
}
