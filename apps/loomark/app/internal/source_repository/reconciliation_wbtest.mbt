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
