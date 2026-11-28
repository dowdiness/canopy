///|
const TEST_OPERATION_1 : String = "a0000000-0000-4000-8000-000000000001"

///|
const TEST_OPERATION_2 : String = "a0000000-0000-4000-8000-000000000002"

///|
fn test_account(value~ : String = "account-a") -> AccountId {
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
fn replica_document(replica : DocumentReplica) -> Document {
  match replica.document() {
    Some(document) => document
    None => abort("expected a live working document")
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
  RemoteDocument::Present(
    test_revision(revision),
    Content(text, ChangeTime(0.0)),
  )
}

///|
fn sync_doc(text : String) -> Document {
  Document::create(test_document_id("document"), text, ChangeTime(0.0))
}

///|
fn initial_replica(text : String) -> DocumentReplica {
  DocumentReplica(test_account(), sync_doc(text))
}

///|
fn start_save(replica : DocumentReplica, operation_id : String) -> ReplicaWrite {
  guard replica.directive() is ReplicaDirective::CreateOperation(draft) &&
    draft.content() is PendingContent::Save(_) else {
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
  guard test_edit(replica, text) is EditPlan::Persist(write) else {
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
test "relation includes visible text that has not entered a Replica write" {
  let replica = DocumentReplica::receive(
    test_account(),
    sync_doc("base"),
    test_revision(1.0),
  )
  let live = replica.live().unwrap()
  assert_eq(
    live.relation(sync_doc("base"), replica.remote_knowledge(None)),
    Relation::Current,
  )
  assert_eq(
    live.relation(sync_doc("typing"), replica.remote_knowledge(None)),
    Relation::LocalAhead,
  )
  assert_eq(
    live.relation(
      sync_doc("typing"),
      replica.remote_knowledge(Some(RemoteHead::Present(test_revision(2.0)))),
    ),
    Relation::Concurrent,
  )
}

///|
test "relation distinguishes a known remote update from local durability" {
  let replica = DocumentReplica::receive(
    test_account(),
    sync_doc("base"),
    test_revision(1.0),
  )
  let live = replica.live().unwrap()
  assert_eq(
    live.relation(
      sync_doc("base"),
      replica.remote_knowledge(Some(RemoteHead::Present(test_revision(2.0)))),
    ),
    Relation::RemoteAhead,
  )
  assert_eq(
    live.relation(
      sync_doc("base"),
      replica.remote_knowledge(Some(RemoteHead::Deleted(test_revision(2.0)))),
    ),
    Relation::DeletedRemotely,
  )
}

///|
test "newer catalog deletion supersedes an available stored update" {
  let replica = DocumentReplica::receive(
    test_account(),
    sync_doc("base"),
    test_revision(1.0),
  )
  guard replica.reconcile(remote_present(2.0, "remote"))
    is ReconcilePlan::Persist(write) else {
    fail("remote update")
  }
  let available = write.replica()
  let live = available.live().unwrap()
  assert_eq(
    live.relation(
      sync_doc("base"),
      available.remote_knowledge(Some(RemoteHead::Deleted(test_revision(3.0)))),
    ),
    Relation::DeletedRemotely,
  )
}

///|
test "restart resends the exact parsed durable pending operation" {
  let replica = sending_replica("first", TEST_OPERATION_1)
  guard replica.directive() is ReplicaDirective::Send(operation) else {
    fail("expected pending operation")
  }
  assert_eq(operation.operation_id(), test_operation(TEST_OPERATION_1))
  assert_eq(operation.base_revision(), 0.0)
  assert_eq(
    operation.content(),
    PendingContent::Save(Content("first", ChangeTime(0.0))),
  )
}

///|
test "acknowledgment retains an edit made during sending" {
  let sending = sending_replica("first", TEST_OPERATION_1)
  let edited = edit_write(sending, "newer").replica()
  let completed = edited
    .acknowledge(test_operation(TEST_OPERATION_1), test_revision(1.0))
    .replica()
  assert_true(
    completed.directive() is ReplicaDirective::CreateOperation(draft) &&
    draft.content() == PendingContent::Save(Content("newer", ChangeTime(1.0))),
  )
  assert_eq(replica_document(completed).text(), "newer")
  assert_true(
    completed.state
    is ReplicaState::Live(
      {
        baseline: LiveBaseline::Saved(_, baseline),
        phase: LivePhase::Ready,
        ..
      },
    ) &&
    baseline.text() == "first",
  )
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
  assert_true(
    rejected.directive() is ReplicaDirective::CreateOperation(draft) &&
    draft.content() == PendingContent::Save(Content("first", ChangeTime(0.0))),
  )
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
test "a new delete decision after conflict uses the observed revision" {
  let saved = sending_replica("base", TEST_OPERATION_1)
    .acknowledge(test_operation(TEST_OPERATION_1), test_revision(1.0))
    .replica()
  let deleting = saved.request_deletion().replica()
  guard deleting.directive() is ReplicaDirective::CreateOperation(draft) else {
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
  let deleting = rejected.request_deletion().replica()
  guard deleting.directive() is ReplicaDirective::CreateOperation(draft) else {
    fail("new informed deletion")
  }
  assert_eq(draft.content(), PendingContent::Delete)
  assert_eq(deleting.baseline_revision(), 2.0)
}

///|
test "equal remote text advances baseline once" {
  let replica = reconcile_change(
    initial_replica("same"),
    remote_present(3.0, "same"),
  ).replica()
  assert_eq(replica.directive(), ReplicaDirective::Synchronized)
  assert_eq(replica.baseline_revision(), 3.0)
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
  assert_eq(replica_document(converged).text(), "base")
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
  assert_eq(replica_document(deleted).text(), "base")
}

///|
test "opening an available Replica accepts its retained remote revision" {
  let saved = sending_replica("base", TEST_OPERATION_1)
    .acknowledge(test_operation(TEST_OPERATION_1), test_revision(1.0))
    .replica()
  let retained = remote_present(2.0, "remote")
  let available = reconcile_change(saved, retained).replica()
  guard available.open(test_revision(2.0)) is OpenStep::Persist(write) else {
    fail("available open")
  }
  assert_eq(replica_document(write.replica()).text(), "remote")
  assert_eq(write.replica().baseline_revision(), 2.0)
  assert_eq(write.replica().directive(), ReplicaDirective::Synchronized)
}

///|
test "opening an available Replica uses its newest retained revision" {
  let saved = sending_replica("base", TEST_OPERATION_1)
    .acknowledge(test_operation(TEST_OPERATION_1), test_revision(1.0))
    .replica()
  let available = reconcile_change(saved, remote_present(3.0, "newest")).replica()
  guard available.open(test_revision(2.0)) is OpenStep::Persist(write) else {
    fail("newest retained open")
  }
  assert_eq(replica_document(write.replica()).text(), "newest")
  assert_eq(write.replica().baseline_revision(), 3.0)
}

///|
test "opening a tombstoned available Replica is unavailable" {
  let saved = sending_replica("base", TEST_OPERATION_1)
    .acknowledge(test_operation(TEST_OPERATION_1), test_revision(1.0))
    .replica()
  let tombstone = RemoteDocument::Deleted(test_revision(2.0))
  let available = reconcile_change(saved, tombstone).replica()
  assert_eq(available.open(test_revision(2.0)), OpenStep::Unavailable)
}

///|
test "opening waits until a newer remote revision has been reconciled" {
  let saved = sending_replica("base", TEST_OPERATION_1)
    .acknowledge(test_operation(TEST_OPERATION_1), test_revision(1.0))
    .replica()
  assert_eq(saved.open(test_revision(2.0)), OpenStep::AwaitSync)
}

///|
test "opening a covered Replica is ready even with a pending local operation" {
  let saved = sending_replica("base", TEST_OPERATION_1)
    .acknowledge(test_operation(TEST_OPERATION_1), test_revision(1.0))
    .replica()
  let sending = edit_write(saved, "local").replica()
  assert_eq(sending.open(test_revision(1.0)), OpenStep::Ready)
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
  guard test_edit(available, "local after notice")
    is EditPlan::Persist(diverged) else {
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
  let deleting = saved.request_deletion().replica()
  guard deleting.directive() is ReplicaDirective::CreateOperation(delete_draft) else {
    fail("expected delete draft")
  }
  let deleted = delete_draft
    .start(test_operation(TEST_OPERATION_2))
    .replica()
    .acknowledge(test_operation(TEST_OPERATION_2), test_revision(2.0))
    .replica()
  assert_eq(deleted.directive(), ReplicaDirective::Synchronized)
  assert_true(deleted.is_deleted())
}

///|
test "deletion resolves an uncertain save before creating delete operation" {
  let sending = sending_replica("sent", TEST_OPERATION_1)
  let edited = edit_write(sending, "newer").replica()
  let deleting = edited.request_deletion().replica()
  guard deleting.directive() is ReplicaDirective::Send(save) else {
    fail("resolve save first")
  }
  assert_eq(save.operation_id(), test_operation(TEST_OPERATION_1))
  assert_eq(
    save.content(),
    PendingContent::Save(Content("sent", ChangeTime(0.0))),
  )
  let resolved = deleting
    .acknowledge(test_operation(TEST_OPERATION_1), test_revision(1.0))
    .replica()
  guard resolved.directive() is ReplicaDirective::CreateOperation(delete) else {
    fail("delete should become preparable")
  }
  assert_eq(delete.content(), PendingContent::Delete)
  assert_eq(resolved.document(), None)
}

///|
test "unpublished deletion removes the replica without creating a delete state" {
  let replica = initial_replica("text")
  assert_eq(replica.request_deletion(), ReplicaWrite::Remove(replica))
}

///|
test "deletion rejects an observed tombstone instead of persisting a no-op" {
  let synchronized = sending_replica("base", TEST_OPERATION_1)
    .acknowledge(test_operation(TEST_OPERATION_1), test_revision(1.0))
    .replica()
  let observed = reconcile_change(
    synchronized,
    RemoteDocument::Deleted(test_revision(2.0)),
  ).replica()
  let deleted = observed.request_deletion().replica()
  assert_true(deleted.is_deleted())
  assert_eq(deleted.directive(), ReplicaDirective::Synchronized)
  assert_eq(
    try {
      deleted.request_deletion() |> ignore
      None
    } catch {
      error => Some(error)
    },
    Some(DeletionUnavailable::AlreadyDeleted),
  )
  assert_eq(test_edit(deleted, "later"), EditPlan::Unavailable)
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

///|
/// The replica's working document after the user types `text`.
fn test_working(replica : DocumentReplica, text : String) -> Document {
  match replica.document() {
    Some(document) => document.update(text, ChangeTime(1.0))
    None => Document::create(replica.document_id(), text, ChangeTime(1.0))
  }
}

///|
fn test_edit(replica : DocumentReplica, text : String) -> EditPlan {
  replica.edit(test_working(replica, text))
}

///|
/// A Replica saved as "base" at 1, edited to "local" at 3, that then observes
/// a remote "remote" revision at 2.
fn rule_a_replica(remote : String) -> DocumentReplica raise {
  let id = test_document_id("document")
  let saved = DocumentReplica(
      test_account(),
      Document::create(id, "base", ChangeTime(1.0)),
    )
    |> start_save(TEST_OPERATION_1)
    |> ReplicaWrite::replica
  let saved = saved
    .acknowledge(test_operation(TEST_OPERATION_1), test_revision(1.0))
    .replica()
  guard saved.edit(Document::create(id, "local", ChangeTime(3.0)))
    is EditPlan::Persist(edited) else {
    abort("edit")
  }
  reconcile_change(
    edited.replica(),
    RemoteDocument::Present(
      test_revision(2.0),
      Content(remote, ChangeTime(2.0)),
    ),
  ).replica()
}

///|
test "a working copy equal to a known version keeps that version's Change time" {
  let live = rule_a_replica("remote").live().unwrap()
  let time = (text : String) => live.working(text, ChangeTime(9.0)).changed_at()
  assert_eq(time("remote"), ChangeTime(2.0))
  assert_eq(time("base"), ChangeTime(1.0))
  assert_eq(time("local"), ChangeTime(3.0))
  assert_eq(time("new"), ChangeTime(9.0))
}

///|
test "a remote revision with the local text gives it the remote Change time" {
  let settled = rule_a_replica("local")
  assert_eq(
    settled.document(),
    Some(
      Document::create(test_document_id("document"), "local", ChangeTime(2.0)),
    ),
  )
  assert_eq(settled.directive(), ReplicaDirective::Synchronized)
}
