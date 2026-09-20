///|
fn test_account(value : String) -> @source_repository.AccountId {
  @source_repository.AccountId::parse(value) catch {
    _ => abort("invalid test account")
  }
}

///|
fn test_document_id(
  value? : String = "document",
) -> @source_repository.DocumentId {
  let mut hash = 0
  for byte in value {
    hash = (hash * 131 + byte.to_int()) % 65521
  }
  let hex = hash.to_string(radix=16)
  let id = "a0000000-0000-4000-8000-" +
    String::make(12 - hex.length(), '0') +
    hex
  @source_repository.DocumentId::parse(id) catch {
    _ => abort("invalid test document id")
  }
}

///|
fn test_document(text : String) -> @source_repository.Document {
  @source_repository.Document::create(test_document_id(), text)
}

///|
fn test_operation_id() -> @source_repository.OperationId {
  @source_repository.OperationId::parse("10000000-0000-4000-8000-000000000001") catch {
    _ => abort("invalid test operation id")
  }
}

///|
fn test_revision() -> @source_repository.SavedRevision {
  @source_repository.SavedRevision::parse(1.0) catch {
    _ => abort("invalid test revision")
  }
}

///|
fn test_sending_checkpoint() -> @source_repository.SyncCheckpoint {
  let checkpoint = @source_repository.SyncCheckpoint::enroll(
    test_account("account"),
    test_document("sent"),
  )
  guard checkpoint.plan_save() is @source_repository.Start(draft) else {
    abort("expected save draft")
  }
  draft.start(test_operation_id()).checkpoint()
}

///|
fn test_write(
  account : @source_repository.AccountId,
  text : String,
) -> @source_repository.CheckpointWrite {
  @source_repository.SyncCheckpoint::enroll(account, test_document("original"))
  .edit(text)
  .unwrap()
}

///|
test "only the latest account lookup can select an account" {
  let (sync, first) = State().begin_lookup()
  let (sync, second) = sync.begin_lookup()
  let account = test_account("account-a")
  let (stale, selected) = sync.resolved(first, Resolved(account, "A"))
  assert_eq(selected, None)
  assert_true(stale.session() == Resolving(second))
  let (current, selected) = stale.resolved(second, Resolved(account, "A"))
  assert_eq(selected, Some(AccountSelection::AccountSelected(account)))
  assert_true(current.session() == Current(account, "A"))
}

///|
test "account changes retain transient document attempts" {
  let account_a = test_account("account-a")
  let account_b = test_account("account-b")
  let write = test_write(account_a, "local")
  let (state, attempt) = State().persist(write)
  let attempt = attempt.unwrap()
  let (state, request) = state.begin_lookup()
  let (state, _) = state.resolved(request, Resolved(account_b, "B"))
  let (state, request) = state.begin_lookup()
  let (state, _) = state.resolved(request, Resolved(account_a, "A"))
  let (state, follow_up) = state.stored(
    attempt.request_id(),
    write.checkpoint(),
  )
  assert_eq(follow_up, None)
  assert_true(state.session() == Current(account_a, "A"))
  assert_true(state.lanes.is_empty())
}

///|
test "an explicit request retries the newest failed checkpoint" {
  let account = test_account("account")
  let first = test_write(account, "first")
  let latest = first.checkpoint().edit("latest").unwrap()
  let (state, attempt) = State().persist(first)
  let attempt = attempt.unwrap()
  let (state, _) = state.persist(latest)
  let (failed, retained) = state.failed(
    attempt.request_id(),
    first.checkpoint(),
  )
  assert_eq(retained, latest.checkpoint())
  let (retrying, retry) = failed.persist(latest)
  let retry = retry.unwrap()
  assert_eq(retry.write(), latest)
  assert_true(retry.request_id() != attempt.request_id())
  assert_true(retrying.lanes[0].state is LaneState::Storing(_, None))
}

///|
test "old completion cannot finish an identical retry" {
  let account = test_account("account")
  let write = test_write(account, "local")
  let (state, first) = State().persist(write)
  let first = first.unwrap()
  let (failed, _) = state.failed(first.request_id(), write.checkpoint())
  let (retrying, retry) = failed.persist(write)
  let retry = retry.unwrap()
  let stale : Result[(State, Attempt?), CompletionError] = Ok(
    retrying.stored(first.request_id(), write.checkpoint()),
  ) catch {
    error => Err(error)
  }
  assert_eq(stale, Err(CompletionError::StaleCompletion))
  let (done, next) = retrying.stored(retry.request_id(), write.checkpoint())
  assert_eq(next, None)
  assert_true(done.lanes.is_empty())
}

///|
test "lifecycle retry resumes metadata writes but not newer document text" {
  let durable = test_sending_checkpoint()
  let (state, _) = State().schedule(durable)
  let (state, acknowledgment) = state.acknowledged(
    durable,
    test_operation_id(),
    test_revision(),
  )
  let acknowledgment = acknowledgment.unwrap()
  let (failed, _) = state.failed(
    acknowledgment.request_id(),
    acknowledgment.write().checkpoint(),
  )
  assert_true(failed.retry_metadata(durable).1 is Some(_))

  let (state, saving) = State().save(durable, "newer")
  let saving = saving.unwrap()
  let (failed, _) = state.failed(
    saving.request_id(),
    saving.write().checkpoint(),
  )
  assert_eq(failed.retry_metadata(durable).1, None)
}

///|
test "completion cannot cross an account lane" {
  let account_a = test_account("account-a")
  let account_b = test_account("account-b")
  let write = test_write(account_a, "local")
  let other = test_write(account_b, "local").checkpoint()
  let (state, attempt) = State().persist(write)
  let result : Result[(State, Attempt?), CompletionError] = Ok(
    state.stored(attempt.unwrap().request_id(), other),
  ) catch {
    error => Err(error)
  }
  assert_eq(result, Err(CompletionError::StaleCompletion))
}

///|
test "acknowledgment follows a local write already in the lane" {
  let durable = test_sending_checkpoint()
  let (state, saving) = State().save(durable, "newer")
  let saving = saving.unwrap()
  let (state, acknowledging) = state.acknowledge(
    durable,
    test_operation_id(),
    test_revision(),
  )
  assert_eq(acknowledging, None)

  let (_, acknowledging) = state.stored(
    saving.request_id(),
    saving.write().checkpoint(),
  )
  let acknowledged = acknowledging.unwrap().write().checkpoint()
  assert_eq(acknowledged.document().text(), "newer")
  assert_true(acknowledged.directive() is @source_repository.SaveRequired)
}

///|
test "local write follows an acknowledgment already in the lane" {
  let durable = test_sending_checkpoint()
  let (state, acknowledging) = State().acknowledge(
    durable,
    test_operation_id(),
    test_revision(),
  )
  let acknowledging = acknowledging.unwrap()
  let (state, saving) = state.save(durable, "newer")
  assert_eq(saving, None)

  let (_, saving) = state.stored(
    acknowledging.request_id(),
    acknowledging.write().checkpoint(),
  )
  let saved = saving.unwrap().write().checkpoint()
  assert_eq(saved.document().text(), "newer")
  assert_true(saved.directive() is @source_repository.SaveRequired)
}

///|
test "durable save planning precedes delivery" {
  let durable = @source_repository.SyncCheckpoint::enroll(
    test_account("account"),
    test_document("local"),
  )
  let (state, action) = State().schedule(durable)
  guard action is Some(CreateOperation(plan, _, _)) else {
    fail("operation identity")
  }
  let (state, storing) = state.prepared(plan, durable, test_operation_id())
  let storing = storing.unwrap()
  assert_true(
    storing.write().checkpoint().directive()
    is @source_repository.SyncDirective::Send(operation) &&
    operation.operation_id() == test_operation_id(),
  )
  let (state, next) = state.stored(
    storing.request_id(),
    storing.write().checkpoint(),
  )
  assert_eq(next, None)
  let (_, action) = state.schedule(storing.write().checkpoint())
  assert_true(action is Some(Action::Deliver(_, _, _)))
}

///|
test "one durable pending operation has one active delivery" {
  let durable = test_sending_checkpoint()
  let (state, action) = State().schedule(durable)
  assert_true(action is Some(Action::Deliver(_, _, _)))
  let (_, duplicate) = state.schedule(durable)
  assert_eq(duplicate, None)
}

///|
test "delivery acknowledgment uses a newer local causal head" {
  let durable = test_sending_checkpoint()
  let (state, _) = State().schedule(durable)
  let (state, local_write) = state.save(durable, "newer")
  let local_write = local_write.unwrap()
  let (state, acknowledgment) = state.acknowledged(
    durable,
    test_operation_id(),
    test_revision(),
  )
  assert_eq(acknowledgment, None)
  let (_, acknowledgment) = state.stored(
    local_write.request_id(),
    local_write.write().checkpoint(),
  )
  let acknowledged = acknowledgment.unwrap().write().checkpoint()
  assert_eq(acknowledged.document().text(), "newer")
  assert_true(acknowledged.directive() is @source_repository.SaveRequired)
}

///|
test "uncertain delivery retries and oversized content waits for an edit" {
  let durable = test_sending_checkpoint()
  let (state, _) = State().schedule(durable)
  let retryable = state.delivery_failed(durable, test_operation_id())
  assert_true(retryable.schedule(durable).1 is Some(Action::Deliver(_, _, _)))

  let (state, _) = State().schedule(durable)
  let (state, rejected) = state.delivery_too_large(
    durable,
    test_operation_id(),
  )
  let rejected = rejected.unwrap()
  let rejected_checkpoint = rejected.write().checkpoint()
  assert_true(rejected_checkpoint.directive() is @source_repository.SaveRequired)
  let (state, _) = state.stored(
    rejected.request_id(),
    rejected_checkpoint,
  )
  assert_eq(state.schedule(rejected_checkpoint).1, None)
  assert_true(state.save(rejected_checkpoint, "smaller").1 is Some(_))
}

///|
test "new text written during delivery is not blocked by the old rejection" {
  let durable = test_sending_checkpoint()
  let (state, _) = State().schedule(durable)
  let (state, saving) = state.save(durable, "smaller")
  let saving = saving.unwrap()
  let (state, rejected) = state.delivery_too_large(
    durable,
    test_operation_id(),
  )
  assert_eq(rejected, None)
  let (state, rejected) = state.stored(
    saving.request_id(),
    saving.write().checkpoint(),
  )
  let rejected = rejected.unwrap()
  let (state, _) = state.stored(
    rejected.request_id(),
    rejected.write().checkpoint(),
  )
  assert_true(
    state.schedule(rejected.write().checkpoint()).1
    is Some(Action::CreateOperation(_, _, _)),
  )
}

///|
test "rejected operation identity is replaced without another edit" {
  let durable = test_sending_checkpoint()
  let (state, _) = State().schedule(durable)
  let (state, rejected) = state.operation_rejected(
    durable,
    test_operation_id(),
  )
  let rejected = rejected.unwrap()
  let (state, _) = state.stored(
    rejected.request_id(),
    rejected.write().checkpoint(),
  )
  assert_true(
    state.schedule(rejected.write().checkpoint()).1
    is Some(Action::CreateOperation(_, _, _)),
  )
}

///|
test "revision conflict creates recovery before replacing the checkpoint" {
  let durable = test_sending_checkpoint()
  let (state, _) = State().schedule(durable)
  let state = state.revision_conflict(durable, test_operation_id())
  let (state, fetching) = state.schedule(durable)
  assert_true(fetching is Some(Action::FetchRemote(_, _, _)))
  let remote = @source_repository.RemoteDocument::Present(
    test_revision(),
    "remote",
  )
  let (state, action) = state.rejected(
    durable,
    test_operation_id(),
    remote,
  )
  assert_eq(action, ConflictAction::CreateRecovery)
  let recovery_id = @source_repository.DocumentId::parse("recovery") catch {
    _ => abort("valid recovery id")
  }
  let (_, storing) = state.recover(
    durable,
    test_operation_id(),
    recovery_id,
  )
  guard storing.unwrap().write() is @source_repository.CheckpointAndRecovery(
    checkpoint,
    recovery,
  ) else {
    fail("atomic conflict recovery")
  }
  assert_eq(recovery.text(), "sent")
  assert_true(
    checkpoint.directive()
    is @source_repository.SyncDirective::Conflict(_, _),
  )
}

///|
test "failed recovery identity can retry the durable operation" {
  let durable = test_sending_checkpoint()
  let (state, _) = State().schedule(durable)
  let state = state.revision_conflict(durable, test_operation_id())
  let (state, _) = state.schedule(durable)
  let remote = @source_repository.RemoteDocument::Present(
    test_revision(),
    "remote",
  )
  let (state, _) = state.rejected(durable, test_operation_id(), remote)
  let state = state.recovery_failed(
    durable.account(),
    durable.document().id(),
    test_operation_id(),
  )
  assert_true(state.schedule(durable).1 is Some(Action::Deliver(_, _, _)))
}
