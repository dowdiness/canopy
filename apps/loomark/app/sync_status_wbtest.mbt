///|
fn status_sync(account : @source_repository.AccountId) -> @sync.State {
  let (sync, lookup) = @sync.State().begin_lookup()
  sync.resolved(lookup, @sync.AccountResult::Resolved(account, "Writer")).0
}

///|
fn status_revision(value : Double) -> @source_repository.SavedRevision {
  @source_repository.SavedRevision::parse(value) catch {
    _ => abort("valid test revision")
  }
}

///|
fn sync_start_action(
  model : Model,
  account : @source_repository.AccountId,
) -> @documents.StartSync {
  guard model.page is Editing(editing) &&
    editing.documents.sync_start(editing.activation.key, account)
    is @documents.SyncStart::Ready(action) else {
    abort("sync start available")
  }
  action
}

///|
fn status_model(
  replica : @source_repository.DocumentReplica,
  sync : @sync.State,
) -> Model {
  let saved = @source_repository.SavedDocuments::from_documents([]).unwrap()
  let saved = saved.apply_replica(replica) catch {
    _ => abort("valid test replica")
  }
  let documents = @documents.State::State(saved).project_account(
    replica.account(),
  )
  test_model(
    Editing({
      ..test_editing(),
      activation: {
        key: @documents.Key::replica(replica.account(), replica.document_id()),
        generation: 0,
      },
      documents,
    }),
    sync,
  )
}

///|
test "account status is a narrow projection of the session" {
  let account = sync_test_account("account")
  assert_true(account_status(@sync.State()) == AccountStatus::Unavailable)
  let (checking, _) = @sync.State().begin_lookup()
  assert_true(account_status(checking) == AccountStatus::Checking)
  let current = status_sync(account)
  assert_true(account_status(current) == AccountStatus::SignedIn("Writer"))
}

///|
test "local document status exposes sign-in and sync-start states" {
  let signed_out = test_model(Editing(test_editing()), @sync.State())
  let (sync, lookup) = signed_out.sync().begin_lookup()
  let signed_out = signed_out.with_sync(
    sync.resolved(lookup, @sync.AccountResult::SignedOut).0,
  )
  assert_true(document_sync_status(signed_out) == Some(SignInRequired))

  let account = sync_test_account("account")
  let signed_in = signed_out.with_sync(status_sync(account))
  guard document_sync_status(signed_in) is Some(ReadyToSync(action)) else {
    fail("ready to sync")
  }
  assert_eq(action.account(), account)
  assert_eq(action.document_id(), document_id("one"))

  guard signed_in.page is Editing(editing) else { fail("editing") }
  let (documents, _) = editing.documents.reduce(
    @documents.Msg::New(document_id("new")),
  )
  let ephemeral = {
    ..signed_in,
    page: Editing({
      ..editing,
      activation: { key: source_key("new"), generation: 1, },
      documents,
    }),
  }
  assert_true(document_sync_status(ephemeral) == Some(SavedOnDevice))
}

///|
test "replica status combines durable directive with transient progress" {
  let account = sync_test_account("account")
  let document = documents_test_document("one", "one")
  let synchronized = @source_repository.DocumentReplica::receive(
    account,
    document,
    status_revision(1.0),
  )
  let idle = status_sync(account)
  assert_true(
    document_sync_status(status_model(synchronized, idle)) == Some(Synced),
  )

  guard synchronized.directive()
    is @source_repository.ReplicaDirective::Synchronized else {
    fail("synchronized replica")
  }
  let edited = synchronized.edit("edited")
  guard edited is @source_repository.EditPlan::Persist(write) else {
    fail("edited replica")
  }
  let (persistence, attempt) = @replica_persistence.State().submit(write)
  let attempt = attempt.unwrap()
  let (persistence, _) = persistence.complete(
    attempt,
    Err(@source_repository.ReplicaFailure::StorageUnavailable),
  )
  let model = {
    ..status_model(synchronized, idle),
    replication: @replication.State(protocol=idle, persistence~),
  }
  guard document_sync_status(model) is Some(RetryAvailable(RetryPersistence(_))) else {
    fail("retry available")
  }

  let (persisting, _) = @replica_persistence.State().submit(write)
  assert_true(
    document_sync_status({
      ..status_model(synchronized, idle),
      replication: @replication.State(protocol=idle, persistence=persisting),
    }) ==
    Some(SavingOnDevice),
  )
}

///|
test "retry messages restart only their owned lifecycle" {
  let account = sync_test_account("account")
  let document = documents_test_document("one", "one")
  let synchronized = @source_repository.DocumentReplica::receive(
    account,
    document,
    status_revision(1.0),
  )
  guard synchronized.edit("edited")
    is @source_repository.EditPlan::Persist(write) else {
    fail("edited replica")
  }
  let (persistence, attempt) = @replica_persistence.State().submit(write)
  let (persistence, _) = persistence.complete(
    attempt.unwrap(),
    Err(@source_repository.ReplicaFailure::StorageUnavailable),
  )
  let model = {
    ..status_model(synchronized, status_sync(account)),
    replication: @replication.State(protocol=status_sync(account), persistence~),
  }
  guard document_sync_status(model) is Some(RetryAvailable(action)) else {
    fail("retry available")
  }
  let (retrying, _) = test_root_update(model, RetrySync(action))
  assert_true(
    retrying.replication.status(account, document.id())
    is @replica_persistence.Persisting,
  )
  let (expired, _) = test_root_update(retrying, RetrySync(action))
  assert_true(expired == retrying)

  let unavailable = model.with_sync(@sync.State())
  let (checking, _) = test_root_update(unavailable, RetryAccount)
  assert_true(account_status(checking.sync()) == AccountStatus::Checking)
}

///|
test "sync start preserves editor activation and starts replica sync" {
  let account = sync_test_account("account")
  let initial = test_model(Editing(test_editing()), status_sync(account))
  let key = source_key("one")
  guard initial.page is Editing(before) else { fail("editing") }
  let document = before.documents.document(key).unwrap()
  let (starting, _) = test_root_update(
    initial,
    StartSync(sync_start_action(initial, account)),
  )
  guard starting.page is Editing(during) else { fail("editing") }
  assert_true(during.documents.sync_start(key, account) is @documents.Starting)
  assert_true(during.activation == before.activation)
  assert_true(document_sync_status(starting) == Some(WaitingToSync))

  let replica = @source_repository.DocumentReplica(account, document)
  let (_, attempt) = initial.replication
    .persistence()
    .submit(replica.promote_source())
  let (completed, _) = test_root_update(
    starting,
    Sync(ReplicaWriteCompleted(attempt.unwrap(), Ok(()))),
  )
  guard completed.page is Editing(after) else { fail("editing") }
  assert_eq(after.activation.generation, before.activation.generation)
  assert_true(
    after.activation.key == @documents.Key::replica(account, document.id()),
  )
  assert_eq(after.documents.text(after.activation.key), Some(document.text()))
  assert_true(completed.sync().progress(replica) is @sync.Progress::Working)
}

///|
test "native callbacks keep their activation across sync-start rekeying" {
  let account = sync_test_account("account")
  let initial = test_model(Editing(test_editing()), status_sync(account))
  guard initial.page is Editing(before) else { fail("editing") }
  let document = before.documents.document(source_key("one")).unwrap()
  let (starting, _) = test_root_update(
    initial,
    StartSync(sync_start_action(initial, account)),
  )
  let (composing, _) = test_root_update(starting, CompositionStarted(0))
  let replica = @source_repository.DocumentReplica(account, document)
  let (_, attempt) = initial.replication
    .persistence()
    .submit(replica.promote_source())
  let (rekeyed, _) = test_root_update(
    composing,
    Sync(ReplicaWriteCompleted(attempt.unwrap(), Ok(()))),
  )
  let (changed, _) = test_root_update(
    rekeyed,
    TextChanged(0, @text_change.TextChange::ReplaceAll("composed")),
  )
  let (ended, _) = test_root_update(changed, CompositionEnded(0))
  guard ended.page is Editing(after) else { fail("editing") }
  assert_eq(after.activation.generation, 0)
  assert_eq(after.documents.text(after.activation.key), Some("composed"))
  assert_false(after.documents.is_composing(after.activation.key))
}

///|
test "account switch does not redirect an in-flight sync start" {
  let account_a = sync_test_account("account-a")
  let account_b = sync_test_account("account-b")
  let initial = test_model(Editing(test_editing()), status_sync(account_a))
  guard initial.page is Editing(before) else { fail("editing") }
  let document = before.documents.document(source_key("one")).unwrap()
  let (starting, _) = test_root_update(
    initial,
    StartSync(sync_start_action(initial, account_a)),
  )
  let (sync, lookup) = starting.sync().begin_lookup()
  let (switched, _) = test_root_update(
    starting.with_sync(sync),
    Sync(AccountResolved(lookup, @sync.Resolved(account_b, "B"))),
  )
  let replica = @source_repository.DocumentReplica(account_a, document)
  let (_, attempt) = initial.replication
    .persistence()
    .submit(replica.promote_source())
  let (completed, _) = test_root_update(
    switched,
    Sync(ReplicaWriteCompleted(attempt.unwrap(), Ok(()))),
  )
  assert_true(
    completed.sync().session() is @sync.Session::Current(current, _) &&
    current == account_b,
  )
  assert_true(completed.sync().progress(replica) is @sync.Progress::Inactive)
  guard completed.page is Editing(after) else { fail("editing") }
  assert_true(
    after.activation.key == @documents.Key::replica(account_a, document.id()),
  )
  assert_true(document_sync_status(completed) == Some(SavedOnDevice))
}
