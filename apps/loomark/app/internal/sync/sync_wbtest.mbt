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
  @source_repository.DocumentId::parse(
    "a0000000-0000-4000-8000-" + String::make(12 - hex.length(), '0') + hex,
  ) catch {
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
fn revision(value : Double) -> @source_repository.SavedRevision {
  @source_repository.SavedRevision::parse(value) catch {
    _ => abort("invalid revision")
  }
}

///|
fn sending_replica() -> @source_repository.DocumentReplica {
  let replica = @source_repository.DocumentReplica(
    test_account("account"),
    test_document("sent"),
  )
  guard replica.plan_save() is @source_repository.OperationPlan::Start(draft) else {
    abort("save draft")
  }
  draft.start(test_operation_id()).replica()
}

///|
fn signed_in(account : @source_repository.AccountId) -> State {
  let (state, lookup) = State().begin_lookup()
  state.resolved(lookup, Resolved(account, "Writer")).0
}

///|
fn with_catalog(
  state : State,
  account : @source_repository.AccountId,
  entries : Array[@source_repository.RemoteEntry],
) -> State {
  let (state, discovery) = state.begin_discovery()
  state.discovered(account, discovery.unwrap(), Some(entries)).0
}

///|
test "only the latest account lookup can select an account" {
  let (state, first) = State().begin_lookup()
  let (state, second) = state.begin_lookup()
  let account = test_account("account-a")
  let (state, selected) = state.resolved(first, Resolved(account, "A"))
  assert_eq(selected, None)
  assert_true(state.session() == Resolving(second))
  let (state, selected) = state.resolved(second, Resolved(account, "A"))
  assert_eq(selected, Some(AccountSelection::AccountSelected(account)))
  assert_true(state.session() == Current(account, "A"))
}

///|
test "delivery capability prevents operation-id ABA" {
  let replica = sending_replica()
  let state = signed_in(replica.account())
  guard state.advance(replica) is (state, Some(Deliver(first, _, _, _))) else {
    fail("first delivery")
  }
  let state = state.delivery_failed(replica, first, test_operation_id())
  guard state.advance(replica) is (state, Some(Deliver(second, _, _, _))) else {
    fail("second delivery")
  }
  let stale : Result[(State, @source_repository.ReplicaWrite?), WorkError] = Ok(
    state.acknowledged(replica, first, test_operation_id(), revision(1.0)),
  ) catch {
    error => Err(error)
  }
  assert_true(first != second)
  assert_eq(stale, Err(WorkError::StaleWork))
}

///|
test "progress exposes only network work for one replica" {
  let replica = sending_replica()
  let idle = signed_in(replica.account())
  assert_true(idle.progress(replica) is Progress::Retryable(_))
  guard idle.advance(replica) is (working, Some(Deliver(_, _, _, _))) else {
    fail("delivery")
  }
  assert_eq(working.progress(replica), Progress::Working)
  let other = @source_repository.DocumentReplica::receive(
    replica.account(),
    @source_repository.Document::create(
      test_document_id(value="other"),
      "other",
    ),
    revision(1.0),
  )
  assert_eq(working.progress(other), Progress::Inactive)
}

///|
test "opening a remote document returns one replica write" {
  let account = test_account("account")
  let entry = @source_repository.RemoteEntry::Present(
    test_document_id(),
    revision(2.0),
    "Remote",
  )
  guard signed_in(account).select_open(entry).advance_open(None)
    is (state, Some(GetRemote(effect, _, _, Open(intent, expected)))) else {
    fail("open read")
  }
  let (state, write) = state.opened(
    effect,
    account,
    test_document_id(),
    intent,
    expected,
    None,
    @source_repository.RemoteDocument::Present(revision(2.0), "remote text"),
  )
  let replica = write.unwrap().replica()
  assert_eq(replica.document().text(), "remote text")
  assert_eq(state.select_open(entry).advance_open(Some(replica)).1, None)
}

///|
test "a newer remote open advances the supplied causal head" {
  let account = test_account("account")
  let first = @source_repository.DocumentReplica::receive(
    account,
    test_document("first"),
    revision(1.0),
  )
  let entry = @source_repository.RemoteEntry::Present(
    test_document_id(),
    revision(2.0),
    "Second",
  )
  guard signed_in(account).select_open(entry).advance_open(Some(first))
    is (state, Some(GetRemote(effect, _, _, Open(intent, expected)))) else {
    fail("newer open")
  }
  let (_, write) = state.opened(
    effect,
    account,
    test_document_id(),
    intent,
    expected,
    Some(first),
    @source_repository.RemoteDocument::Present(revision(2.0), "second"),
  )
  let second = write.unwrap().replica()
  assert_eq(second.generation(), first.generation() + 1.0)
  assert_eq(second.baseline_revision(), 2.0)
}

///|
test "failed catalog revision fetch remains retryable" {
  let account = test_account("account")
  let replica = @source_repository.DocumentReplica::receive(
    account,
    test_document("base"),
    revision(1.0),
  )
  let state = with_catalog(signed_in(account), account, [
    @source_repository.RemoteEntry::Present(
      test_document_id(),
      revision(2.0),
      "Remote",
    ),
  ])
  guard state.advance(replica)
    is (state, Some(GetRemote(effect, _, _, Revision(expected)))) else {
    fail("revision fetch")
  }
  let state = state.remote_failed(replica, effect, Revision(expected)) catch {
    _ => abort("active fetch")
  }
  assert_true(state.progress(replica) is Retryable(_))
  assert_true(
    state.advance(replica).1 is Some(GetRemote(_, _, _, Revision(retry))) &&
    retry == revision(2.0),
  )
}

///|
test "an available update continues observing newer catalog revisions" {
  let account = test_account("account")
  let base = @source_repository.DocumentReplica::receive(
    account,
    test_document("base"),
    revision(1.0),
  )
  guard base.reconcile(
      @source_repository.RemoteDocument::Present(revision(2.0), "remote-two"),
    )
    is @source_repository.ReconcilePlan::Persist(write) else {
    fail("available update")
  }
  let available = write.replica()
  let state = with_catalog(signed_in(account), account, [
    @source_repository.RemoteEntry::Present(
      test_document_id(),
      revision(3.0),
      "Remote three",
    ),
  ])
  assert_true(
    state.advance(available).1 is Some(GetRemote(_, _, _, Revision(expected))) &&
    expected == revision(3.0),
  )
}

///|
test "catalog keeps unseen entries and only accepts newer revisions" {
  let account = test_account("account")
  let first = test_document_id(value="a")
  let second = test_document_id(value="b")
  let state = with_catalog(signed_in(account), account, [
    @source_repository.RemoteEntry::Present(first, revision(2.0), "A"),
    @source_repository.RemoteEntry::Present(second, revision(1.0), "B"),
  ])
  let state = with_catalog(state, account, [
    @source_repository.RemoteEntry::Deleted(first, revision(1.0)),
  ])
  assert_true(
    state.remote_entry(first)
    is Some(@source_repository.RemoteEntry::Present(_, _, "A")),
  )
  assert_true(state.remote_entry(second) is Some(_))
  let state = with_catalog(state, account, [
    @source_repository.RemoteEntry::Deleted(first, revision(3.0)),
  ])
  assert_true(
    state.remote_entry(first)
    is Some(@source_repository.RemoteEntry::Deleted(_, _)),
  )
}
