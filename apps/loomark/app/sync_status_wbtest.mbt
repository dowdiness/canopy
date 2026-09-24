///|
priv struct DocumentSyncView {
  durability : LocalDurability
  persistence : @replica_persistence.Status?
  sync : DocumentSync
  remote : @documents.RemoteState?
  activity : @sync.Activity?
}

///|
fn document_sync_view(model : Model) -> DocumentSyncView? {
  guard document_durability(model) is Some(durability) &&
    document_sync(model) is Some(sync) else {
    return None
  }
  Some({
    durability,
    persistence: document_replica_persistence(model),
    sync,
    remote: document_remote_state(model),
    activity: document_sync_activity(model),
  })
}

///|
fn status_sync(account : @source_repository.AccountId) -> @sync.State {
  let (sync, lookup) = @sync.State().begin_lookup() catch {
    _ => abort("lookup should be available")
  }
  sync.resolved(lookup, @sync.AccountResult::Resolved(account, "Writer")).0
}

///|
fn status_sync_with_catalog(
  account : @source_repository.AccountId,
  entry : @source_repository.RemoteEntry,
) -> @sync.State {
  let current = status_sync(account)
  let (discovering, discovery) = current.begin_discovery()
  discovering.discovered(account, discovery.unwrap(), Some([entry])).0
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
priv struct TestLinkedSync {
  remote : @documents.RemoteState
  activity : @sync.Activity
}

///|
fn linked_status(view : DocumentSyncView) -> TestLinkedSync {
  guard view.sync is DocumentSync::Linked &&
    view.remote is Some(remote) &&
    view.activity is Some(activity) else {
    abort("linked document sync view")
  }
  { remote, activity, }
}

///|
test "account status is a narrow projection of the session" {
  let account = sync_test_account("account")
  assert_true(account_status(@sync.State()) == AccountStatus::Unavailable)
  let (checking, _) = @sync.State().begin_lookup()
  assert_true(account_status(checking) == AccountStatus::Checking)
  let current = status_sync(account)
  assert_true(account_status(current) == AccountStatus::SignedIn("Writer"))
  let (refreshing, discovery) = current.begin_discovery()
  let unavailable = refreshing.discovered(account, discovery.unwrap(), None).0
  assert_true(account_status(unavailable) == AccountStatus::SyncUnavailable)
}

///|
test "local document status exposes sign-in and sync-start states" {
  let signed_out = test_model(Editing(test_editing()), @sync.State())
  let (sync, lookup) = signed_out.sync().begin_lookup()
  let signed_out = signed_out.with_sync(
    sync.resolved(lookup, @sync.AccountResult::SignedOut).0,
  )
  guard document_sync_view(signed_out) is Some(signed_out_view) else {
    fail("signed-out document sync view")
  }
  assert_true(signed_out_view.durability is LocalDurability::Stored)
  assert_true(signed_out_view.sync is DocumentSync::DeviceOnly)

  let account = sync_test_account("account")
  let signed_in = signed_out.with_sync(status_sync(account))
  guard document_sync_view(signed_in) is Some(signed_in_view) &&
    signed_in_view.sync is DocumentSync::SyncAvailable(action) else {
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
  guard document_sync_view(ephemeral) is Some(ephemeral_view) else {
    fail("ephemeral document sync view")
  }
  assert_true(ephemeral_view.durability is LocalDurability::Stored)
  assert_true(ephemeral_view.sync is DocumentSync::DeviceOnly)
}

///|
test "replica status keeps local durability separate from transfer" {
  let account = sync_test_account("account")
  let document = documents_test_document("one", "one")
  let synchronized = @source_repository.DocumentReplica::receive(
    account,
    document,
    status_revision(1.0),
  )
  let idle = status_sync(account)
  guard document_sync_view(status_model(synchronized, idle))
    is Some(synchronized_view) else {
    fail("synchronized document sync view")
  }
  assert_true(synchronized_view.durability is LocalDurability::Stored)
  let synchronized_status = linked_status(synchronized_view)
  assert_true(synchronized_status.remote is @documents.RemoteState::Current)
  assert_true(
    synchronized_view.persistence is Some(@replica_persistence.Status::Current),
  )
  assert_true(synchronized_status.activity is @sync.Activity::Idle)

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
  guard document_sync_view(model) is Some(failed_view) else {
    fail("failed document sync view")
  }
  assert_true(failed_view.durability is LocalDurability::Stored)
  let failed_status = linked_status(failed_view)
  assert_true(failed_status.remote is @documents.RemoteState::Current)
  assert_true(
    failed_view.persistence
    is Some(@replica_persistence.Status::Retryable(_, _)),
  )
  assert_true(failed_status.activity is @sync.Activity::Idle)

  let (persisting, _) = @replica_persistence.State().submit(write)
  let persisting_model = {
    ..status_model(synchronized, idle),
    replication: @replication.State(protocol=idle, persistence=persisting),
  }
  guard document_sync_view(persisting_model) is Some(persisting_view) else {
    fail("persisting document sync view")
  }
  assert_true(persisting_view.durability is LocalDurability::Stored)
  let persisting_status = linked_status(persisting_view)
  assert_true(persisting_status.remote is @documents.RemoteState::Current)
  assert_true(
    persisting_view.persistence is Some(@replica_persistence.Status::Persisting),
  )
  assert_true(persisting_status.activity is @sync.Activity::Idle)
}

///|
test "tombstone candidates cannot report visible text as synchronized" {
  let account = sync_test_account("account")
  let document = documents_test_document("one", "base")
  let synchronized = @source_repository.DocumentReplica::receive(
    account,
    document,
    status_revision(1.0),
  )
  guard synchronized.reconcile(
      @source_repository.RemoteDocument::Deleted(status_revision(2.0)),
    )
    is @source_repository.ReconcilePlan::Persist(observed_write) else {
    fail("remote deletion")
  }
  let observed = observed_write.replica()
  let deletion = observed.request_deletion() catch {
    _ => abort("available deletion")
  }
  assert_true(deletion.replica().is_deleted())
  let (persistence, attempt) = @replica_persistence.State().submit(deletion)
  let pending = {
    ..status_model(observed, status_sync(account)),
    replication: @replication.State(protocol=status_sync(account), persistence~),
  }
  guard document_sync_view(pending) is Some(pending_view) else {
    fail("pending tombstone view")
  }
  let pending_status = linked_status(pending_view)
  assert_true(pending_status.remote is @documents.RemoteState::Unavailable)
  assert_true(
    pending_view.persistence is Some(@replica_persistence.Status::Persisting),
  )

  let (persistence, _) = persistence.complete(
    attempt.unwrap(),
    Err(@source_repository.ReplicaFailure::StorageUnavailable),
  )
  let failed = {
    ..pending,
    replication: @replication.State(protocol=status_sync(account), persistence~),
  }
  guard document_sync_view(failed) is Some(failed_view) else {
    fail("failed tombstone view")
  }
  let failed_status = linked_status(failed_view)
  assert_true(failed_status.remote is @documents.RemoteState::Unavailable)
  assert_true(
    failed_view.persistence
    is Some(@replica_persistence.Status::Retryable(_, _)),
  )
}

///|
test "unsaved visible text projects durability and relation independently" {
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
  let initial = status_model(synchronized, status_sync(account))
  guard initial.page is Editing(editing) else { fail("editing") }
  let key = editing.activation.key
  let (documents, _) = editing.documents.reduce(
    @documents.Msg::TextChanged(key, "edited"),
  )
  let (documents, _) = documents.reduce(
    @documents.Msg::ApplyPendingEdit(key, pending_revision(documents, key)),
  )
  let model : Model = {
    page: Editing({ ..editing, documents, }),
    replication: @replication.State(protocol=status_sync(account), persistence~),
    departure: Stable,
    login_prepare: None,
    next_login_id: 0,
  }
  guard document_sync_view(model) is Some(status) else {
    fail("document sync view")
  }
  assert_true(status.durability is LocalDurability::Saving)
  let linked = linked_status(status)
  assert_true(linked.remote is @documents.RemoteState::LocalAhead)
  assert_true(
    status.persistence is Some(@replica_persistence.Status::Retryable(_, _)),
  )
  assert_true(linked.activity is @sync.Activity::Idle)
}

///|
test "network retry cannot become a saving retry" {
  let account = sync_test_account("account")
  let document = documents_test_document("one", "base")
  let synchronized = @source_repository.DocumentReplica::receive(
    account,
    document,
    status_revision(1.0),
  )
  guard synchronized.edit("sent")
    is @source_repository.EditPlan::Persist(edited) &&
    edited.replica().directive()
    is @source_repository.ReplicaDirective::CreateOperation(draft) else {
    fail("operation draft")
  }
  let sending = draft.start(sync_operation_id()).replica()
  guard status_sync(account).advance(sending)
    is (delivering, Some(@sync.Action::Deliver(attempt, _))) else {
    fail("delivery")
  }
  let retryable = delivering.delivery_failed(sending, attempt) catch {
    _ => abort("active delivery")
  }
  let initial = status_model(sending, retryable)
  guard initial.page is Editing(editing) else { fail("editing") }
  let key = editing.activation.key
  let (documents, _) = editing.documents.reduce(
    @documents.Msg::TextChanged(key, "newer"),
  )
  let (documents, _) = documents.reduce(
    @documents.Msg::ApplyPendingEdit(key, pending_revision(documents, key)),
  )
  let model = { ..initial, page: Editing({ ..editing, documents, }), }
  guard document_sync_view(model) is Some(view) else {
    fail("document sync view")
  }
  assert_true(view.durability is LocalDurability::Saving)
  let linked = linked_status(view)
  assert_true(view.persistence is Some(@replica_persistence.Status::Current))
  assert_true(linked.activity is @sync.Activity::Retryable(_))
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
  guard model.page is Editing(editing) else { fail("editing") }
  let key = editing.activation.key
  let (documents, _) = editing.documents.reduce(
    @documents.Msg::TextChanged(key, "edited"),
  )
  let (documents, _) = documents.reduce(
    @documents.Msg::ApplyPendingEdit(key, pending_revision(documents, key)),
  )
  let model = { ..model, page: Editing({ ..editing, documents, }), }
  guard document_sync_view(model) is Some(view) &&
    view.persistence is Some(@replica_persistence.Status::Retryable(action, _)) else {
    fail("retry available")
  }
  let message = RetrySaving(action)
  let (retrying, _) = test_root_update(model, message)
  assert_true(
    retrying.replication.status(account, document.id())
    is @replica_persistence.Persisting,
  )
  let (expired, _) = test_root_update(retrying, message)
  assert_true(expired == retrying)

  let unavailable = model.with_sync(@sync.State())
  let (checking, _) = test_root_update(unavailable, RetryAccount)
  assert_true(account_status(checking.sync()) == AccountStatus::Checking)
}

///|
test "replica persistence remains actionable without an account session" {
  let account = sync_test_account("account")
  let replica = @source_repository.DocumentReplica::receive(
    account,
    documents_test_document("one", "base"),
    status_revision(1.0),
  )
  guard replica.edit("edited") is @source_repository.EditPlan::Persist(write) else {
    fail("edited replica")
  }
  let (persistence, attempt) = @replica_persistence.State().submit(write)
  let (persistence, _) = persistence.complete(
    attempt.unwrap(),
    Err(@source_repository.ReplicaFailure::StorageUnavailable),
  )
  let model = {
    ..status_model(replica, @sync.State()),
    replication: @replication.State(protocol=@sync.State(), persistence~),
  }
  assert_true(
    document_replica_persistence(model)
    is Some(@replica_persistence.Status::Retryable(_, _)),
  )
  assert_true(document_sync(model) is Some(DocumentSync::Unavailable))
}

///|
test "fork persistence belongs to its recovery Source until commit" {
  let account = sync_test_account("account")
  let first = status_revision(1.0)
  let replica = @source_repository.DocumentReplica::receive(
    account,
    documents_test_document("one", "base"),
    first,
  )
  let edited = match replica.edit("local") {
    @source_repository.EditPlan::Persist(write) => write.replica()
    _ => abort("local edit")
  }
  let divergence = match
    edited.reconcile(
      @source_repository.RemoteDocument::Present(status_revision(2.0), "remote"),
    ) {
    @source_repository.ReconcilePlan::Persist(write) => write.replica()
    _ => abort("divergence")
  }
  let recovery_id = document_id("recovery")
  let fork = divergence.fork(recovery_id) catch { _ => abort("recovery fork") }
  let saved = @source_repository.SavedDocuments::from_documents([])
    .unwrap()
    .apply_replica(divergence)
  let documents = @documents.State::State(saved)
    .project_account(account)
    .begin_fork(fork) catch {
      _ => abort("forking documents")
    }
  let page = Editing({
    ..test_editing(),
    activation: { key: source_key("recovery"), generation: 1, },
    documents,
  })
  let (persistence, attempt) = @replica_persistence.State().submit(fork)
  let (persistence, _) = persistence.complete(
    attempt.unwrap(),
    Err(@source_repository.ReplicaFailure::StorageUnavailable),
  )
  let model : Model = {
    page,
    replication: @replication.State(protocol=@sync.State(), persistence~),
    departure: Stable,
    login_prepare: None,
    next_login_id: 0,
  }
  assert_true(
    document_replica_persistence(model)
    is Some(@replica_persistence.Status::Retryable(_, _)),
  )
  assert_true(document_sync(model) is Some(DocumentSync::DeviceOnly))
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
  guard document_sync_view(starting) is Some(starting_view) else {
    fail("starting document sync view")
  }
  assert_true(starting_view.durability is LocalDurability::Stored)
  assert_true(starting_view.sync is DocumentSync::Linking)

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
  assert_true(completed.sync().activity(replica) is @sync.Activity::Working)
  guard document_sync_view(completed) is Some(completed_view) else {
    fail("active transfer document sync view")
  }
  assert_true(completed_view.durability is LocalDurability::Stored)
  let completed_status = linked_status(completed_view)
  assert_true(completed_status.remote is @documents.RemoteState::LocalAhead)
  assert_true(
    completed_view.persistence is Some(@replica_persistence.Status::Current),
  )
  assert_true(completed_status.activity is @sync.Activity::Working)
}

///|
test "remote update capability is projected independently of durability" {
  let account = sync_test_account("account")
  let document = documents_test_document("one", "local")
  let synchronized = @source_repository.DocumentReplica::receive(
    account,
    document,
    status_revision(1.0),
  )
  guard synchronized.reconcile(
      @source_repository.RemoteDocument::Present(status_revision(2.0), "remote"),
    )
    is @source_repository.ReconcilePlan::Persist(write) else {
    fail("remote update")
  }
  let remote_sync = status_sync_with_catalog(
    account,
    @source_repository.RemoteEntry::Present(
      document.id(),
      status_revision(2.0),
      "remote",
    ),
  )
  guard document_sync_view(status_model(write.replica(), remote_sync))
    is Some(view) else {
    fail("remote update document sync view")
  }
  assert_true(view.durability is LocalDurability::Stored)
  let linked = linked_status(view)
  assert_true(linked.remote is @documents.RemoteState::UpdateAvailable(_))
  assert_true(view.persistence is Some(@replica_persistence.Status::Current))
  assert_true(linked.activity is @sync.Activity::Idle)
}

///|
test "remote freshness changes independently of network activity" {
  let account = sync_test_account("account")
  let document = documents_test_document("one", "base")
  let replica = @source_repository.DocumentReplica::receive(
    account,
    document,
    status_revision(1.0),
  )
  let current = status_model(replica, status_sync(account))
  let deleted = status_model(
    replica,
    status_sync_with_catalog(
      account,
      @source_repository.RemoteEntry::Deleted(
        document.id(),
        status_revision(2.0),
      ),
    ),
  )
  assert_true(document_remote_state(current) != document_remote_state(deleted))
  assert_true(
    document_remote_state(deleted)
    is Some(@documents.RemoteState::DeletedRemotely),
  )
  assert_eq(document_sync_activity(current), document_sync_activity(deleted))
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
  assert_true(completed.sync().activity(replica) is @sync.Activity::Idle)
  guard completed.page is Editing(after) else { fail("editing") }
  assert_true(
    after.activation.key == @documents.Key::replica(account_a, document.id()),
  )
  guard document_sync_view(completed) is Some(completed_view) else {
    fail("switched document sync view")
  }
  assert_true(completed_view.durability is LocalDurability::Stored)
  assert_true(completed_view.sync is DocumentSync::Unavailable)
}
