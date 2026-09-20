///|
test "checkpoint writes coalesce conflict recovery directly" {
  let first = edit_write(enrolled("base"), "local")
  let conflict = preserve_conflict(
    first.checkpoint(),
    remote_present(1.0, "remote"),
    "recovery",
  )
  let newer = edit_write(conflict.checkpoint(), "newer local")
  guard conflict.coalesce(newer) is CheckpointAndRecovery(checkpoint, recovery) else {
    fail("expected retained recovery")
  }
  assert_eq(checkpoint, newer.checkpoint())
  assert_eq(recovery.id(), test_document_id("recovery"))
}
