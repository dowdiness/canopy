///|
fn checkpoint_test_frame(header : String, payload : String) -> String {
  "loomark-sync\n" + header.length().to_string() + "\n" + header + payload
}

///|
fn checkpoint_key(
  account? : String = "account-a",
  document? : String = "document",
) -> String {
  sync_key(test_account(value=account), test_document_id(document))
}

///|
test "codec retains parsed pending operation and newer text" {
  let checkpoint = sending_checkpoint("sent", TEST_OPERATION_1)
    .edit("newer")
    .unwrap()
    .checkpoint()
  let reopened = decode_checkpoint(
    checkpoint_key(),
    encode_checkpoint(checkpoint),
  ).unwrap()
  assert_eq(reopened, checkpoint)
  guard reopened.directive() is SyncDirective::Send(operation) else {
    fail("expected persisted operation")
  }
  assert_eq(operation.operation_id(), test_operation(TEST_OPERATION_1))
  assert_eq(operation.content(), PendingContent::Save("sent"))
  assert_eq(reopened.document().text(), "newer")
}

///|
test "codec retains pending deletion for restart" {
  let saved = sending_checkpoint("text", TEST_OPERATION_1)
    .acknowledge(test_operation(TEST_OPERATION_1), test_revision(1.0))
    .checkpoint()
  guard saved.plan_delete() is OperationPlan::Start(draft) else {
    fail("expected delete draft")
  }
  let checkpoint = draft.start(test_operation(TEST_OPERATION_2)).checkpoint()
  let reopened = decode_checkpoint(
    checkpoint_key(),
    encode_checkpoint(checkpoint),
  ).unwrap()
  assert_eq(reopened, checkpoint)
  guard reopened.directive() is SyncDirective::Send(operation) else {
    fail("expected pending deletion")
  }
  assert_eq(operation.operation_id(), test_operation(TEST_OPERATION_2))
  assert_eq(operation.content(), PendingContent::Delete)
}

///|
test "frame preserves raw text without JSON escaping" {
  let text = "line 1\n\"quoted\"\\slash\u{0000}日本語🌳"
  let checkpoint = enrolled(text)
  let encoded = encode_checkpoint(checkpoint)
  assert_true(encoded.has_suffix(text))
  assert_eq(decode_checkpoint(checkpoint_key(), encoded), Some(checkpoint))
}

///|
test "frame stores one copy of shared large text" {
  let text = String::make(1024 * 1024, 'x')
  let checkpoint = sending_checkpoint(text, TEST_OPERATION_1)
    .acknowledge(test_operation(TEST_OPERATION_1), test_revision(1.0))
    .checkpoint()
  let encoded = encode_checkpoint(checkpoint)
  assert_true(encoded.length() < text.length() + 1024)
  assert_eq(decode_checkpoint(checkpoint_key(), encoded), Some(checkpoint))
}

///|
test "codec retains exclusive conflict phase" {
  let edited = sending_checkpoint("base", TEST_OPERATION_1)
    .acknowledge(test_operation(TEST_OPERATION_1), test_revision(1.0))
    .checkpoint()
    .edit("local")
    .unwrap()
    .checkpoint()
  let checkpoint = preserve_conflict(
    edited,
    remote_present(2.0, "remote"),
    "recovery",
  ).checkpoint()
  assert_eq(
    decode_checkpoint(checkpoint_key(), encode_checkpoint(checkpoint)),
    Some(checkpoint),
  )
  assert_true(checkpoint.phase is SyncPhase::Conflict(_))
  assert_eq(
    checkpoint.directive(),
    SyncDirective::Conflict("recovery", remote_present(2.0, "remote")),
  )
}

///|
test "checkpoint key binds parsed account and document identity" {
  let checkpoint = enrolled("text")
  let encoded = encode_checkpoint(checkpoint)
  assert_eq(
    decode_checkpoint(checkpoint_key(account="account-b"), encoded),
    None,
  )
  assert_eq(decode_checkpoint(checkpoint_key(document="other"), encoded), None)
}

///|
test "codec parser rejects malformed fields, revisions, and impossible phases" {
  let valid = encode_checkpoint(enrolled("text"))
  let extra =
    #|{"account_id":"account-a","document_id":"document","generation":0,"current":0,"baseline":{"kind":"missing"},"phase":{"kind":"ready"},"text_lengths":[1],"extra":true}
  let invalid_revision =
    #|{"account_id":"account-a","document_id":"document","generation":0,"current":0,"baseline":{"kind":"present","revision":0,"text":0},"phase":{"kind":"ready"},"text_lengths":[1]}
  let impossible_sending =
    #|{"account_id":"account-a","document_id":"document","generation":1,"current":0,"baseline":{"kind":"missing"},"phase":{"kind":"sending","operation":{"kind":"save","operation_id":"a0000000-0000-4000-8000-000000000001","base_revision":1,"text":0}},"text_lengths":[1]}
  let malformed = [
    "{}",
    "loomark-sync\n",
    "loomark-sync\n01\n{}",
    "loomark-sync\n2\n{}",
    "loomark-sync\n999999999999999999999999999999\n{}",
    valid + "x",
    valid[:valid.length() - 1].to_owned(),
    checkpoint_test_frame(extra, "x"),
    checkpoint_test_frame(invalid_revision, "x"),
    checkpoint_test_frame(impossible_sending, "x"),
  ]
  for encoded in malformed {
    assert_eq(decode_checkpoint(checkpoint_key(), encoded), None)
  }
}
