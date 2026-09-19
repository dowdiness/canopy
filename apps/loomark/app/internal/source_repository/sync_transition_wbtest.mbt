///|
const TEST_OPERATION_1 : String = "a0000000-0000-4000-8000-000000000001"

///|
const TEST_OPERATION_2 : String = "a0000000-0000-4000-8000-000000000002"

///|
fn test_account(value? : String = "account-a") -> AccountId {
  AccountId::parse(value) catch {
    _ => abort("invalid test account")
  }
}

///|
fn test_operation(value : String) -> OperationId {
  OperationId::parse(value) catch {
    _ => abort("invalid test operation")
  }
}

///|
fn test_revision(value : Double) -> SavedRevision {
  SavedRevision::parse(value) catch {
    _ => abort("invalid test revision")
  }
}

///|
fn remote_present(revision : Double, text : String) -> RemoteDocument {
  RemoteDocument::Present(test_revision(revision), text)
}

///|
fn sync_doc(text : String) -> Document {
  Document::create("document", text) catch {
    _ => abort("invalid document")
  }
}

///|
fn enrolled(text : String) -> SyncCheckpoint {
  SyncCheckpoint::enroll(test_account(), sync_doc(text))
}

///|
fn start_save(
  checkpoint : SyncCheckpoint,
  operation_id : String,
) -> CheckpointWrite {
  guard checkpoint.plan_save() is OperationPlan::Start(draft) else {
    abort("expected operation draft")
  }
  draft.start(test_operation(operation_id))
}

///|
fn sending_checkpoint(text : String, operation_id : String) -> SyncCheckpoint {
  start_save(enrolled(text), operation_id).checkpoint()
}

///|
fn reconcile_change(
  checkpoint : SyncCheckpoint,
  remote : RemoteDocument,
) -> CheckpointWrite {
  guard checkpoint.reconcile(remote) is ReconcilePlan::Persist(write) else {
    abort("expected reconciliation write")
  }
  write
}

///|
fn preserve_conflict(
  checkpoint : SyncCheckpoint,
  remote : RemoteDocument,
  recovery_id : String,
) -> CheckpointWrite {
  guard checkpoint.reconcile(remote) is ReconcilePlan::ConflictDetected(draft) else {
    abort("expected conflict")
  }
  draft.preserve(recovery_id) catch {
    _ => abort("invalid test recovery identity")
  }
}

///|
test "restart resends the exact parsed durable pending operation" {
  let checkpoint = sending_checkpoint("first", TEST_OPERATION_1)
  guard checkpoint.directive() is SyncDirective::Send(operation) else {
    fail("expected pending operation")
  }
  assert_eq(operation.operation_id(), test_operation(TEST_OPERATION_1))
  assert_eq(operation.base_revision(), 0.0)
  assert_eq(operation.content(), PendingContent::Save("first"))
}

///|
test "acknowledgment retains an edit made during sending" {
  let sending = sending_checkpoint("first", TEST_OPERATION_1)
  let edited = sending.edit("newer").unwrap().checkpoint()
  let completed = edited
    .acknowledge(test_operation(TEST_OPERATION_1), test_revision(1.0))
    .checkpoint()
  assert_eq(completed.directive(), SyncDirective::SaveRequired)
  assert_eq(completed.document().text(), "newer")
  assert_eq(completed.baseline, remote_present(1.0, "first"))
  assert_eq(completed.phase, SyncPhase::Ready)
}

///|
test "a stale receipt is an explicit error" {
  let checkpoint = sending_checkpoint("first", TEST_OPERATION_1)
  let result : Result[CheckpointWrite, ReceiptMismatch] = Ok(
    checkpoint.acknowledge(test_operation(TEST_OPERATION_2), test_revision(1.0)),
  ) catch {
    error => Err(error)
  }
  assert_eq(result, Err(ReceiptMismatch::OperationMismatch))
}

///|
test "pending delivery wins over a competing remote revision" {
  let checkpoint = sending_checkpoint("local", TEST_OPERATION_1)
  assert_eq(
    checkpoint.reconcile(remote_present(1.0, "remote")),
    ReconcilePlan::Unchanged,
  )
  guard checkpoint.directive() is SyncDirective::Send(operation) else {
    fail("expected original pending operation")
  }
  assert_eq(operation.operation_id(), test_operation(TEST_OPERATION_1))
}

///|
test "definitive save rejection retires pending operation into conflict" {
  let saved = sending_checkpoint("base", TEST_OPERATION_1)
    .acknowledge(test_operation(TEST_OPERATION_1), test_revision(1.0))
    .checkpoint()
  let edited = saved.edit("local").unwrap().checkpoint()
  let pending = start_save(edited, TEST_OPERATION_2).checkpoint()
  guard pending.reject_conflict(
      test_operation(TEST_OPERATION_2),
      remote_present(2.0, "remote"),
    )
    is ReconcilePlan::ConflictDetected(draft) else {
    fail("expected conflict draft")
  }
  let conflicted = draft.preserve("rejected-save-recovery")
  assert_true(conflicted is CheckpointAndRecovery(_, _))
  assert_eq(
    conflicted.checkpoint().directive(),
    SyncDirective::Conflict(
      "rejected-save-recovery",
      remote_present(2.0, "remote"),
    ),
  )
}

///|
test "definitive delete rejection requires a new informed decision" {
  let saved = sending_checkpoint("base", TEST_OPERATION_1)
    .acknowledge(test_operation(TEST_OPERATION_1), test_revision(1.0))
    .checkpoint()
  guard saved.plan_delete() is OperationPlan::Start(draft) else {
    fail("expected delete draft")
  }
  let pending = draft.start(test_operation(TEST_OPERATION_2)).checkpoint()
  guard pending.reject_conflict(
      test_operation(TEST_OPERATION_2),
      remote_present(2.0, "remote"),
    )
    is ReconcilePlan::Persist(write) else {
    fail("expected remote update")
  }
  let rejected = write.checkpoint()
  assert_eq(
    rejected.directive(),
    SyncDirective::UpdateAvailable(remote_present(2.0, "remote")),
  )
  assert_eq(rejected.plan_delete(), OperationPlan::Current)
}

///|
test "equal remote text advances baseline once" {
  let checkpoint = reconcile_change(
    enrolled("same"),
    remote_present(3.0, "same"),
  ).checkpoint()
  assert_eq(checkpoint.directive(), SyncDirective::Synchronized)
  assert_eq(checkpoint.baseline, remote_present(3.0, "same"))
  assert_eq(
    checkpoint.reconcile(remote_present(3.0, "same")),
    ReconcilePlan::Unchanged,
  )
}

///|
test "delayed remote revisions cannot replace a newer available update" {
  let saved = sending_checkpoint("base", TEST_OPERATION_1)
    .acknowledge(test_operation(TEST_OPERATION_1), test_revision(1.0))
    .checkpoint()
  let available = reconcile_change(saved, remote_present(3.0, "newest")).checkpoint()
  for
    delayed in [
      remote_present(2.0, "base"),
      remote_present(2.0, "older-different"),
    ] {
    assert_eq(available.reconcile(delayed), ReconcilePlan::Unchanged)
    assert_eq(
      available.directive(),
      SyncDirective::UpdateAvailable(remote_present(3.0, "newest")),
    )
  }
}

///|
test "divergence produces one atomic conflict write" {
  let checkpoint = sending_checkpoint("base", TEST_OPERATION_1)
    .acknowledge(test_operation(TEST_OPERATION_1), test_revision(1.0))
    .checkpoint()
    .edit("local")
    .unwrap()
    .checkpoint()
  let conflicted = preserve_conflict(
    checkpoint,
    remote_present(2.0, "remote"),
    "recovery",
  )
  guard conflicted is CheckpointAndRecovery(checkpoint, recovery) else {
    fail("expected atomic conflict write")
  }
  assert_eq(recovery.text(), "local")
  assert_eq(
    checkpoint.directive(),
    SyncDirective::Conflict("recovery", remote_present(2.0, "remote")),
  )
}

///|
test "editing after a remote-update notice becomes a conflict" {
  let checkpoint = sending_checkpoint("base", TEST_OPERATION_1)
    .acknowledge(test_operation(TEST_OPERATION_1), test_revision(1.0))
    .checkpoint()
  let available = reconcile_change(checkpoint, remote_present(2.0, "remote")).checkpoint()
  assert_eq(
    available.directive(),
    SyncDirective::UpdateAvailable(remote_present(2.0, "remote")),
  )
  let edited = available.edit("local after notice").unwrap().checkpoint()
  assert_true(
    preserve_conflict(
      edited,
      remote_present(2.0, "remote"),
      "recovery-after-notice",
    )
    is CheckpointAndRecovery(_, _),
  )
}

///|
test "acknowledged deletion remains a tombstone" {
  let saved = sending_checkpoint("text", TEST_OPERATION_1)
    .acknowledge(test_operation(TEST_OPERATION_1), test_revision(1.0))
    .checkpoint()
  guard saved.plan_delete() is OperationPlan::Start(delete_draft) else {
    fail("expected delete draft")
  }
  let deleted = delete_draft
    .start(test_operation(TEST_OPERATION_2))
    .checkpoint()
    .acknowledge(test_operation(TEST_OPERATION_2), test_revision(2.0))
    .checkpoint()
  assert_eq(deleted.directive(), SyncDirective::Synchronized)
  assert_eq(deleted.plan_save(), OperationPlan::Current)
}

///|
test "ingress rejects malformed identifiers and revisions" {
  assert_true(
    try {
      AccountId::parse("") |> ignore
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      OperationId::parse("not-a-uuid") |> ignore
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      SavedRevision::parse(0.0) |> ignore
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      SavedRevision::parse(1.5) |> ignore
      false
    } catch {
      _ => true
    },
  )
}
