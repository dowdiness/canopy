///|
fn replica_test_frame(header : String, payload : String) -> String {
  "loomark-replica\n" + header.length().to_string() + "\n" + header + payload
}

///|
fn test_replica_key(
  account? : String = "account-a",
  document? : String = "document",
) -> String {
  replica_key(test_account(value=account), test_document_id(document))
}

///|
test "codec retains parsed pending operation and newer text" {
  let replica = edit_write(sending_replica("sent", TEST_OPERATION_1), "newer").replica()
  let reopened = decode_replica(test_replica_key(), encode_replica(replica)).unwrap()
  assert_eq(reopened, replica)
  guard reopened.directive() is ReplicaDirective::Send(operation) else {
    fail("expected persisted operation")
  }
  assert_eq(operation.operation_id(), test_operation(TEST_OPERATION_1))
  assert_eq(operation.content(), PendingContent::Save("sent"))
  assert_eq(replica_document(reopened).text(), "newer")
}

///|
test "codec retains pending deletion for restart" {
  let saved = sending_replica("text", TEST_OPERATION_1)
    .acknowledge(test_operation(TEST_OPERATION_1), test_revision(1.0))
    .replica()
  let preparing = saved.request_deletion().replica()
  let reopened = decode_replica(test_replica_key(), encode_replica(preparing)).unwrap()
  assert_eq(reopened, preparing)
  guard reopened.directive() is ReplicaDirective::CreateOperation(draft) else {
    fail("expected delete draft")
  }
  let replica = draft.start(test_operation(TEST_OPERATION_2)).replica()
  let reopened = decode_replica(test_replica_key(), encode_replica(replica)).unwrap()
  assert_eq(reopened, replica)
  guard reopened.directive() is ReplicaDirective::Send(operation) else {
    fail("expected pending deletion")
  }
  assert_eq(operation.operation_id(), test_operation(TEST_OPERATION_2))
  assert_eq(operation.content(), PendingContent::Delete)
}

///|
test "tombstone frame retains only identity and revision" {
  let saved = DocumentReplica::receive(
    test_account(),
    Document::create(test_document_id("document"), "text"),
    test_revision(1.0),
  )
  guard saved.request_deletion().replica().directive()
    is ReplicaDirective::CreateOperation(draft) else {
    fail("delete draft")
  }
  let tombstone = draft
    .start(test_operation(TEST_OPERATION_2))
    .replica()
    .acknowledge(test_operation(TEST_OPERATION_2), test_revision(2.0))
    .replica()
  let encoded = encode_replica(tombstone)
  assert_false(encoded.has_suffix("text"))
  assert_eq(decode_replica(test_replica_key(), encoded), Some(tombstone))
}

///|
test "codec retains deletion while resolving a save" {
  let deleting = sending_replica("sent", TEST_OPERATION_1).edit("newer")
  guard deleting is EditPlan::Persist(edited) else { fail("edit") }
  let deleting = edited.replica().request_deletion().replica()
  let reopened = decode_replica(test_replica_key(), encode_replica(deleting)).unwrap()
  assert_eq(reopened, deleting)
  guard reopened.directive() is ReplicaDirective::Send(operation) else {
    fail("saved operation")
  }
  assert_eq(operation.operation_id(), test_operation(TEST_OPERATION_1))
  assert_eq(operation.content(), PendingContent::Save("sent"))
}

///|
test "frame preserves raw text without JSON escaping" {
  let text = "line 1\n\"quoted\"\\slash\u{0000}日本語🌳"
  let replica = initial_replica(text)
  let encoded = encode_replica(replica)
  assert_true(encoded.has_suffix(text))
  assert_eq(decode_replica(test_replica_key(), encoded), Some(replica))
}

///|
test "frame stores one copy of shared large text" {
  let text = String::make(1024 * 1024, 'x')
  let replica = sending_replica(text, TEST_OPERATION_1)
    .acknowledge(test_operation(TEST_OPERATION_1), test_revision(1.0))
    .replica()
  let encoded = encode_replica(replica)
  assert_true(encoded.length() < text.length() + 1024)
  assert_eq(decode_replica(test_replica_key(), encoded), Some(replica))
}

///|
test "codec retains recovery relation independently of sync phase" {
  let edited = sending_replica("base", TEST_OPERATION_1)
    .acknowledge(test_operation(TEST_OPERATION_1), test_revision(1.0))
    .replica()
  let edited = edit_write(edited, "local").replica()
  let replica = preserve_conflict(
    edited,
    remote_present(2.0, "remote"),
    "recovery",
  ).replica()
  assert_eq(
    decode_replica(test_replica_key(), encode_replica(replica)),
    Some(replica),
  )
  assert_true(
    replica.state is ReplicaState::Live({ phase: LivePhase::Ready, .. }),
  )
  assert_eq(replica.recovery_document_id(), Some(test_document_id("recovery")))
}

///|
test "codec retains available and diverged observations" {
  let synchronized = sending_replica("base", TEST_OPERATION_1)
    .acknowledge(test_operation(TEST_OPERATION_1), test_revision(1.0))
    .replica()
  let available = reconcile_change(synchronized, remote_present(2.0, "remote")).replica()
  let diverged = edit_write(available, "local").replica()
  for replica in [available, diverged] {
    assert_eq(
      decode_replica(test_replica_key(), encode_replica(replica)),
      Some(replica),
    )
  }
  assert_true(
    available.state
    is ReplicaState::Live({ phase: LivePhase::Available(_), .. }),
  )
  assert_true(
    diverged.state is ReplicaState::Live({ phase: LivePhase::Diverged(_), .. }),
  )
}

///|
test "replica key binds parsed account and document identity" {
  let replica = initial_replica("text")
  let encoded = encode_replica(replica)
  assert_eq(
    decode_replica(test_replica_key(account="account-b"), encoded),
    None,
  )
  assert_eq(decode_replica(test_replica_key(document="other"), encoded), None)
}

///|
test "codec parser rejects malformed fields, revisions, and impossible phases" {
  let valid = encode_replica(initial_replica("text"))
  let document_id = test_document_id("document").value()
  let prefix = "{\"account_id\":\"account-a\",\"document_id\":\"" +
    document_id +
    "\","
  let extra = prefix +
    "\"generation\":0,\"state\":{\"kind\":\"live\",\"current\":0,\"baseline\":{\"kind\":\"missing\"},\"phase\":{\"kind\":\"ready\"}},\"recovery_document_id\":null,\"text_lengths\":[1],\"extra\":true}"
  let invalid_revision = prefix +
    "\"generation\":0,\"state\":{\"kind\":\"tombstone\",\"revision\":0},\"recovery_document_id\":null,\"text_lengths\":[]}"
  let impossible_sending = prefix +
    "\"generation\":1,\"state\":{\"kind\":\"live\",\"current\":0,\"baseline\":{\"kind\":\"missing\"},\"phase\":{\"kind\":\"sending\",\"operation\":{\"kind\":\"save\",\"operation_id\":\"a0000000-0000-4000-8000-000000000001\",\"base_revision\":1,\"text\":0}}},\"recovery_document_id\":null,\"text_lengths\":[1]}"
  let deletion_resolving_delete = prefix +
    "\"generation\":1,\"state\":{\"kind\":\"deleting\",\"current\":0,\"baseline\":{\"kind\":\"missing\"},\"phase\":{\"kind\":\"resolving_save\",\"operation\":{\"kind\":\"delete\",\"operation_id\":\"a0000000-0000-4000-8000-000000000001\",\"base_revision\":0}}},\"recovery_document_id\":null,\"text_lengths\":[1]}"
  let deletion_sending_save = prefix +
    "\"generation\":1,\"state\":{\"kind\":\"deleting\",\"current\":0,\"baseline\":{\"kind\":\"present\",\"revision\":1,\"text\":0},\"phase\":{\"kind\":\"sending\",\"operation\":{\"kind\":\"save\",\"operation_id\":\"a0000000-0000-4000-8000-000000000001\",\"base_revision\":1,\"text\":0}}},\"recovery_document_id\":null,\"text_lengths\":[1]}"
  let deleted_preparing = prefix +
    "\"generation\":1,\"state\":{\"kind\":\"deleting\",\"current\":0,\"baseline\":{\"kind\":\"missing\"},\"phase\":{\"kind\":\"ready\"}},\"recovery_document_id\":null,\"text_lengths\":[1]}"
  let malformed = [
    "{}",
    "loomark-replica\n",
    "loomark-replica\n01\n{}",
    "loomark-replica\n2\n{}",
    "loomark-replica\n999999999999999999999999999999\n{}",
    valid + "x",
    valid[:valid.length() - 1].to_owned(),
    replica_test_frame(extra, "x"),
    replica_test_frame(invalid_revision, "x"),
    replica_test_frame(impossible_sending, "x"),
    replica_test_frame(deletion_resolving_delete, "x"),
    replica_test_frame(deletion_sending_save, "x"),
    replica_test_frame(deleted_preparing, "x"),
  ]
  for encoded in malformed {
    assert_eq(decode_replica(test_replica_key(), encoded), None)
  }
}
