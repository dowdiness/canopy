///|
fn doc(id : String, text : String) -> Document {
  Document::create(test_document_id(id), text)
}

///|
fn rejects_empty_id() -> Bool {
  let _ = DocumentId::parse("") catch { err => return err == InvalidIdentity }
  false
}

///|
test "DocumentId parses identity and Document updates exactly" {
  assert_true(rejects_empty_id())
  assert_eq(test_document_id("identity").value(), "identity")
  let first = doc("a", "old")
  assert_eq(first.update("new").text(), "new")
  assert_eq(first.text(), "old")
}

///|
test "Document accessors preserve ownership" {
  let text = "exact\n日本語"
  let value = doc("id", text)
  assert_eq(value.id().value(), "id")
  assert_eq(value.text(), text)
}

///|
test "from_documents sorts lexical and accepts empty" {
  let saved = SavedDocuments::from_documents([doc("z", "z"), doc("a", "a")]).unwrap()
  assert_eq(saved.all().map(x => x.id().value()), ["a", "z"])
  assert_eq(SavedDocuments::from_documents([]).unwrap().all(), [])
}

///|
test "from_documents rejects duplicate identities" {
  assert_eq(
    SavedDocuments::from_documents([doc("a", "1"), doc("a", "2")]),
    None,
  )
}

///|
test "catalog derives names in document order" {
  let saved = SavedDocuments::from_documents([
    doc("b", "# Bee\n"),
    doc("a", "plain"),
  ]).unwrap()
  assert_eq(saved.catalog().entries().map(x => (x.document_id(), x.name())), [
    (test_document_id("a"), "plain"),
    (test_document_id("b"), "Bee"),
  ])
}

///|
test "apply stores replacement and preserves unrelated issue" {
  let saved = SavedDocuments::from_documents([doc("a", "old"), doc("b", "b")]).unwrap()
  let next = saved.apply(RepositoryChange::Stored(doc("a", "new"))).unwrap()
  assert_eq(next.find(test_document_id("a")).unwrap().text(), "new")
  assert_eq(saved.find(test_document_id("a")).unwrap().text(), "old")
}

///|
test "apply inserts and deletes while retaining lexical order" {
  let saved = SavedDocuments::from_documents([doc("b", "b")]).unwrap()
  let inserted = saved.apply(RepositoryChange::Stored(doc("a", "a"))).unwrap()
  assert_eq(inserted.all().map(x => x.id().value()), ["a", "b"])
  assert_eq(
    inserted
    .apply(RepositoryChange::Deleted(test_document_id("a")))
    .unwrap()
    .all()
    .map(x => x.id().value()),
    ["b"],
  )
  assert_eq(
    inserted.apply(RepositoryChange::Deleted(test_document_id("missing"))),
    None,
  )
}

///|
test "from_documents keeps lexical order without startup selection state" {
  let saved = SavedDocuments::from_documents([doc("b", "b"), doc("a", "a")]).unwrap()
  assert_eq(saved.all().map(document => document.id().value()), ["a", "b"])
}

///|
test "checkpoint updates preserve document projections without rebuilding them" {
  let saved = SavedDocuments::from_documents([doc("local", "# Local\n")]).unwrap()
  let sentinel = { ..saved, catalog_value: Catalog([]), }
  let checkpoint = SyncCheckpoint::enroll(
    test_account(),
    doc("remote", "remote"),
  )
  let updated = sentinel.apply_checkpoint(checkpoint)
  assert_eq(updated.all(), sentinel.all())
  assert_eq(updated.catalog(), sentinel.catalog())
  assert_eq(updated.issues(), sentinel.issues())
}

///|
test "checkpoint insertion and replacement retain lexical order" {
  let initial = SavedDocuments::from_documents([]).unwrap()
  let account_b = SyncCheckpoint::enroll(
    test_account(value="account-b"),
    doc("same", "B"),
  )
  let account_a_z = SyncCheckpoint::enroll(test_account(), doc("z", "Z"))
  let account_a_a = SyncCheckpoint::enroll(test_account(), doc("a", "A"))
  let saved = initial
    .apply_checkpoint(account_b)
    .apply_checkpoint(account_a_z)
    .apply_checkpoint(account_a_a)
  assert_eq(
    saved
    .checkpoints_for(test_account())
    .map(value => value.document().id().value()),
    ["a", "z"],
  )
  let replacement = account_a_a.edit("new").unwrap().checkpoint()
  let replaced = saved.apply_checkpoint(replacement)
  assert_eq(
    replaced
    .checkpoints_for(test_account())
    .map(value => value.document().id().value()),
    ["a", "z"],
  )
  assert_eq(
    replaced.checkpoints_for(test_account())[0].document().text(),
    "new",
  )
  let stale : Result[SavedDocuments, CheckpointApplyError] = Ok(
    replaced.apply_checkpoint(account_a_a),
  ) catch {
    error => Err(error)
  }
  assert_eq(stale, Err(CheckpointApplyError::StaleCheckpoint))
}

///|
test "checkpoint lookup keeps account ownership explicit" {
  let account_a = test_account()
  let account_b = test_account(value="account-b")
  let checkpoint = SyncCheckpoint::enroll(account_a, doc("one", "a"))
  let saved = SavedDocuments::from_documents([])
    .unwrap()
    .apply_checkpoint(checkpoint)
  assert_eq(
    saved.checkpoint(account_a, test_document_id("one")),
    Some(checkpoint),
  )
  assert_eq(saved.checkpoint(account_b, test_document_id("one")), None)
}
