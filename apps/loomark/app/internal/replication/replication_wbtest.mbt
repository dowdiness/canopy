///|
fn test_account() -> @source_repository.AccountId {
  @source_repository.AccountId::parse("account") catch {
    _ => abort("valid account")
  }
}

///|
fn test_document() -> @source_repository.Document {
  let id = @source_repository.DocumentId::parse(
    "10000000-0000-4000-8000-000000000001",
  ) catch {
    _ => abort("valid document id")
  }
  @source_repository.Document::create(id, "durable")
}

///|
fn test_protocol(account : @source_repository.AccountId) -> @sync.State {
  let (protocol, lookup) = @sync.State().begin_lookup() catch {
    _ => abort("initial lookup is available")
  }
  protocol.resolved(lookup, @sync.Resolved(account, "Writer")).0
}

///|
fn test_open_protocol(account : @source_repository.AccountId) -> @sync.State {
  let protocol = test_protocol(account)
  let (protocol, discovery) = protocol.begin_discovery()
  protocol.discovered(account, discovery.unwrap(), Some([remote_entry()])).0
}

///|
fn test_replica() -> @source_repository.DocumentReplica {
  @source_repository.DocumentReplica(test_account(), test_document())
}

///|
fn edited_write() -> @source_repository.ReplicaWrite {
  guard test_replica().edit("edited")
    is @source_repository.EditPlan::Persist(write) else {
    abort("edited replica")
  }
  write
}

///|
fn remote_entry() -> @source_repository.RemoteEntry {
  let revision = @source_repository.SavedRevision::parse(1.0) catch {
    _ => abort("valid revision")
  }
  @source_repository.RemoteEntry::Present(
    test_document().id(),
    revision,
    "Remote",
  )
}

///|
fn received_replica() -> @source_repository.DocumentReplica {
  let revision = @source_repository.SavedRevision::parse(1.0) catch {
    _ => abort("valid revision")
  }
  @source_repository.DocumentReplica::receive(
    test_account(),
    test_document(),
    revision,
  )
}

///|
fn edited_received_write() -> @source_repository.ReplicaWrite {
  guard received_replica().edit("edited")
    is @source_repository.EditPlan::Persist(write) else {
    abort("edited received replica")
  }
  write
}

///|
fn sending_replica() -> @source_repository.DocumentReplica {
  guard edited_received_write().replica().directive()
    is @source_repository.ReplicaDirective::CreateOperation(draft) else {
    abort("operation draft")
  }
  let operation = @source_repository.OperationId::parse(
    "20000000-0000-4000-8000-000000000001",
  ) catch {
    _ => abort("valid operation id")
  }
  draft.start(operation).replica()
}

///|
test "remote work cannot start before its replica write commits" {
  let account = test_account()
  let durable = test_replica()
  let saved = @source_repository.SavedDocuments::from_documents([])
    .unwrap()
    .apply_replica(durable)
  let state = State(protocol=test_protocol(account))
  let (state, effect) = state.submit(edited_write())
  guard effect is Some(Persist(attempt)) else { fail("persistence effect") }
  assert_eq(state.settle_replica(durable).1, None)

  let (state, completion) = state.complete(attempt, Ok(()))
  guard completion is @replica_persistence.Completion::Current(write) else {
    fail("current replica")
  }
  let saved = saved.apply_replica_write(write)
  let committed = saved.replica(account, test_document().id()).unwrap()
  guard state.settle_replica(committed).1
    is Some(Network(@sync.Action::CreateOperation(attempt))) else {
    fail("network effect")
  }
  assert_eq(attempt.account(), account)
  assert_eq(attempt.document_id(), test_document().id())
}

///|
test "a durable remote selection is taken exactly once" {
  let account = test_account()
  let durable = received_replica()
  let saved = @source_repository.SavedDocuments::from_documents([])
    .unwrap()
    .apply_replica(durable)
  let state = State(protocol=test_open_protocol(account))
  let (state, effects) = state.select(saved, test_document().id())
  assert_eq(effects, [])
  guard state.take_selection(saved) is (state, Some(opened), None) else {
    fail("durable open")
  }
  assert_eq(opened.replica(), durable)
  assert_eq(state.take_selection(saved).1, None)
}

///|
test "a remote selection cannot be taken from a busy Replica lane" {
  let account = test_account()
  let durable = received_replica()
  let saved = @source_repository.SavedDocuments::from_documents([])
    .unwrap()
    .apply_replica(durable)
  let state = State(protocol=test_open_protocol(account))
  let (state, effect) = state.submit(edited_received_write())
  guard effect is Some(Persist(attempt)) else { fail("persistence effect") }
  let (state, selected) = state.select(saved, test_document().id())
  assert_eq(selected, [])
  assert_eq(state.take_selection(saved).1, None)

  let (state, completion) = state.complete(attempt, Ok(()))
  guard completion is @replica_persistence.Completion::Current(write) else {
    fail("current write")
  }
  let saved = saved.apply_replica_write(write)
  let (state, _) = state.settle_replica(write.replica())
  guard state.take_selection(saved) is (_, Some(opened), _) else {
    fail("open after durable completion")
  }
  assert_eq(opened.replica(), write.replica())
}

///|
test "remote selection resumes ordinary sync after the matching commit" {
  let account = test_account()
  let durable = test_replica()
  let saved = @source_repository.SavedDocuments::from_documents([])
    .unwrap()
    .apply_replica(durable)
  let state = State(protocol=test_open_protocol(account))
  let (state, effect) = state.submit(edited_write())
  guard effect is Some(Persist(attempt)) else { fail("persistence effect") }
  let (state, selected) = state.select(saved, test_document().id())
  assert_eq(selected, [])

  let (state, _) = state.complete(attempt, Ok(()))
  guard state.settle_replica(attempt.write().replica()).1
    is Some(Network(@sync.GetRemote(open))) else {
    fail("ordinary sync")
  }
  assert_eq(open.account(), account)
  assert_eq(open.document_id(), test_document().id())
}

///|
test "remote selection retries failed Replica durability instead of reading" {
  let account = test_account()
  let durable = test_replica()
  let saved = @source_repository.SavedDocuments::from_documents([])
    .unwrap()
    .apply_replica(durable)
  let state = State(protocol=test_open_protocol(account))
  let (state, effect) = state.submit(edited_write())
  guard effect is Some(Persist(attempt)) else { fail("persistence effect") }
  let (state, _) = state.complete(
    attempt,
    Err(@source_repository.ReplicaFailure::StorageUnavailable),
  )
  guard state.select(saved, test_document().id()).1 is [Persist(_)] else {
    fail("durability retry")
  }
}

///|
test "remote open retry creates a fresh network attempt" {
  let account = test_account()
  let saved = @source_repository.SavedDocuments::from_documents([]).unwrap()
  let state = State(protocol=test_open_protocol(account))
  guard state.select(saved, test_document().id())
    is (state, [Network(@sync.OpenRemote(first))]) else {
    fail("first open")
  }
  let protocol = state.protocol().open_failed(first) catch {
      _ => abort("active open")
    }
  guard protocol.selection_activity()
    is @sync.SelectionActivity::Retryable(retry) else {
    fail("retryable open")
  }
  guard state.with_protocol(protocol).retry_selection(saved, retry)
    is (retrying, Network(@sync.OpenRemote(second))) else {
    fail("retried open")
  }
  assert_true(first != second)
  assert_true(
    retrying.protocol().selection_activity() is @sync.SelectionActivity::Working,
  )
}

///|
test "selection retains an earlier failed refresh" {
  let account = test_account()
  let durable = received_replica()
  let revision = @source_repository.SavedRevision::parse(2.0) catch {
    _ => abort("valid revision")
  }
  let (protocol, discovery) = test_protocol(account).begin_discovery()
  let protocol = protocol.discovered(
      account,
      discovery.unwrap(),
      Some([
        @source_repository.RemoteEntry::Present(
          test_document().id(),
          revision,
          "Remote",
        ),
      ]),
    ).0
  guard protocol.advance(durable)
    is (reading, Some(@sync.Action::GetRemote(read))) else {
    fail("background read")
  }
  let saved = @source_repository.SavedDocuments::from_documents([])
    .unwrap()
    .apply_replica(durable)
  let state = State(protocol=reading)
  let (selected, effects) = state.select(saved, test_document().id())
  assert_eq(effects, [])
  let failed = selected.protocol().remote_failed(durable, read) catch {
      _ => abort("active background read")
    }
  guard selected.with_protocol(failed).settle_replica(durable)
    is (_, Some(Network(@sync.GetRemote(open)))) else {
    fail("refresh retry")
  }
  assert_eq(open.account(), account)
  assert_eq(open.document_id(), test_document().id())
}

///|
test "selection rejects a refresh response older than the current catalog" {
  let account = test_account()
  let durable = received_replica()
  let revision = @source_repository.SavedRevision::parse(2.0) catch {
    _ => abort("valid revision")
  }
  let (protocol, discovery) = test_protocol(account).begin_discovery()
  let protocol = protocol.discovered(
      account,
      discovery.unwrap(),
      Some([
        @source_repository.RemoteEntry::Present(
          test_document().id(),
          revision,
          "Remote",
        ),
      ]),
    ).0
  let saved = @source_repository.SavedDocuments::from_documents([])
    .unwrap()
    .apply_replica(durable)
  let state = State(protocol~)
  guard state.select(saved, test_document().id())
    is (opening, [Network(@sync.GetRemote(attempt))]) else {
    fail("selected refresh")
  }
  let stale = @source_repository.RemoteDocument::Present(
    @source_repository.SavedRevision::parse(1.0) catch {
      _ => abort("valid revision")
    },
    "durable",
  )
  let rejected = try opening.receive_remote(durable, attempt, stale) catch {
    @sync.WorkError::StaleWork => true
  } noraise {
    _ => false
  }
  assert_true(rejected)
}

///|
test "remote refresh response from an old account persists without new network work" {
  let durable = received_replica()
  let revision = @source_repository.SavedRevision::parse(2.0)
  let (protocol, discovery) = test_protocol(durable.account()).begin_discovery()
  let protocol = protocol.discovered(
      durable.account(),
      discovery.unwrap(),
      Some([
        @source_repository.RemoteEntry::Present(
          durable.document_id(),
          revision,
          "Remote",
        ),
      ]),
    ).0
  guard protocol.advance(durable)
    is (protocol, Some(@sync.Action::GetRemote(read))) else {
    fail("refresh read")
  }
  let (protocol, lookup) = protocol.begin_lookup() catch {
    _ => abort("lookup available")
  }
  let other = @source_repository.AccountId::parse("other") catch {
    _ => abort("valid account")
  }
  let protocol = protocol.resolved(lookup, @sync.Resolved(other, "Other")).0
  let state = State(protocol~)
  let remote = @source_repository.RemoteDocument::Present(revision, "remote")
  let (state, effect) = state.receive_remote(durable, read, remote)
  guard effect is Some(Persist(attempt)) else { fail("old account write") }
  let (state, completion) = state.complete(attempt, Ok(()))
  guard completion is @replica_persistence.Completion::Current(write) else {
    fail("old account write committed")
  }
  assert_eq(write.replica().account(), durable.account())
  assert_eq(write.replica().remote_update().unwrap().remote(), remote)
  assert_eq(state.settle_replica(write.replica()).1, None)
}

///|
test "replacing a selection starts only the new remote-only fetch" {
  let account = test_account()
  let durable = received_replica()
  let second = @source_repository.DocumentId::parse(
    "10000000-0000-4000-8000-000000000002",
  ) catch {
    _ => abort("valid document id")
  }
  let revision1 = @source_repository.SavedRevision::parse(1.0) catch {
    _ => abort("valid revision")
  }
  let revision2 = @source_repository.SavedRevision::parse(2.0) catch {
    _ => abort("valid revision")
  }
  let (protocol, discovery) = test_protocol(account).begin_discovery()
  let protocol = protocol.discovered(
      account,
      discovery.unwrap(),
      Some([
        @source_repository.RemoteEntry::Present(
          test_document().id(),
          revision1,
          "First",
        ),
        @source_repository.RemoteEntry::Present(second, revision1, "Second"),
      ]),
    ).0
  let saved = @source_repository.SavedDocuments::from_documents([])
    .unwrap()
    .apply_replica(durable)
  let (selected, effects) = State(protocol~).select(saved, test_document().id())
  assert_eq(effects, [])
  let (protocol, discovery) = selected.protocol().begin_discovery()
  let protocol = protocol.discovered(
      account,
      discovery.unwrap(),
      Some([
        @source_repository.RemoteEntry::Present(
          test_document().id(),
          revision2,
          "First",
        ),
        @source_repository.RemoteEntry::Present(second, revision1, "Second"),
      ]),
    ).0
  guard selected.with_protocol(protocol).select(saved, second)
    is (_, [Network(@sync.OpenRemote(opened))]) else {
    fail("new selection")
  }
  assert_eq(opened.document_id(), second)
}

///|
test "account switch cannot release a selected GET for the previous account" {
  let account = test_account()
  let durable = test_replica()
  let saved = @source_repository.SavedDocuments::from_documents([])
    .unwrap()
    .apply_replica(durable)
  let state = State(protocol=test_open_protocol(account))
  let (state, effect) = state.submit(edited_write())
  guard effect is Some(Persist(attempt)) else { fail("persistence effect") }
  let (state, selected) = state.select(saved, test_document().id())
  assert_eq(selected, [])
  let (protocol, lookup) = state.protocol().begin_lookup()
  let other = @source_repository.AccountId::parse("other") catch {
    _ => abort("valid other account")
  }
  let protocol = protocol.resolved(
      lookup,
      @sync.AccountResult::Resolved(other, "Other"),
    ).0
  let (state, _) = state.with_protocol(protocol).complete(attempt, Ok(()))
  assert_eq(state.settle_replica(attempt.write().replica()).1, None)
}

///|
test "account resume retries durability without also starting network work" {
  let account = test_account()
  let durable = test_replica()
  let saved = @source_repository.SavedDocuments::from_documents([])
    .unwrap()
    .apply_replica(durable)
  let state = State(protocol=test_protocol(account))
  let (state, effect) = state.submit(edited_write())
  guard effect is Some(Persist(attempt)) else { fail("persistence effect") }
  let (state, _) = state.complete(
    attempt,
    Err(@source_repository.ReplicaFailure::StorageUnavailable),
  )
  let (state, effects) = state.resume_account(saved, account)
  guard effects is [Persist(_)] else { fail("durability retry only") }
  assert_true(
    state.status(account, test_document().id())
    is @replica_persistence.Status::Persisting,
  )
}

///|
test "network retry is consumed against the authoritative durable replica" {
  let replica = sending_replica()
  let protocol = test_protocol(replica.account())
  guard protocol.advance(replica)
    is (delivering, Some(@sync.Action::Deliver(attempt, operation))) else {
    fail("delivery")
  }
  let retryable = delivering.delivery_failed(replica, attempt) catch {
    _ => abort("active delivery")
  }
  guard retryable.activity(replica) is @sync.Activity::Retryable(retry) else {
    fail("retry capability")
  }
  let saved = @source_repository.SavedDocuments::from_documents([])
    .unwrap()
    .apply_replica(replica)
  let state = State(protocol=retryable)
  guard state.retry_sync(saved, retry)
    is (retried, Effect::Network(@sync.Action::Deliver(_, resent))) else {
    fail("retry delivery")
  }
  assert_eq(resent.operation_id(), operation.operation_id())
  let expired = try retried.retry_sync(saved, retry) catch {
    ExpiredRetry => true
  } noraise {
    _ => false
  }
  assert_true(expired)
}

///|
test "selection does not block a network retry" {
  let replica = sending_replica()
  let protocol = test_open_protocol(replica.account())
  guard protocol.advance(replica)
    is (delivering, Some(@sync.Action::Deliver(attempt, original))) else {
    fail("delivery")
  }
  let failed = delivering.delivery_failed(replica, attempt) catch {
    _ => abort("active delivery")
  }
  guard failed.activity(replica) is @sync.Activity::Retryable(retry) else {
    fail("retry capability")
  }
  let saved = @source_repository.SavedDocuments::from_documents([])
    .unwrap()
    .apply_replica(replica)
  let state = State(protocol=failed)
  let (selected, effects) = state.select(saved, replica.document_id())
  guard effects is [Network(@sync.Deliver(_, operation))] else {
    fail("automatic delivery retry")
  }
  assert_eq(operation.operation_id(), original.operation_id())
  let expired = try selected.retry_sync(saved, retry) catch {
    ExpiredRetry => true
  } noraise {
    _ => false
  }
  assert_true(expired)
}

///|
test "save_local replaces obsolete failed text even when replacement also fails" {
  let durable = test_replica()
  let (state, effect) = State().submit(edited_write())
  guard effect is Some(Persist(old)) else { fail("first write") }
  let (state, _) = state.complete(old, Err(@source_repository.WriteFailed))
  guard state.status(durable.account(), durable.document_id())
    is @replica_persistence.Retryable(old_retry, _) else {
    fail("failed write")
  }
  let (state, effect) = state.save_local(durable, "durable")
  guard effect is Some(Persist(replacement)) else { fail("replacement write") }
  let expired = try state.retry_save(old_retry) catch {
    ExpiredRetry => true
  } noraise {
    _ => false
  }
  assert_true(expired)
  let (state, completion) = state.complete(
    replacement,
    Err(@source_repository.WriteFailed),
  )
  guard completion is @replica_persistence.Retryable(_, retry, _) else {
    fail("replacement can retry")
  }
  let (state, effect) = state.retry_save(retry)
  guard effect is Persist(attempt) else { fail("local retry") }
  let (state, completion) = state.complete(attempt, Ok(()))
  guard completion is @replica_persistence.Current(write) else {
    fail("latest text committed")
  }
  let saved = @source_repository.SavedDocuments::from_documents([])
    .unwrap()
    .apply_replica(durable)
    .apply_replica_write(write)
  assert_eq(
    saved
    .replica(durable.account(), durable.document_id())
    .unwrap()
    .document()
    .unwrap()
    .text(),
    "durable",
  )
  assert_true(
    state.status(durable.account(), durable.document_id())
    is @replica_persistence.Current,
  )
}

///|
test "save_local retries matching failed acknowledgment without losing its baseline" {
  let durable = sending_replica()
  guard durable.directive() is @source_repository.Send(operation) else {
    fail("pending delivery")
  }
  let revision = @source_repository.SavedRevision::parse(2.0)
  let acknowledged = durable.acknowledge(operation.operation_id(), revision)
  let (state, effect) = State().submit(acknowledged)
  guard effect is Some(Persist(attempt)) else { fail("receipt write") }
  let (state, _) = state.complete(attempt, Err(@source_repository.WriteFailed))
  let (state, effect) = state.save_local(durable, "edited")
  guard effect is Some(Persist(retry)) else { fail("receipt retry") }
  let (_, completion) = state.complete(retry, Ok(()))
  guard completion is @replica_persistence.Current(write) else {
    fail("receipt committed")
  }
  assert_eq(write.replica().baseline_revision(), 2.0)
  assert_eq(write.replica().directive(), @source_repository.Synchronized)
  assert_eq(write.replica().document().unwrap().text(), "edited")
}

///|
test "save_local returning to durable text queues behind an in-flight edit" {
  let durable = test_replica()
  let (state, effect) = State().submit(edited_write())
  guard effect is Some(Persist(first)) else { fail("first write") }
  let (state, effect) = state.save_local(durable, "durable")
  assert_eq(effect, None)
  let (state, completion) = state.complete(first, Ok(()))
  guard completion is @replica_persistence.Superseded(older, next) else {
    fail("return to durable text remains queued")
  }
  let saved = @source_repository.SavedDocuments::from_documents([])
    .unwrap()
    .apply_replica(durable)
    .apply_replica_write(older)
  let (_, completion) = state.complete(next, Ok(()))
  guard completion is @replica_persistence.Current(write) else {
    fail("latest text committed after older write")
  }
  assert_eq(
    saved
    .apply_replica_write(write)
    .replica(durable.account(), durable.document_id())
    .unwrap()
    .document()
    .unwrap()
    .text(),
    "durable",
  )
}

///|
test "save_local unchanged text does not replace a failed atomic recovery" {
  let replica = edited_received_write().replica()
  let revision = @source_repository.SavedRevision::parse(2.0)
  guard replica.reconcile(
      @source_repository.RemoteDocument::Present(revision, "remote"),
    )
    is @source_repository.ReconcilePlan::Persist(diverged) else {
    fail("divergence")
  }
  let durable = diverged.replica()
  let recovery_id = @source_repository.DocumentId::parse(
    "30000000-0000-4000-8000-000000000001",
  )
  let fork = durable.fork(recovery_id)
  let (state, effect) = State().submit(fork)
  guard effect is Some(Persist(attempt)) else { fail("atomic fork") }
  let (state, _) = state.complete(attempt, Err(@source_repository.WriteFailed))
  let (state, effect) = state.save_local(durable, "edited")
  assert_eq(effect, None)
  let (state, effect) = state.retry_document(
    durable.account(),
    durable.document_id(),
  )
  guard effect is Some(Persist(retry)) else { fail("fork retry") }
  let (_, completion) = state.complete(retry, Ok(()))
  guard completion is @replica_persistence.Current(write) else {
    fail("atomic recovery committed")
  }
  let saved = @source_repository.SavedDocuments::from_documents([])
    .unwrap()
    .apply_replica(durable)
    .apply_replica_write(write)
  assert_eq(saved.find(recovery_id).unwrap().text(), "edited")
  assert_eq(
    saved
    .replica(durable.account(), durable.document_id())
    .unwrap()
    .document()
    .unwrap()
    .text(),
    "remote",
  )
}

///|
test "delivery receipt follows the newest queued edit without early network work" {
  let durable = sending_replica()
  guard test_protocol(durable.account()).advance(durable)
    is (protocol, Some(@sync.Action::Deliver(delivery, _))) else {
    fail("delivery")
  }
  guard durable.edit("latest") is @source_repository.EditPlan::Persist(newer) else {
    fail("newer edit")
  }
  let (state, effect) = State(protocol~).submit(newer)
  guard effect is Some(Persist(first)) else { fail("first write") }
  let revision = @source_repository.SavedRevision::parse(2.0)
  let (state, effect) = state.acknowledge_delivery(durable, delivery, revision)
  assert_eq(effect, None)
  guard state.complete(first, Ok(()))
    is (state, @replica_persistence.Superseded(_, next)) else {
    fail("receipt waits behind newer edit")
  }
  let (state, completion) = state.complete(next, Ok(()))
  guard completion is @replica_persistence.Completion::Current(write) else {
    fail("receipt committed")
  }
  assert_eq(write.replica().baseline_revision(), 2.0)
  assert_eq(write.replica().document().unwrap().text(), "latest")
  assert_true(
    state.status(durable.account(), durable.document_id())
    is @replica_persistence.Status::Current,
  )
}

///|
test "remote refresh remains pending until its replica write commits" {
  let durable = received_replica()
  let saved = @source_repository.SavedDocuments::from_documents([])
    .unwrap()
    .apply_replica(durable)
  let revision = @source_repository.SavedRevision::parse(2.0)
  let (protocol, discovery) = test_protocol(durable.account()).begin_discovery()
  let protocol = protocol.discovered(
      durable.account(),
      discovery.unwrap(),
      Some([
        @source_repository.RemoteEntry::Present(
          durable.document_id(),
          revision,
          "Remote",
        ),
      ]),
    ).0
  guard protocol.advance(durable)
    is (protocol, Some(@sync.Action::GetRemote(read))) else {
    fail("refresh read")
  }
  let state = State(protocol~)
  let remote = @source_repository.RemoteDocument::Present(revision, "remote")
  let (state, effect) = state.receive_remote(durable, read, remote)
  guard effect is Some(Persist(attempt)) else { fail("reconciled write") }
  assert_eq(attempt.write().replica().document().unwrap().text(), "durable")
  assert_eq(attempt.write().replica().remote_update().unwrap().remote(), remote)
  assert_eq(
    saved
    .replica(durable.account(), durable.document_id())
    .unwrap()
    .remote_update(),
    None,
  )
  assert_eq(state.settle_replica(durable).1, None)
  let (state, completion) = state.complete(attempt, Ok(()))
  guard completion is @replica_persistence.Completion::Current(write) else {
    fail("remote observation committed")
  }
  let committed = saved
    .apply_replica_write(write)
    .replica(durable.account(), durable.document_id())
    .unwrap()
  assert_eq(committed.document().unwrap().text(), "durable")
  assert_eq(committed.remote_update().unwrap().remote(), remote)
  assert_true(
    state.status(durable.account(), durable.document_id())
    is @replica_persistence.Status::Current,
  )
}

///|
test "remote refresh queues behind an in-flight edit without losing local text" {
  let durable = received_replica()
  let revision = @source_repository.SavedRevision::parse(2.0)
  let (protocol, discovery) = test_protocol(durable.account()).begin_discovery()
  let protocol = protocol.discovered(
      durable.account(),
      discovery.unwrap(),
      Some([
        @source_repository.RemoteEntry::Present(
          durable.document_id(),
          revision,
          "Remote",
        ),
      ]),
    ).0
  guard protocol.advance(durable)
    is (protocol, Some(@sync.Action::GetRemote(read))) else {
    fail("refresh read")
  }
  let (state, effect) = State(protocol~).save_local(durable, "latest")
  guard effect is Some(Persist(first)) else { fail("local edit write") }
  let remote = @source_repository.RemoteDocument::Present(revision, "remote")
  let (state, effect) = state.receive_remote(durable, read, remote)
  assert_eq(effect, None)
  assert_eq(state.settle_replica(durable).1, None)
  guard state.complete(first, Ok(()))
    is (state, @replica_persistence.Superseded(_, next)) else {
    fail("remote observation waits behind local edit")
  }
  assert_eq(next.write().replica().document().unwrap().text(), "latest")
  let (state, completion) = state.complete(next, Ok(()))
  guard completion is @replica_persistence.Completion::Current(write) else {
    fail("remote observation committed")
  }
  assert_eq(write.replica().document().unwrap().text(), "latest")
  assert_eq(write.replica().observed_revision(), 2.0)
  assert_true(
    state.status(durable.account(), durable.document_id())
    is @replica_persistence.Status::Current,
  )
}
