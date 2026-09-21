///|
fn command_doc(id : String) -> Document {
  Document::create(test_document_id(id), "# text\n")
}

///|
test "open begins with complete Store entries scan" {
  assert_true(
    @debug.to_string(open(_ => @cmd.none)).contains("IndexedDBEntries"),
  )
}

///|
test "saved membership parses an exact editing hint" {
  let saved = SavedDocuments::from_documents([command_doc("a")]).unwrap()
  assert_eq(
    saved.editing_document_hint(test_document_id("a")),
    Some(EditingDocumentHint(test_document_id("a"))),
  )
  assert_eq(saved.editing_document_hint(test_document_id("missing")), None)
}

///|
test "remembering a parsed hint writes the advisory record" {
  let saved = SavedDocuments::from_documents([command_doc("a")]).unwrap()
  let hint = saved.editing_document_hint(test_document_id("a")).unwrap()
  assert_true(@debug.to_string(hint.remember()).contains("IndexedDBApply"))
}

///|
test "save replaces a known document" {
  let saved = SavedDocuments::from_documents([command_doc("a")]).unwrap()
  assert_true(
    @debug.to_string(save(saved, command_doc("a"), _ => @cmd.none)).contains(
      "IndexedDBApply",
    ),
  )
}

///|
test "save inserts only at unobserved key" {
  let saved = SavedDocuments::from_documents([]).unwrap()
  assert_true(
    @debug.to_string(save(saved, command_doc("new"), _ => @cmd.none)).contains(
      "IndexedDBApply",
    ),
  )
  let (saved, _) = reconcile_scan([
    @indexed_db.Entry::StringRecord(source_key(test_document_id("new")), "bad"),
  ])
  assert_false(
    @debug.to_string(save(saved, command_doc("new"), _ => @cmd.none)).contains(
      "IndexedDBApply",
    ),
  )
}

///|
test "delete rejects unknown document" {
  let saved = SavedDocuments::from_documents([]).unwrap()
  let emitted : Array[DeleteResult] = []
  let command = delete(saved, test_document_id("missing"), result => {
    emitted.push(result)
    @cmd.none
  })
  assert_eq(emitted, [DeleteResult::DeleteFailed(DeleteFailure::InvalidSource)])
  assert_false(@debug.to_string(command).contains("IndexedDB"))
}

///|
test "delete and create commands use positional callbacks" {
  let saved = SavedDocuments::from_documents([command_doc("a")]).unwrap()
  assert_true(
    @debug.to_string(delete(saved, test_document_id("a"), _ => @cmd.none)).contains(
      "IndexedDBApply",
    ),
  )
  assert_false(
    @debug.to_string(create(saved, _ => @cmd.none)).contains("IndexedDB"),
  )
}

///|
test "sync start atomically publishes replica and retires local source" {
  let document = command_doc("a")
  let saved = SavedDocuments::from_documents([document]).unwrap()
  let command = persist_replica_write(
    saved,
    DocumentReplica(test_account(), document).promote_source(),
    _ => @cmd.none,
  )
  assert_true(@debug.to_string(command).contains("IndexedDBApply(2)"))
}

///|
test "replica failure reports only the storage error" {
  assert_eq(
    replica_result(Some(@indexed_db.WriteError::Unavailable)),
    Err(ReplicaFailure::StorageUnavailable),
  )
}

///|
test "pending operation is written inside its complete replica" {
  let replica = DocumentReplica(test_account(), command_doc("a"))
  let saved = SavedDocuments::from_documents([]).unwrap().apply_replica(replica)
  let pending = start_save(replica, TEST_OPERATION_1)
  assert_eq(replica_mutations(pending), [
    @indexed_db.Mutation::Set(
      replica_key(test_account(), test_document_id("a")),
      encode_replica(pending.replica()),
    ),
  ])
  let command = persist_replica_write(saved, pending, _ => @cmd.none)
  assert_true(@debug.to_string(command).contains("IndexedDBApply(1)"))
}

///|
test "conflict replica and recovery source share one transaction" {
  let replica = DocumentReplica(test_account(), command_doc("a"))
  let saved = SavedDocuments::from_documents([]).unwrap().apply_replica(replica)
  let sent = start_save(replica, TEST_OPERATION_1)
  let acknowledged = sent
    .replica()
    .acknowledge(test_operation(TEST_OPERATION_1), test_revision(1.0))
  let edited = edit_write(acknowledged.replica(), "local").replica()
  let conflicted = preserve_conflict(
    edited,
    remote_present(2.0, "remote"),
    "recovery",
  )
  guard conflicted is Fork(replica, recovery) else {
    fail("expected conflict recovery")
  }
  assert_eq(replica_mutations(conflicted), [
    @indexed_db.Mutation::Set(
      replica_key(test_account(), test_document_id("a")),
      encode_replica(replica),
    ),
    @indexed_db.Mutation::Set(
      source_key(test_document_id("recovery")),
      encode_document(recovery),
    ),
  ])
  let command = persist_replica_write(saved, conflicted, _ => @cmd.none)
  assert_true(@debug.to_string(command).contains("IndexedDBApply(2)"))
}
