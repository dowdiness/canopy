///|
fn test_account(value : String) -> @source_repository.AccountId {
  @source_repository.AccountId::parse(value) catch {
    _ => abort("invalid test account")
  }
}

///|
fn test_document_id() -> @source_repository.DocumentId {
  @source_repository.DocumentId::parse("document") catch {
    _ => abort("invalid test document id")
  }
}

///|
fn test_document(text : String) -> @source_repository.Document {
  @source_repository.Document::create(test_document_id(), text)
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
  let failed = state.failed(attempt.request_id(), first.checkpoint())
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
  let failed = state.failed(first.request_id(), write.checkpoint())
  let (retrying, retry) = failed.persist(write)
  let retry = retry.unwrap()
  let stale : Result[(State, Attempt?), CompletionError] = Ok(
    retrying.stored(first.request_id(), write.checkpoint()),
  ) catch { error => Err(error) }
  assert_eq(stale, Err(CompletionError::StaleCompletion))
  let (done, next) = retrying.stored(retry.request_id(), write.checkpoint())
  assert_eq(next, None)
  assert_true(done.lanes.is_empty())
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
  ) catch { error => Err(error) }
  assert_eq(result, Err(CompletionError::StaleCompletion))
}
