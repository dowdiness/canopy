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
  assert_eq(stored.replica().document().text(), "first")
  assert_eq(next.write().replica().document().text(), "third")
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
  assert_eq(retained.replica().document().text(), "second")
  let (state, retried) = state.retry(retry) catch {
    _ => abort("current retry")
  }
  assert_eq(retried.write(), retained)
  assert_true(
    state.status(test_account(), test_document_id()) is Status::Persisting,
  )
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
  assert_eq(replacement.unwrap().write().replica().document().text(), "smaller")
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
  assert_eq(stored.replica().document().text(), "text")
  assert_eq(next.write().replica().document().text(), "newer")
  assert_true(next.write() is @source_repository.ReplicaWrite::Store(_))
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
