///|
test "replica writes coalesce conflict recovery directly" {
  let first = edit_write(initial_replica("base"), "local")
  let conflict = preserve_conflict(
    first.replica(),
    remote_present(1.0, "remote"),
    "recovery",
  )
  let newer = edit_write(conflict.replica(), "newer local")
  guard conflict.coalesce(newer) is StoreWithRecovery(replica, recovery) else {
    fail("expected retained recovery")
  }
  assert_eq(replica, newer.replica())
  assert_eq(recovery.id(), test_document_id("recovery"))
}
