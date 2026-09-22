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
test "DocumentId admits only UUID identities" {
  for invalid in ["", "document", "a0000000-0000-9000-8000-000000000001"] {
    assert_true(
      try {
        DocumentId::parse(invalid) |> ignore
        false
      } catch {
        InvalidIdentity => true
      },
    )
  }
  let valid = "a0000000-0000-4000-8000-000000000001"
  assert_eq(DocumentId::parse(valid).value(), valid)
}

///|
test "DocumentId parses identity and Document updates exactly" {
  assert_true(rejects_empty_id())
  assert_true(valid_uuid(test_document_id("identity").value()))
  let first = doc("a", "old")
  assert_eq(first.update("new").text(), "new")
  assert_eq(first.text(), "old")
}

///|
test "Document accessors preserve ownership" {
  let text = "exact\n日本語"
  let value = doc("id", text)
  assert_eq(value.id(), test_document_id("id"))
  assert_eq(value.text(), text)
}

///|
test "from_documents sorts lexical and accepts empty" {
  let saved = SavedDocuments::from_documents([doc("z", "z"), doc("a", "a")]).unwrap()
  assert_eq(saved.all().map(x => x.id()), [
    test_document_id("a"),
    test_document_id("z"),
  ])
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
  assert_eq(inserted.all().map(x => x.id()), [
    test_document_id("a"),
    test_document_id("b"),
  ])
  assert_eq(
    inserted
    .apply(RepositoryChange::Deleted(test_document_id("a")))
    .unwrap()
    .all()
    .map(x => x.id()),
    [test_document_id("b")],
  )
  assert_eq(
    inserted.apply(RepositoryChange::Deleted(test_document_id("missing"))),
    None,
  )
}

///|
test "from_documents keeps lexical order without startup selection state" {
  let saved = SavedDocuments::from_documents([doc("b", "b"), doc("a", "a")]).unwrap()
  assert_eq(saved.all().map(document => document.id()), [
    test_document_id("a"),
    test_document_id("b"),
  ])
}

///|
test "replica updates preserve document projections without rebuilding them" {
  let saved = SavedDocuments::from_documents([doc("local", "# Local\n")]).unwrap()
  let sentinel = { ..saved, catalog_value: Catalog([]), }
  let replica = DocumentReplica(test_account(), doc("remote", "remote"))
  let updated = sentinel.apply_replica(replica)
  assert_eq(updated.all(), sentinel.all())
  assert_eq(updated.catalog(), sentinel.catalog())
  assert_eq(updated.issues(), sentinel.issues())
}

///|
test "replica insertion and replacement retain lexical order" {
  let initial = SavedDocuments::from_documents([]).unwrap()
  let account_b = DocumentReplica(
    test_account(value="account-b"),
    doc("same", "B"),
  )
  let account_a_z = DocumentReplica(test_account(), doc("z", "Z"))
  let account_a_a = DocumentReplica(test_account(), doc("a", "A"))
  let saved = initial
    .apply_replica(account_b)
    .apply_replica(account_a_z)
    .apply_replica(account_a_a)
  assert_eq(
    saved.replicas_for(test_account()).map(value => value.document_id()),
    [test_document_id("a"), test_document_id("z")],
  )
  let replacement = edit_write(account_a_a, "new").replica()
  let replaced = saved.apply_replica(replacement)
  assert_eq(
    replaced.replicas_for(test_account()).map(value => value.document_id()),
    [test_document_id("a"), test_document_id("z")],
  )
  assert_eq(
    replica_document(replaced.replicas_for(test_account())[0]).text(),
    "new",
  )
  let stale : Result[SavedDocuments, ReplicaApplyError] = Ok(
    replaced.apply_replica(account_a_a),
  ) catch {
    error => Err(error)
  }
  assert_eq(stale, Err(ReplicaApplyError::StaleReplica))
}

///|
test "replica lookup keeps account ownership explicit" {
  let account_a = test_account()
  let account_b = test_account(value="account-b")
  let replica = DocumentReplica(account_a, doc("one", "a"))
  let saved = SavedDocuments::from_documents([]).unwrap().apply_replica(replica)
  assert_eq(saved.replica(account_a, test_document_id("one")), Some(replica))
  assert_eq(saved.replica(account_b, test_document_id("one")), None)
}

///|
test "committed replica removal removes only its account membership" {
  let account_a = test_account()
  let account_b = test_account(value="account-b")
  let replica_a = DocumentReplica(account_a, doc("shared", "A"))
  let replica_b = DocumentReplica(account_b, doc("shared", "B"))
  let saved = SavedDocuments::from_documents([doc("local", "local")])
    .unwrap()
    .apply_replica(replica_a)
    .apply_replica(replica_b)
  let removed = saved.apply_replica_write(ReplicaWrite::Remove(replica_a))
  assert_eq(removed.replica(account_a, test_document_id("shared")), None)
  assert_eq(
    removed.replica(account_b, test_document_id("shared")),
    Some(replica_b),
  )
  assert_eq(
    removed.find(test_document_id("local")),
    Some(doc("local", "local")),
  )
}

///|
test "replica removal commits identity despite unpersisted newer text" {
  let durable = DocumentReplica(test_account(), doc("one", "durable"))
  let saved = SavedDocuments::from_documents([]).unwrap().apply_replica(durable)
  guard durable.edit("newer") is EditPlan::Persist(newer) else {
    fail("newer candidate")
  }
  let removed = saved.apply_replica_write(ReplicaWrite::Remove(newer.replica()))
  assert_eq(removed.replica(test_account(), test_document_id("one")), None)
}

///|
test "committed conflict applies replica and recovery source atomically" {
  let base = DocumentReplica(test_account(), doc("one", "base"))
  let saved = SavedDocuments::from_documents([]).unwrap().apply_replica(base)
  let sent = start_save(base, TEST_OPERATION_1)
  let acknowledged = sent
    .replica()
    .acknowledge(test_operation(TEST_OPERATION_1), test_revision(1.0))
  let edited = edit_write(acknowledged.replica(), "local").replica()
  let write = preserve_conflict(
    edited,
    remote_present(2.0, "remote"),
    "recovery",
  )
  guard write is Fork(replica, recovery) else { fail("conflict write") }
  let committed = saved.apply_replica_write(write)
  assert_eq(
    committed.replica(test_account(), test_document_id("one")),
    Some(replica),
  )
  assert_eq(committed.find(recovery.id()), Some(recovery))
}
