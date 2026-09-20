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
  let (protocol, lookup) = @sync.State().begin_lookup()
  protocol.resolved(lookup, @sync.Resolved(account, "Writer")).0
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
    is Some(Network(@sync.Action::CreateOperation(_, owner, document_id))) else {
    fail("network effect")
  }
  assert_eq(owner, account)
  assert_eq(document_id, test_document().id())
}

///|
test "remote selection is released by the matching Replica commit" {
  let account = test_account()
  let durable = test_replica()
  let state = State(protocol=test_protocol(account))
  let (state, effect) = state.submit(edited_write())
  guard effect is Some(Persist(attempt)) else { fail("persistence effect") }
  let (state, selected) = state.select(remote_entry(), Some(durable))
  assert_eq(selected, None)

  let (state, _) = state.complete(attempt, Ok(()))
  guard state.settle_replica(attempt.write().replica()).1
    is Some(Network(@sync.GetRemote(_, owner, document_id, @sync.Open(_, _)))) else {
    fail("remote open")
  }
  assert_eq(owner, account)
  assert_eq(document_id, test_document().id())
}

///|
test "remote selection retries failed Replica durability instead of reading" {
  let account = test_account()
  let durable = test_replica()
  let state = State(protocol=test_protocol(account))
  let (state, effect) = state.submit(edited_write())
  guard effect is Some(Persist(attempt)) else { fail("persistence effect") }
  let (state, _) = state.complete(
    attempt,
    Err(@source_repository.ReplicaFailure::StorageUnavailable),
  )
  guard state.select(remote_entry(), Some(durable)).1 is Some(Persist(_)) else {
    fail("durability retry")
  }
}

///|
test "account switch cannot release a selected GET for the previous account" {
  let account = test_account()
  let durable = test_replica()
  let state = State(protocol=test_protocol(account))
  let (state, effect) = state.submit(edited_write())
  guard effect is Some(Persist(attempt)) else { fail("persistence effect") }
  let (state, selected) = state.select(remote_entry(), Some(durable))
  assert_eq(selected, None)
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
