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
fn test_document_id(value : String) -> DocumentId {
  let mut hash = 0
  for byte in value {
    hash = (hash * 131 + byte.to_int()) % 65521
  }
  let hex = hash.to_string(radix=16)
  let id = "a0000000-0000-4000-8000-" +
    String::make(12 - hex.length(), '0') +
    hex
  DocumentId::parse(id) catch {
    _ => abort("invalid test document identity")
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
  Document::create(test_document_id("document"), text)
}

///|
fn initial_replica(text : String) -> DocumentReplica {
  DocumentReplica(test_account(), sync_doc(text))
}

///|
fn start_save(replica : DocumentReplica, operation_id : String) -> ReplicaWrite {
  guard replica.plan_save() is OperationPlan::Start(draft) else {
    abort("expected operation draft")
  }
  draft.start(test_operation(operation_id))
}

///|
fn sending_replica(text : String, operation_id : String) -> DocumentReplica {
  start_save(initial_replica(text), operation_id).replica()
}

///|
fn edit_write(replica : DocumentReplica, text : String) -> ReplicaWrite {
  guard replica.edit(text) is EditPlan::Persist(write) else {
    abort("expected edit write")
  }
  write
}

///|
fn reconcile_change(
  replica : DocumentReplica,
  remote : RemoteDocument,
) -> ReplicaWrite {
  guard replica.reconcile(remote) is ReconcilePlan::Persist(write) else {
    abort("expected reconciliation write")
  }
  write
}

///|
fn preserve_conflict(
  replica : DocumentReplica,
  remote : RemoteDocument,
  recovery_id : String,
) -> ReplicaWrite {
  guard replica.reconcile(remote) is ReconcilePlan::Persist(diverged) else {
    abort("expected divergence")
  }
  diverged.replica().fork(test_document_id(recovery_id)) catch {
    _ => abort("invalid test recovery identity")
  }
}

///|
test "restart resends the exact parsed durable pending operation" {
  let replica = sending_replica("first", TEST_OPERATION_1)
  guard replica.directive() is ReplicaDirective::Send(operation) else {
    fail("expected pending operation")
  }
  assert_eq(operation.operation_id(), test_operation(TEST_OPERATION_1))
  assert_eq(operation.base_revision(), 0.0)
  assert_eq(operation.content(), PendingContent::Save("first"))
}

///|
test "acknowledgment retains an edit made during sending" {
  let sending = sending_replica("first", TEST_OPERATION_1)
  let edited = edit_write(sending, "newer").replica()
  let completed = edited
    .acknowledge(test_operation(TEST_OPERATION_1), test_revision(1.0))
    .replica()
  assert_eq(completed.directive(), ReplicaDirective::SaveRequired)
  assert_eq(completed.document().text(), "newer")
  assert_eq(completed.baseline, remote_present(1.0, "first"))
  assert_eq(completed.phase, ReplicaPhase::Ready)
}

///|
test "a stale receipt is an explicit error" {
  let replica = sending_replica("first", TEST_OPERATION_1)
  let result : Result[ReplicaWrite, ReceiptMismatch] = Ok(
    replica.acknowledge(test_operation(TEST_OPERATION_2), test_revision(1.0)),
  ) catch {
    error => Err(error)
  }
  assert_eq(result, Err(ReceiptMismatch::OperationMismatch))
}

///|
test "definitive non-application retires only the matching operation" {
  let replica = sending_replica("first", TEST_OPERATION_1)
  let rejected = replica
    .reject_operation(test_operation(TEST_OPERATION_1))
    .replica()
  assert_eq(rejected.directive(), ReplicaDirective::SaveRequired)
  let mismatch : Result[ReplicaWrite, ReceiptMismatch] = Ok(
    replica.reject_operation(test_operation(TEST_OPERATION_2)),
  ) catch {
    error => Err(error)
  }
  assert_eq(mismatch, Err(ReceiptMismatch::OperationMismatch))
}

///|
test "pending delivery wins over a competing remote revision" {
  let replica = sending_replica("local", TEST_OPERATION_1)
  assert_eq(
    replica.reconcile(remote_present(1.0, "remote")),
    ReconcilePlan::Unchanged,
  )
  guard replica.directive() is ReplicaDirective::Send(operation) else {
    fail("expected original pending operation")
  }
  assert_eq(operation.operation_id(), test_operation(TEST_OPERATION_1))
}

///|
test "definitive save rejection retires pending operation into conflict" {
  let saved = sending_replica("base", TEST_OPERATION_1)
    .acknowledge(test_operation(TEST_OPERATION_1), test_revision(1.0))
    .replica()
  let edited = edit_write(saved, "local").replica()
  let pending = start_save(edited, TEST_OPERATION_2).replica()
  guard pending.reject_conflict(
      test_operation(TEST_OPERATION_2),
      remote_present(2.0, "remote"),
    )
    is ReconcilePlan::Persist(diverged) else {
    fail("expected durable divergence")
  }
  assert_eq(diverged.replica().directive(), ReplicaDirective::RecoveryRequired)
  let conflicted = diverged
    .replica()
    .fork(test_document_id("rejected-save-recovery")) catch {
      _ => abort("recovery identity")
    }
  assert_true(conflicted is Fork(_, _))
  assert_eq(conflicted.replica().directive(), ReplicaDirective::Synchronized)
  assert_eq(
    conflicted.replica().recovery_document_id(),
    Some(test_document_id("rejected-save-recovery")),
  )
}

///|
test "definitive delete rejection requires a new informed decision" {
  let saved = sending_replica("base", TEST_OPERATION_1)
    .acknowledge(test_operation(TEST_OPERATION_1), test_revision(1.0))
    .replica()
  guard saved.plan_delete() is OperationPlan::Start(draft) else {
    fail("expected delete draft")
  }
  let pending = draft.start(test_operation(TEST_OPERATION_2)).replica()
  guard pending.reject_conflict(
      test_operation(TEST_OPERATION_2),
      remote_present(2.0, "remote"),
    )
    is ReconcilePlan::Persist(write) else {
    fail("expected remote update")
  }
  let rejected = write.replica()
  assert_eq(
    rejected.directive(),
    ReplicaDirective::UpdateAvailable(remote_present(2.0, "remote")),
  )
  assert_eq(rejected.plan_delete(), OperationPlan::Current)
}

///|
test "equal remote text advances baseline once" {
  let replica = reconcile_change(
    initial_replica("same"),
    remote_present(3.0, "same"),
  ).replica()
  assert_eq(replica.directive(), ReplicaDirective::Synchronized)
  assert_eq(replica.baseline, remote_present(3.0, "same"))
  assert_eq(
    replica.reconcile(remote_present(3.0, "same")),
    ReconcilePlan::Unchanged,
  )
}

///|
test "delayed remote revisions cannot replace a newer available update" {
  let saved = sending_replica("base", TEST_OPERATION_1)
    .acknowledge(test_operation(TEST_OPERATION_1), test_revision(1.0))
    .replica()
  let available = reconcile_change(saved, remote_present(3.0, "newest")).replica()
  for
    delayed in [
      remote_present(2.0, "base"),
      remote_present(2.0, "older-different"),
    ] {
    assert_eq(available.reconcile(delayed), ReconcilePlan::Unchanged)
    assert_eq(
      available.directive(),
      ReplicaDirective::UpdateAvailable(remote_present(3.0, "newest")),
    )
  }
}

///|
test "a newer remote revision can converge an available update to local text" {
  let saved = sending_replica("base", TEST_OPERATION_1)
    .acknowledge(test_operation(TEST_OPERATION_1), test_revision(1.0))
    .replica()
  let available = reconcile_change(saved, remote_present(2.0, "remote")).replica()
  let converged = reconcile_change(available, remote_present(3.0, "base")).replica()
  assert_eq(converged.directive(), ReplicaDirective::Synchronized)
  assert_eq(converged.baseline_revision(), 3.0)
  assert_eq(converged.document().text(), "base")
}

///|
test "a newer tombstone replaces an available update" {
  let saved = sending_replica("base", TEST_OPERATION_1)
    .acknowledge(test_operation(TEST_OPERATION_1), test_revision(1.0))
    .replica()
  let available = reconcile_change(saved, remote_present(2.0, "remote")).replica()
  let tombstone = RemoteDocument::Deleted(test_revision(3.0))
  let deleted = reconcile_change(available, tombstone).replica()
  assert_eq(deleted.directive(), ReplicaDirective::UpdateAvailable(tombstone))
  assert_eq(deleted.observed_revision(), 3.0)
  assert_eq(deleted.document().text(), "base")
}

///|
test "opening an available Replica accepts its retained remote revision" {
  let saved = sending_replica("base", TEST_OPERATION_1)
    .acknowledge(test_operation(TEST_OPERATION_1), test_revision(1.0))
    .replica()
  let retained = remote_present(2.0, "remote")
  let available = reconcile_change(saved, retained).replica()
  guard available.open(retained) is OpenOutcome::PersistAndOpen(write) else {
    fail("available open")
  }
  assert_eq(write.replica().document().text(), "remote")
  assert_eq(write.replica().baseline_revision(), 2.0)
  assert_eq(write.replica().directive(), ReplicaDirective::Synchronized)
}

///|
test "opening an available Replica never regresses a retained revision" {
  let saved = sending_replica("base", TEST_OPERATION_1)
    .acknowledge(test_operation(TEST_OPERATION_1), test_revision(1.0))
    .replica()
  let available = reconcile_change(saved, remote_present(3.0, "newest")).replica()
  guard available.open(remote_present(2.0, "delayed"))
    is OpenOutcome::PersistAndOpen(write) else {
    fail("newest retained open")
  }
  assert_eq(write.replica().document().text(), "newest")
  assert_eq(write.replica().baseline_revision(), 3.0)
}

///|
test "opening a tombstoned available Replica is unavailable" {
  let saved = sending_replica("base", TEST_OPERATION_1)
    .acknowledge(test_operation(TEST_OPERATION_1), test_revision(1.0))
    .replica()
  let tombstone = RemoteDocument::Deleted(test_revision(2.0))
  let available = reconcile_change(saved, tombstone).replica()
  assert_eq(available.open(tombstone), OpenOutcome::Unavailable)
}

///|
test "opening a newer tombstone persists it without opening" {
  let saved = sending_replica("base", TEST_OPERATION_1)
    .acknowledge(test_operation(TEST_OPERATION_1), test_revision(1.0))
    .replica()
  let tombstone = RemoteDocument::Deleted(test_revision(2.0))
  guard saved.open(tombstone) is OpenOutcome::PersistOnly(write) else {
    fail("tombstone persistence")
  }
  assert_eq(
    write.replica().directive(),
    ReplicaDirective::UpdateAvailable(tombstone),
  )
  assert_eq(write.replica().document().text(), "base")
}

///|
test "divergence produces one atomic conflict write" {
  let replica = sending_replica("base", TEST_OPERATION_1)
    .acknowledge(test_operation(TEST_OPERATION_1), test_revision(1.0))
    .replica()
  let replica = edit_write(replica, "local").replica()
  let conflicted = preserve_conflict(
    replica,
    remote_present(2.0, "remote"),
    "recovery",
  )
  guard conflicted is Fork(replica, recovery) else {
    fail("expected atomic conflict write")
  }
  assert_eq(recovery.text(), "local")
  assert_eq(replica.directive(), ReplicaDirective::Synchronized)
  assert_eq(replica.recovery_document_id(), Some(test_document_id("recovery")))
}

///|
test "editing after a remote-update notice persists divergence before recovery" {
  let replica = sending_replica("base", TEST_OPERATION_1)
    .acknowledge(test_operation(TEST_OPERATION_1), test_revision(1.0))
    .replica()
  let available = reconcile_change(replica, remote_present(2.0, "remote")).replica()
  assert_eq(
    available.directive(),
    ReplicaDirective::UpdateAvailable(remote_present(2.0, "remote")),
  )
  guard available.edit("local after notice") is EditPlan::Persist(diverged) else {
    fail("expected durable divergence")
  }
  assert_eq(diverged.replica().directive(), ReplicaDirective::RecoveryRequired)
  assert_true(
    diverged.replica().fork(test_document_id("recovery-after-notice"))
    is Fork(_, _),
  )
}

///|
test "acknowledged deletion remains a tombstone" {
  let saved = sending_replica("text", TEST_OPERATION_1)
    .acknowledge(test_operation(TEST_OPERATION_1), test_revision(1.0))
    .replica()
  guard saved.plan_delete() is OperationPlan::Start(delete_draft) else {
    fail("expected delete draft")
  }
  let deleted = delete_draft
    .start(test_operation(TEST_OPERATION_2))
    .replica()
    .acknowledge(test_operation(TEST_OPERATION_2), test_revision(2.0))
    .replica()
  assert_eq(deleted.directive(), ReplicaDirective::Synchronized)
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
