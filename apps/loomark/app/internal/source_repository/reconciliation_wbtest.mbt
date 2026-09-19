///|
fn rdoc(id : String, text : String) -> Document {
  Document::create(id, text) catch {
    _ => abort("invalid test id")
  }
}

///|
fn rentry(id : String, text : String) -> @indexed_db.Entry {
  @indexed_db.Entry::StringRecord(
    "source/v1/" + id,
    encode_document(rdoc(id, text)),
  )
}

///|
test "reconciliation derives catalog and preserves unrelated observations" {
  let (saved, selected) = reconcile_scan([
    rentry("b", "# B\n"),
    rentry("a", "# A\n"),
    @indexed_db.Entry::StringRecord("other", "x"),
  ])
  guard selected is Some(selected) else { fail("missing selection") }
  assert_eq(selected.id(), "a")
  assert_eq(saved.all().map(x => x.id()), ["a", "b"])
  assert_eq(saved.issues(), [RepositoryIssue::UnknownRecord("other")])
}

///|
test "reconciliation isolates malformed unknown and unsupported records" {
  let (saved, selected) = reconcile_scan([
    @indexed_db.Entry::StringRecord("source/v1/bad", "nope"),
    @indexed_db.Entry::UnsupportedValue("source/v1/binary"),
    @indexed_db.Entry::StringRecord("source/v2/future", "x"),
    @indexed_db.Entry::UnsupportedValue("metadata"),
    @indexed_db.Entry::UnsupportedKey(4),
  ])
  assert_eq(selected, None)
  assert_eq(saved.all(), [])
  assert_eq(saved.issues(), [
    RepositoryIssue::InvalidSource("source/v1/bad"),
    RepositoryIssue::InvalidSource("source/v1/binary"),
    RepositoryIssue::UnsupportedSourceSchema("source/v2/future"),
    RepositoryIssue::UnsupportedRecord("metadata"),
    RepositoryIssue::UnsupportedKey(4),
  ])
}

///|
test "only exact editing-document string selects a valid document" {
  let entries = [
    rentry("a", "a"),
    rentry("b", "b"),
    @indexed_db.Entry::StringRecord("editing-document", "b"),
  ]
  let (_, selected) = reconcile_scan(entries)
  guard selected is Some(selected) else { fail("missing selection") }
  assert_eq(selected.id(), "b")
  let (_, fallback) = reconcile_scan([
    rentry("a", "a"),
    @indexed_db.Entry::StringRecord("editing-document", "missing"),
  ])
  guard fallback is Some(fallback) else { fail("missing fallback") }
  assert_eq(fallback.id(), "a")
  let (_, non_string_fallback) = reconcile_scan([
    rentry("a", "a"),
    @indexed_db.Entry::UnsupportedValue("editing-document"),
  ])
  guard non_string_fallback is Some(non_string_fallback) else {
    fail("missing non-string fallback")
  }
  assert_eq(non_string_fallback.id(), "a")
}

///|
test "duplicate valid payload ids are not admitted twice" {
  let (saved, _) = reconcile_scan([
    rentry("a", "a"),
    @indexed_db.Entry::StringRecord(
      "source/v1/b",
      encode_document(rdoc("a", "other")),
    ),
  ])
  assert_eq(saved.all().map(x => x.id()), ["a"])
  assert_eq(saved.issues(), [RepositoryIssue::InvalidSource("source/v1/b")])
}

///|
test "opening empty scan is ready without writing" {
  let (saved, selected) = reconcile_scan([])
  assert_eq(selected, None)
  assert_eq(saved.catalog().entries(), [])
}

///|
test "legacy sources remain readable beside account-scoped checkpoints" {
  let account_a = SyncCheckpoint::enroll(test_account(), rdoc("shared", "A"))
  let account_b = SyncCheckpoint::enroll(
    test_account(value="account-b"),
    rdoc("shared", "B"),
  )
  let (saved, selected) = reconcile_scan([
    rentry("legacy", "legacy text"),
    @indexed_db.Entry::StringRecord(
      sync_key(test_account(value="account-b"), "shared"),
      encode_checkpoint(account_b),
    ),
    @indexed_db.Entry::StringRecord(
      sync_key(test_account(), "shared"),
      encode_checkpoint(account_a),
    ),
  ])
  assert_eq(selected, Some(rdoc("legacy", "legacy text")))
  assert_eq(saved.all(), [rdoc("legacy", "legacy text")])
  assert_eq(saved.checkpoints_for(test_account()), [account_a])
  assert_eq(saved.checkpoints_for(test_account(value="account-b")), [account_b])
  assert_eq(saved.checkpoints_for(test_account(value="account-c")), [])
  assert_eq(saved.issues(), [])
}

///|
test "malformed sync data is isolated without hiding legacy sources" {
  let key = sync_key(test_account(), "bad")
  let (saved, selected) = reconcile_scan([
    rentry("legacy", "safe"),
    @indexed_db.Entry::StringRecord(key, "{}"),
    @indexed_db.Entry::StringRecord("sync/malformed", "malformed"),
  ])
  assert_eq(selected, Some(rdoc("legacy", "safe")))
  assert_eq(saved.checkpoints_for(test_account()), [])
  assert_eq(saved.issues(), [
    RepositoryIssue::InvalidSyncCheckpoint(key),
    RepositoryIssue::InvalidSyncCheckpoint("sync/malformed"),
  ])
}
