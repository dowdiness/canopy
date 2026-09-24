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
  guard replica.directive()
    is @source_repository.ReplicaDirective::CreateOperation(draft) else {
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
test "account lookup compares delayed responses with the retained catalog" {
  let account = test_account("account")
  let document_id = test_document_id()
  let state = with_catalog(signed_in(account), account, [
    @source_repository.RemoteEntry::Present(
      document_id,
      revision(2.0),
      "Remote",
    ),
  ])
  let (resolving, _) = state.begin_lookup()
  assert_eq(resolving.remote_entry(document_id), None)
  let retained = resolving.retained_remote_entry(document_id)
  assert_true(
    !remote_advances(
      retained,
      @source_repository.RemoteDocument::Present(revision(2.0), "same"),
    ),
  )
  assert_true(
    remote_advances(
      retained,
      @source_repository.RemoteDocument::Present(revision(3.0), "newer"),
    ),
  )
}

///|
test "discovery completion survives lookup of the same account" {
  let account = test_account("account")
  let current = signed_in(account)
  let (discovering, discovery) = current.begin_discovery()
  let (resolving, lookup) = discovering.begin_lookup()
  let entry = @source_repository.RemoteEntry::Present(
    test_document_id(),
    revision(2.0),
    "Remote",
  )
  let (observed, accepted) = resolving.discovered(
    account,
    discovery.unwrap(),
    Some([entry]),
  )
  assert_true(accepted)
  assert_false(observed.discovering())
  let restored = observed.resolved(lookup, Resolved(account, "Writer")).0
  assert_eq(restored.observation(), Observation::Observed)
  assert_eq(restored.remote_entry(test_document_id()), Some(entry))
}

///|
test "new discovery supersedes an older completion" {
  let account = test_account("account")
  let current = signed_in(account)
  let (first, first_id) = current.begin_discovery()
  let (second, second_id) = first.begin_discovery()
  let (stale, accepted) = second.discovered(
    account,
    first_id.unwrap(),
    Some([]),
  )
  assert_false(accepted)
  assert_eq(stale, second)
  assert_true(stale.discovering())
  let (observed, accepted) = stale.discovered(
    account,
    second_id.unwrap(),
    Some([]),
  )
  assert_true(accepted)
  assert_false(observed.discovering())
}

///|
test "delivery capability prevents operation-id ABA" {
  let replica = sending_replica()
  let state = signed_in(replica.account())
  guard state.advance(replica) is (state, Some(Deliver(first, _))) else {
    fail("first delivery")
  }
  let state = state.delivery_failed(replica, first)
  guard state.advance(replica) is (state, Some(Deliver(second, _))) else {
    fail("second delivery")
  }
  let stale : Result[(State, @source_repository.ReplicaWrite?), WorkError] = Ok(
    state.acknowledged(replica, first, revision(1.0)),
  ) catch {
    error => Err(error)
  }
  assert_true(first != second)
  assert_eq(stale, Err(WorkError::StaleWork))
}

///|
test "a delivery retry expires after its retried attempt fails" {
  let replica = sending_replica()
  let state = signed_in(replica.account())
  guard state.advance(replica) is (state, Some(Deliver(first, _))) else {
    fail("first delivery")
  }
  let state = state.delivery_failed(replica, first)
  guard state.activity(replica) is Retryable(first_retry) else {
    fail("first retry")
  }
  let (state, action) = state.retry(replica, first_retry) catch {
    _ => abort("current retry")
  }
  guard action is Deliver(second, _) else { fail("second delivery") }
  let state = state.delivery_failed(replica, second)
  guard state.activity(replica) is Retryable(second_retry) else {
    fail("second retry")
  }
  let expired = try state.retry(replica, first_retry) catch {
    StaleWork => true
  } noraise {
    _ => false
  }
  assert_true(expired)
  assert_true(state.retry(replica, second_retry) is (_, Deliver(_, _)))
}

///|
test "selection does not consume a failed delivery retry" {
  let account = test_account("account")
  let received = @source_repository.DocumentReplica::receive(
    account,
    test_document("base"),
    revision(1.0),
  )
  guard received.edit("edited") is @source_repository.EditPlan::Persist(write) &&
    write.replica().directive()
    is @source_repository.ReplicaDirective::CreateOperation(draft) else {
    fail("edited replica")
  }
  let replica = draft.start(test_operation_id()).replica()
  let state = with_catalog(signed_in(account), account, [
    @source_repository.RemoteEntry::Present(
      replica.document_id(),
      revision(1.0),
      "Remote",
    ),
  ])
  guard state.advance(replica) is (delivering, Some(Deliver(attempt, _))) else {
    fail("delivery")
  }
  let failed = delivering.delivery_failed(replica, attempt) catch {
    _ => abort("active delivery")
  }
  guard failed.activity(replica) is Retryable(retry) else {
    fail("retry capability")
  }
  let selected = failed.select(replica.document_id())
  guard selected.advance_selection(Some(replica))
    is (ready, SelectionStep::Wait) else {
    fail("ready selection")
  }
  assert_eq(ready.activity(replica), Activity::Retryable(retry))
  guard ready.retry(replica, retry) is (_, Deliver(_, resumed)) else {
    fail("resumed delivery")
  }
  assert_eq(resumed.operation_id(), test_operation_id())
}

///|
test "editing a blocked payload admits a new save" {
  let replica = sending_replica()
  let state = signed_in(replica.account())
  guard state.advance(replica) is (state, Some(Deliver(attempt, _))) else {
    fail("delivery")
  }
  let (state, rejected) = state.delivery_too_large(replica, attempt) catch {
    _ => abort("current delivery")
  }
  let blocked = rejected.unwrap().replica()
  assert_eq(state.activity(blocked), Activity::Blocked)
  let (state, changed) = state.save(blocked, "small")
  let changed = changed.unwrap().replica()
  assert_eq(state.activity(changed), Activity::Idle)
  assert_true(state.advance(changed).1 is Some(Action::CreateOperation(_)))
}

///|
test "selection preserves a blocked delivery" {
  let replica = sending_replica()
  let state = with_catalog(signed_in(replica.account()), replica.account(), [
    @source_repository.RemoteEntry::Present(
      replica.document_id(),
      revision(1.0),
      "Remote",
    ),
  ])
  guard state.advance(replica) is (state, Some(Deliver(attempt, _))) else {
    fail("delivery")
  }
  let (blocked, rejected) = state.delivery_too_large(replica, attempt) catch {
    _ => abort("current delivery")
  }
  let replica = rejected.unwrap().replica()
  guard blocked.select(replica.document_id()).advance_selection(Some(replica))
    is (selected, SelectionStep::Wait) else {
    fail("selection")
  }
  assert_eq(selected.activity(replica), Activity::Blocked)
  let cancelled = selected.cancel_selection()
  assert_eq(cancelled.activity(replica), Activity::Blocked)
  assert_eq(cancelled.advance(replica).1, None)
}

///|
test "durable deletion plans and delivers one delete operation" {
  let account = test_account("account")
  let replica = @source_repository.DocumentReplica::receive(
    account,
    test_document("base"),
    revision(1.0),
  )
  let state = signed_in(account)
  let (state, deletion) = state.delete(replica, "latest local text")
  let deleting = deletion.replica()
  guard state.advance(deleting) is (state, Some(CreateOperation(attempt))) else {
    fail("delete operation draft")
  }
  assert_eq(attempt.account(), account)
  assert_eq(attempt.document_id(), test_document_id())
  let (state, prepared) = state.prepared(attempt, deleting, test_operation_id()) catch {
    _ => abort("current delete draft")
  }
  let pending = prepared.unwrap().replica()
  guard state.advance(pending) is (state, Some(Deliver(delivery, operation))) else {
    fail("delete delivery")
  }
  assert_eq(delivery.account(), account)
  assert_eq(delivery.document_id(), test_document_id())
  assert_eq(operation.content(), @source_repository.PendingContent::Delete)
  let (_, acknowledged) = state.acknowledged(pending, delivery, revision(2.0)) catch {
    _ => abort("delete acknowledgment")
  }
  assert_true(acknowledged.unwrap().replica().is_deleted())
}

///|
test "deletion invalidates an in-flight conflict recovery" {
  let account = test_account("account")
  let replica = @source_repository.DocumentReplica::receive(
    account,
    test_document("base"),
    revision(1.0),
  )
  guard replica.edit("local") is @source_repository.EditPlan::Persist(edited) else {
    fail("local edit")
  }
  guard edited
    .replica()
    .reconcile(
      @source_repository.RemoteDocument::Present(revision(2.0), "remote"),
    )
    is @source_repository.ReconcilePlan::Persist(diverged) else {
    fail("conflict")
  }
  let replica = diverged.replica()
  let state = signed_in(account)
  guard state.advance(replica) is (recovering, Some(CreateRecovery(attempt))) else {
    fail("recovery")
  }
  let (state, deletion) = recovering.delete(replica, "local")
  let deleting = deletion.replica()
  assert_true(state.advance(deleting).1 is Some(CreateOperation(_)))
  let delayed = try
    state.recover(deleting, attempt, test_document_id(value="recovery"))
  catch {
    StaleWork => true
  } noraise {
    _ => false
  }
  assert_true(delayed)
}

///|
test "activity exposes only active or failed work for one replica" {
  let replica = sending_replica()
  let idle = signed_in(replica.account())
  assert_eq(idle.activity(replica), Activity::Idle)
  guard idle.advance(replica) is (working, Some(Deliver(_, _))) else {
    fail("delivery")
  }
  assert_eq(working.activity(replica), Activity::Working)
  let other = @source_repository.DocumentReplica::receive(
    replica.account(),
    @source_repository.Document::create(
      test_document_id(value="other"),
      "other",
    ),
    revision(1.0),
  )
  assert_eq(working.activity(other), Activity::Idle)
}

///|
test "selecting a remote-only document returns one replica write" {
  let account = test_account("account")
  let entry = @source_repository.RemoteEntry::Present(
    test_document_id(),
    revision(2.0),
    "Remote",
  )
  let catalog = with_catalog(signed_in(account), account, [entry])
  guard catalog.select(test_document_id()).advance_selection(None)
    is (state, SelectionStep::Fetch(attempt)) else {
    fail("open read")
  }
  let (state, write) = state.opened(
    attempt,
    @source_repository.RemoteDocument::Present(revision(2.0), "remote text"),
  )
  guard write is Some(write) else { fail("received Replica persistence") }
  let replica = write.replica()
  assert_eq(
    replica.document().map(document => document.text()),
    Some("remote text"),
  )
  guard state.advance_selection(Some(replica)) is (ready, SelectionStep::Wait) else {
    fail("durable selection")
  }
  assert_true(ready.ready_selection() is Some(_))
}

///|
test "an authoritative Replica supersedes an active selection fetch" {
  let account = test_account("account")
  let entry = @source_repository.RemoteEntry::Present(
    test_document_id(),
    revision(2.0),
    "Remote",
  )
  let catalog = with_catalog(signed_in(account), account, [entry])
  guard catalog.select(test_document_id()).advance_selection(None)
    is (fetching, SelectionStep::Fetch(attempt)) else {
    fail("selection fetch")
  }
  let replica = @source_repository.DocumentReplica::receive(
    account,
    test_document("durable"),
    revision(2.0),
  )
  guard fetching.advance_selection(Some(replica))
    is (ready, SelectionStep::Wait) &&
    ready.ready_selection() is Some(_) else {
    fail("authoritative Replica")
  }
  let stale = try
    ready.opened(
      attempt,
      @source_repository.RemoteDocument::Present(revision(2.0), "stale"),
    )
  catch {
    WorkError::StaleWork => true
  } noraise {
    _ => false
  }
  assert_true(stale)
}

///|
test "an existing Replica uses its ordinary refresh lane" {
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
  let catalog = with_catalog(signed_in(account), account, [entry])
  let selected = catalog.select(test_document_id())
  guard selected.advance_selection(Some(first))
    is (waiting, SelectionStep::Wait) else {
    fail("waiting selection")
  }
  guard waiting.advance(first) is (reading, Some(GetRemote(attempt))) else {
    fail("ordinary refresh")
  }
  let (state, write) = reading.received(
    first,
    attempt,
    @source_repository.RemoteDocument::Present(revision(2.0), "second"),
  )
  guard write is Some(write) else { fail("newer Replica persistence") }
  let second = write.replica()
  assert_eq(second.generation(), first.generation() + 1.0)
  guard state.advance_selection(Some(second))
    is (_, SelectionStep::Persist(opened)) else {
    fail("open retained remote")
  }
  assert_eq(opened.replica().baseline_revision(), 2.0)
}

///|
test "a tombstone ends a pending remote open" {
  let account = test_account("account")
  let entry = @source_repository.RemoteEntry::Present(
    test_document_id(),
    revision(2.0),
    "Remote",
  )
  let catalog = with_catalog(signed_in(account), account, [entry])
  guard catalog.select(test_document_id()).advance_selection(None)
    is (state, SelectionStep::Fetch(attempt)) else {
    fail("open read")
  }
  let (state, write) = state.opened(
    attempt,
    @source_repository.RemoteDocument::Deleted(revision(2.0)),
  )
  assert_eq(write, None)
  assert_eq(state.selection(), None)
  assert_true(
    state.remote_entry(test_document_id())
    is Some(@source_repository.RemoteEntry::Deleted(_, _)),
  )
}

///|
test "catalog tombstone retires an older open fetch" {
  let account = test_account("account")
  let entry = @source_repository.RemoteEntry::Present(
    test_document_id(),
    revision(1.0),
    "Remote",
  )
  let catalog = with_catalog(signed_in(account), account, [entry])
  guard catalog.select(test_document_id()).advance_selection(None)
    is (fetching, SelectionStep::Fetch(attempt)) else {
    fail("open read")
  }
  let retired = with_catalog(fetching, account, [
    @source_repository.RemoteEntry::Deleted(test_document_id(), revision(2.0)),
  ])
  assert_eq(retired.selection(), None)
  let stale : Result[(State, @source_repository.ReplicaWrite?), WorkError] = Ok(
    retired.opened(
      attempt,
      @source_repository.RemoteDocument::Present(revision(1.0), "remote"),
    ),
  ) catch {
    error => Err(error)
  }
  assert_eq(stale, Err(WorkError::StaleWork))
}

///|
test "catalog tombstone retires an open awaiting durability" {
  let account = test_account("account")
  let entry = @source_repository.RemoteEntry::Present(
    test_document_id(),
    revision(1.0),
    "Remote",
  )
  let catalog = with_catalog(signed_in(account), account, [entry])
  guard catalog.select(test_document_id()).advance_selection(None)
    is (fetching, SelectionStep::Fetch(attempt)) else {
    fail("open read")
  }
  let (persisting, write) = fetching.opened(
    attempt,
    @source_repository.RemoteDocument::Present(revision(1.0), "remote"),
  )
  assert_true(write is Some(_))
  let retired = with_catalog(persisting, account, [
    @source_repository.RemoteEntry::Deleted(test_document_id(), revision(2.0)),
  ])
  assert_eq(retired.selection(), None)
}

///|
test "account lookup retires an active open request without retaining work" {
  let account = test_account("account")
  let entry = @source_repository.RemoteEntry::Present(
    test_document_id(),
    revision(2.0),
    "Remote",
  )
  let catalog = with_catalog(signed_in(account), account, [entry])
  guard catalog.select(test_document_id()).advance_selection(None)
    is (fetching, SelectionStep::Fetch(attempt)) else {
    fail("first open")
  }
  let (resolving, lookup) = fetching.begin_lookup()
  let stale : Result[(State, @source_repository.ReplicaWrite?), WorkError] = Ok(
    resolving.opened(
      attempt,
      @source_repository.RemoteDocument::Present(revision(2.0), "remote"),
    ),
  ) catch {
    error => Err(error)
  }
  assert_eq(stale, Err(WorkError::StaleWork))
  let current = resolving.resolved(lookup, Resolved(account, "Writer")).0
  guard current.select(test_document_id()).advance_selection(None)
    is (_, SelectionStep::Fetch(next)) else {
    fail("next open")
  }
  assert_true(next != attempt)
}

///|
test "failed remote open exposes one expiring retry capability" {
  let account = test_account("account")
  let entry = @source_repository.RemoteEntry::Present(
    test_document_id(),
    revision(2.0),
    "Remote",
  )
  let catalog = with_catalog(signed_in(account), account, [entry])
  guard catalog.select(test_document_id()).advance_selection(None)
    is (fetching, SelectionStep::Fetch(first)) else {
    fail("first open")
  }
  let failed = fetching.open_failed(first) catch { _ => abort("active open") }
  guard failed.selection_activity() is SelectionActivity::Retryable(retry) else {
    fail("retryable open")
  }
  guard failed.retry_selection(retry) is (retrying, OpenRemote(second)) else {
    fail("retried open")
  }
  assert_true(second != first)
  let stale : Result[(State, @source_repository.ReplicaWrite?), WorkError] = Ok(
    retrying.opened(
      first,
      @source_repository.RemoteDocument::Present(revision(2.0), "stale"),
    ),
  ) catch {
    error => Err(error)
  }
  assert_eq(stale, Err(WorkError::StaleWork))
  let failed_again = retrying.open_failed(second) catch {
    _ => abort("retried open")
  }
  let expired : Result[(State, Action), WorkError] = Ok(
    failed_again.retry_selection(retry),
  ) catch {
    error => Err(error)
  }
  assert_eq(expired, Err(WorkError::StaleWork))
}

///|
test "selection uses a failed Replica refresh instead of a second fetch" {
  let account = test_account("account")
  let replica = @source_repository.DocumentReplica::receive(
    account,
    test_document("base"),
    revision(1.0),
  )
  let catalog = with_catalog(signed_in(account), account, [
    @source_repository.RemoteEntry::Present(
      test_document_id(),
      revision(2.0),
      "Remote",
    ),
  ])
  guard catalog.advance(replica) is (reading, Some(GetRemote(attempt))) else {
    fail("refresh")
  }
  let selected = reading.select(test_document_id())
  let failed = selected.remote_failed(replica, attempt) catch {
    _ => abort("active refresh")
  }
  assert_true(failed.activity(replica) is Activity::Retryable(_))
  guard failed.advance(replica) is (_, Some(GetRemote(retry))) else {
    fail("refresh retry")
  }
  assert_true(retry != attempt)
}

///|
test "a selected refresh retry coalesces to the current catalog revision" {
  let account = test_account("account")
  let replica = @source_repository.DocumentReplica::receive(
    account,
    test_document("base"),
    revision(1.0),
  )
  let catalog = with_catalog(signed_in(account), account, [
    @source_repository.RemoteEntry::Present(
      test_document_id(),
      revision(2.0),
      "Remote",
    ),
  ])
  guard catalog.advance(replica) is (reading, Some(GetRemote(read))) else {
    fail("background read")
  }
  let failed = reading.remote_failed(replica, read) catch {
    _ => abort("active background read")
  }
  let current = with_catalog(failed, account, [
    @source_repository.RemoteEntry::Present(
      test_document_id(),
      revision(3.0),
      "Newest",
    ),
  ]).select(test_document_id())
  guard current.advance(replica) is (_, Some(GetRemote(retry))) &&
    retry.read is Refresh(required) else {
    fail("coalesced refresh")
  }
  assert_eq(required, revision(3.0))
}

///|
test "new intent and account lookup invalidate a failed open retry" {
  let account = test_account("account")
  let first_id = test_document_id(value="first")
  let second_id = test_document_id(value="second")
  let catalog = with_catalog(signed_in(account), account, [
    @source_repository.RemoteEntry::Present(first_id, revision(1.0), "First"),
    @source_repository.RemoteEntry::Present(second_id, revision(1.0), "Second"),
  ])
  guard catalog.select(first_id).advance_selection(None)
    is (fetching, SelectionStep::Fetch(attempt)) else {
    fail("first open")
  }
  let failed = fetching.open_failed(attempt) catch { _ => abort("active open") }
  guard failed.selection_activity() is SelectionActivity::Retryable(retry) else {
    fail("retryable open")
  }
  let selected = failed.select(second_id)
  let expired : Result[(State, Action), WorkError] = Ok(
    selected.retry_selection(retry),
  ) catch {
    error => Err(error)
  }
  assert_eq(expired, Err(WorkError::StaleWork))
  let resolving = failed.begin_lookup().0
  let expired : Result[(State, Action), WorkError] = Ok(
    resolving.retry_selection(retry),
  ) catch {
    error => Err(error)
  }
  assert_eq(expired, Err(WorkError::StaleWork))
  let cancelled = failed.cancel_selection()
  assert_true(cancelled.selection_activity() is SelectionActivity::Idle)
}

///|
test "a tombstone for an existing Replica uses the ordinary refresh lane" {
  let account = test_account("account")
  let replica = @source_repository.DocumentReplica::receive(
    account,
    test_document("base"),
    revision(1.0),
  )
  let entry = @source_repository.RemoteEntry::Present(
    test_document_id(),
    revision(2.0),
    "Remote",
  )
  let catalog = with_catalog(signed_in(account), account, [entry])
  let selected = catalog.select(test_document_id())
  guard selected.advance(replica) is (state, Some(GetRemote(attempt))) else {
    fail("refresh")
  }
  let tombstone = @source_repository.RemoteDocument::Deleted(revision(2.0))
  let (state, outcome) = state.received(replica, attempt, tombstone)
  guard outcome is Some(write) else { fail("tombstone persistence") }
  assert_eq(
    write.replica().directive(),
    @source_repository.ReplicaDirective::UpdateAvailable(tombstone),
  )
  assert_eq(state.selection(), None)
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
  guard state.advance(replica) is (state, Some(GetRemote(attempt))) &&
    attempt.read is Refresh(_) else {
    fail("revision fetch")
  }
  let state = state.remote_failed(replica, attempt) catch {
    _ => abort("active fetch")
  }
  assert_true(state.activity(replica) is Retryable(_))
  assert_true(
    state.advance(replica).1 is Some(GetRemote(retry_attempt)) &&
    retry_attempt.read is Refresh(retry) &&
    retry == revision(2.0),
  )
}

///|
test "a remote-read retry expires after its retried attempt fails" {
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
  guard state.advance(replica) is (state, Some(GetRemote(first))) else {
    fail("first read")
  }
  let state = state.remote_failed(replica, first) catch {
    _ => abort("first read")
  }
  guard state.activity(replica) is Retryable(first_retry) else {
    fail("first retry")
  }
  let (state, action) = state.retry(replica, first_retry) catch {
    _ => abort("current retry")
  }
  guard action is GetRemote(second) else { fail("second read") }
  let state = state.remote_failed(replica, second) catch {
    _ => abort("second read")
  }
  guard state.activity(replica) is Retryable(second_retry) else {
    fail("second retry")
  }
  let expired = try state.retry(replica, first_retry) catch {
    StaleWork => true
  } noraise {
    _ => false
  }
  assert_true(expired)
  assert_true(state.retry(replica, second_retry) is (_, GetRemote(_)))
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
    state.advance(available).1 is Some(GetRemote(attempt)) &&
    attempt.read is Refresh(expected) &&
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

///|
test "failed discovery retains catalog facts and exposes observation failure" {
  let account = test_account("account")
  let entry = @source_repository.RemoteEntry::Present(
    test_document_id(),
    revision(2.0),
    "Remote",
  )
  let observed = with_catalog(signed_in(account), account, [entry])
  let (refreshing, discovery) = observed.begin_discovery()
  assert_eq(refreshing.observation(), Observation::Observed)
  assert_true(refreshing.discovering())
  let (unavailable, accepted) = refreshing.discovered(
    account,
    discovery.unwrap(),
    None,
  )
  assert_true(accepted)
  assert_false(unavailable.discovering())
  assert_eq(unavailable.observation(), Observation::Unavailable)
  assert_eq(unavailable.remote_entry(test_document_id()), Some(entry))
}

///|
test "remote response is retained independently of catalog freshness" {
  let replica = sending_replica()
  let unknown = signed_in(replica.account())
  guard unknown.advance(replica) is (delivering, Some(Deliver(delivery, _))) else {
    fail("delivery")
  }
  let retrying = delivering.revision_conflict(replica, delivery) catch {
    _ => abort("active delivery")
  }
  guard retrying.advance(replica) is (fetching, Some(GetRemote(attempt))) else {
    fail("conflict fetch")
  }
  let remote = @source_repository.RemoteDocument::Present(
    revision(2.0),
    "Remote",
  )
  let (received, _) = fetching.received(replica, attempt, remote) catch {
    _ => abort("active fetch")
  }
  assert_eq(received.observation(), Observation::Unknown)
  assert_true(received.remote_entry(test_document_id()) is Some(_))
}
