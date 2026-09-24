///|
fn test_account() -> @source_repository.AccountId {
  @source_repository.AccountId::parse("account") catch {
    _ => abort("account")
  }
}

///|
fn test_document_id() -> @source_repository.DocumentId {
  @source_repository.DocumentId::parse("00000000-0000-4000-8000-000000000001") catch {
    _ => abort("document id")
  }
}

///|
fn replica(text : String) -> @source_repository.DocumentReplica {
  @source_repository.DocumentReplica(
    test_account(),
    @source_repository.Document::create(test_document_id(), text),
  )
}

///|
fn replica_text(replica : @source_repository.DocumentReplica) -> String {
  replica.document().map(document => document.text()).unwrap()
}

///|
fn synchronized_replica(text : String) -> @source_repository.DocumentReplica {
  let initial = replica(text)
  guard initial.directive()
    is @source_repository.ReplicaDirective::CreateOperation(draft) else {
    abort("initial save")
  }
  let operation = @source_repository.OperationId::parse(
    "10000000-0000-4000-8000-000000000001",
  ) catch {
    _ => abort("operation id")
  }
  let revision = @source_repository.SavedRevision::parse(1.0) catch {
    _ => abort("revision")
  }
  draft.start(operation).replica().acknowledge(operation, revision).replica() catch {
    _ => abort("save acknowledgment")
  }
}

///|
test "a lane persists one write and retains only its newest successor" {
  let first = replica("first").store()
  let second = first.replica().edit("second")
  guard second is @source_repository.EditPlan::Persist(second) else {
    fail("second write")
  }
  let third = second.replica().edit("third")
  guard third is @source_repository.EditPlan::Persist(third) else {
    fail("third write")
  }
  let (state, attempt) = State().submit(first)
  let attempt = attempt.unwrap()
  let (state, none) = state.submit(second)
  assert_eq(none, None)
  let (state, none) = state.submit(third)
  assert_eq(none, None)
  let (state, completion) = state.complete(attempt, Ok(())) catch {
    _ => abort("current attempt")
  }
  guard completion is Superseded(stored, next) else { fail("successor") }
  assert_eq(replica_text(stored.replica()), "first")
  assert_eq(replica_text(next.write().replica()), "third")
  assert_true(
    state.status(test_account(), test_document_id()) is Status::Persisting,
  )
}

///|
test "failure retains the exact newest write for explicit retry" {
  let first = replica("first").store()
  let second = first.replica().edit("second")
  guard second is @source_repository.EditPlan::Persist(second) else {
    fail("second write")
  }
  let (state, attempt) = State().submit(first)
  let attempt = attempt.unwrap()
  let (state, _) = state.submit(second)
  let (state, completion) = state.complete(
    attempt,
    Err(@source_repository.ReplicaFailure::WriteFailed),
  ) catch {
    _ => abort("current attempt")
  }
  guard completion is Retryable(retained, retry, WriteFailed) else {
    fail("retryable failure")
  }
  assert_eq(replica_text(retained.replica()), "second")
  let (state, retried) = state.retry(retry) catch {
    _ => abort("current retry")
  }
  assert_eq(retried.write(), retained)
  assert_true(
    state.status(test_account(), test_document_id()) is Status::Persisting,
  )
}

///|
test "a retry capability expires when its retried attempt fails" {
  let (state, attempt) = State().submit(replica("text").store())
  let (state, completion) = state.complete(
    attempt.unwrap(),
    Err(@source_repository.ReplicaFailure::WriteFailed),
  ) catch {
    _ => abort("first attempt")
  }
  guard completion is Retryable(_, first_retry, _) else { fail("first retry") }
  let (state, second_attempt) = state.retry(first_retry) catch {
    _ => abort("current retry")
  }
  let (state, completion) = state.complete(
    second_attempt,
    Err(@source_repository.ReplicaFailure::WriteFailed),
  ) catch {
    _ => abort("second attempt")
  }
  guard completion is Retryable(_, second_retry, _) else {
    fail("second retry")
  }
  let expired = try state.retry(first_retry) catch {
    ExpiredRetry => true
  } noraise {
    _ => false
  }
  assert_true(expired)
  let (_, next) = state.retry(second_retry) catch { _ => abort("latest retry") }
  assert_true(next != second_attempt)
}

///|
test "a newer eligible edit replaces a failed write and starts immediately" {
  let first = replica("first").store()
  let (state, attempt) = State().submit(first)
  let (state, completion) = state.complete(
    attempt.unwrap(),
    Err(@source_repository.ReplicaFailure::QuotaExceeded),
  ) catch {
    _ => abort("current attempt")
  }
  guard completion is Retryable(_, _, QuotaExceeded) else {
    fail("retryable failure")
  }
  guard first.replica().edit("smaller")
    is @source_repository.EditPlan::Persist(smaller) else {
    fail("newer write")
  }
  let (state, replacement) = state.submit(smaller)
  assert_eq(replica_text(replacement.unwrap().write().replica()), "smaller")
  assert_true(
    state.status(test_account(), test_document_id()) is Status::Persisting,
  )
}

///|
test "failed source ownership transfer closes its lane" {
  let write = replica("text").promote_source()
  let (state, attempt) = State().submit(write)
  guard write.replica().edit("newer")
    is @source_repository.EditPlan::Persist(newer) else {
    fail("newer write")
  }
  let (state, successor) = state.submit(newer)
  assert_eq(successor, None)
  let (state, completion) = state.complete(
    attempt.unwrap(),
    Err(@source_repository.ReplicaFailure::WriteFailed),
  ) catch {
    _ => abort("current attempt")
  }
  assert_true(completion is Failed(_, WriteFailed))
  assert_true(
    state.status(test_account(), test_document_id()) is Status::Current,
  )
}

///|
test "successful source ownership transfer releases its newest successor" {
  let write = replica("text").promote_source()
  guard write.replica().edit("newer")
    is @source_repository.EditPlan::Persist(newer) else {
    fail("newer write")
  }
  let (state, attempt) = State().submit(write)
  let (state, successor) = state.submit(newer)
  assert_eq(successor, None)
  let (_, completion) = state.complete(attempt.unwrap(), Ok(())) catch {
    _ => abort("current attempt")
  }
  guard completion is Superseded(stored, next) else { fail("successor") }
  assert_eq(replica_text(stored.replica()), "text")
  assert_eq(replica_text(next.write().replica()), "newer")
  assert_true(next.write() is @source_repository.ReplicaWrite::Store(_))
}

///|
test "queued deletion supersedes an active save without losing its intent" {
  let current = synchronized_replica("first")
  guard current.edit("newer") is @source_repository.EditPlan::Persist(save) else {
    fail("save write")
  }
  let deletion = save.replica().request_deletion()
  let (state, attempt) = State().submit(save)
  let (state, queued) = state.submit(deletion)
  assert_eq(queued, None)
  let (_, completion) = state.complete(attempt.unwrap(), Ok(())) catch {
    _ => abort("active save")
  }
  guard completion is Superseded(_, next) else { fail("queued deletion") }
  assert_true(next.write().replica().is_deleting())
  assert_eq(next.write(), deletion)
}

///|
test "failed deletion branches new edits from the durable replica" {
  let durable = synchronized_replica("durable")
  let deletion = durable.request_deletion()
  let (state, attempt) = State().submit(deletion)
  let (state, completion) = state.complete(
    attempt.unwrap(),
    Err(@source_repository.ReplicaFailure::WriteFailed),
  ) catch {
    _ => abort("deletion attempt")
  }
  assert_true(completion is Retryable(_, _, WriteFailed))
  assert_eq(state.editing_base(durable), durable)
  guard state.editing_base(durable).edit("edited after failure")
    is @source_repository.EditPlan::Persist(edit) else {
    fail("durable replica remains editable")
  }
  let (_, replacement) = state.submit(edit)
  assert_eq(
    replacement.map(attempt => replica_text(attempt.write().replica())),
    Some("edited after failure"),
  )
}

///|
test "a delayed acknowledgment rebases a failed newer edit" {
  let base = synchronized_replica("base")
  guard base.edit("sent") is @source_repository.EditPlan::Persist(ready) &&
    ready.replica().directive()
    is @source_repository.ReplicaDirective::CreateOperation(draft) else {
    fail("save draft")
  }
  let operation = @source_repository.OperationId::parse(
    "20000000-0000-4000-8000-000000000002",
  ) catch {
    _ => abort("operation id")
  }
  let durable = draft.start(operation).replica()
  guard durable.edit("newer") is @source_repository.EditPlan::Persist(newer) else {
    fail("newer edit")
  }
  let (state, attempt) = State().submit(newer)
  let (state, _) = state.complete(
    attempt.unwrap(),
    Err(@source_repository.ReplicaFailure::WriteFailed),
  ) catch {
    _ => abort("newer write")
  }
  let revision = @source_repository.SavedRevision::parse(2.0) catch {
    _ => abort("revision")
  }
  let acknowledged = state
    .protocol_base(durable)
    .acknowledge(operation, revision) catch {
      _ => abort("delayed acknowledgment")
    }
  let (_, replacement) = state.submit(acknowledged)
  let replacement = replacement.unwrap().write().replica()
  assert_eq(replica_text(replacement), "newer")
  guard replacement.directive()
    is @source_repository.ReplicaDirective::CreateOperation(draft) else {
    fail("newer edit remains pending")
  }
  assert_eq(draft.content(), @source_repository.PendingContent::Save("newer"))
}

///|
test "a replayed completion is explicitly stale" {
  let (state, attempt) = State().submit(replica("text").store())
  let attempt = attempt.unwrap()
  let (state, _) = state.complete(attempt, Ok(())) catch {
    _ => abort("current attempt")
  }
  let replay : Result[(State, Completion), StaleAttempt] = Ok(
    state.complete(attempt, Ok(())),
  ) catch {
    error => Err(error)
  }
  assert_eq(replay, Err(StaleAttempt::StaleAttempt))
}
