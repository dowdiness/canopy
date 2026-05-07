///| Smoke tests for SyncEditor history accessors (Phase 0).

///|
test "fresh SyncEditor produces empty causal snapshot" {
  let se = @lambda.new_lambda_editor("alice").0
  let snap = se.causal_snapshot()
  inspect(snap.op_count(), content="0")
  inspect(snap.frontier(), content="[]")
}

///|
test "two SyncEditors have distinct construction identities" {
  let a = @lambda.new_lambda_editor("alice").0
  let b = @lambda.new_lambda_editor("bob").0
  // Same instance always returns the same identity.
  inspect(a.identity() == a.identity(), content="true")
  // Distinct instances have distinct identities.
  inspect(a.identity() == b.identity(), content="false")
}
