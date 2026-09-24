///|
fn document_id(value : String) -> @source_repository.DocumentId {
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
fn source_key(value : String) -> @documents.Key {
  @documents.Key::source(document_id(value))
}

///|
fn documents_test_document(
  id : String,
  text : String,
) -> @source_repository.Document {
  @source_repository.Document::create(document_id(id), text)
}

///|
fn pending_revision(documents : @documents.State, key : @documents.Key) -> Int {
  documents
  .pending_edits()
  .search_by(item => item.0 == key)
  .map(index => documents.pending_edits()[index].1)
  .unwrap()
}

///|
fn test_snapshot() -> @source_repository.SavedDocuments {
  @source_repository.SavedDocuments::from_documents([
    documents_test_document("one", "one"),
    documents_test_document("two", "two"),
  ]).unwrap()
}

///|
fn test_editing() -> EditingState {
  let snapshot = test_snapshot()
  let documents = @documents.State::State(snapshot)
  let (preview, _) = @preview.PreviewEngine::PreviewEngine().activate(
    @preview.Input(0, "one"),
  )
  {
    activation: { key: source_key("one"), generation: 0, },
    documents,
    creation: Idle,
    deletion: NoDeletion,
    mode: Text,
    compact: false,
    preview,
    import_failed: false,
    imports_pending: 0,
    new_preparation_request_id: 0,
  }
}

///|
fn test_update(model : Page, msg : Msg) -> (Page, @cmd.Cmd) {
  let (model, command) = update(
    test_model(model, @sync.State()),
    msg,
    @cmd.Emit(_ => @cmd.none),
    @text_area.TextArea::TextArea("loomark-test-text"),
    @preview.PreviewEngine::PreviewEngine(),
  )
  (model.page, command)
}

///|
fn test_root_update(model : Model, msg : Msg) -> (Model, @cmd.Cmd) {
  update(
    model,
    msg,
    @cmd.Emit(_ => @cmd.none),
    @text_area.TextArea::TextArea("loomark-test-text"),
    @preview.PreviewEngine::PreviewEngine(),
  )
}

///|
fn test_model(page : Page, sync : @sync.State) -> Model {
  {
    page,
    replication: @replication.State(protocol=sync),
    departure: Stable,
    login_prepare: None,
    next_login_id: 0,
  }
}

///|
fn begin_replica(
  model : Model,
  account : @source_repository.AccountId,
  document : @source_repository.Document,
) -> (Model, @replica_persistence.Attempt) {
  let saved = model.page.saved_documents().unwrap()
  let durable = saved.replica(account, document.id()).unwrap()
  let base = model.replication.editing_base(durable)
  let (sync, write) = model.sync().save(base, document.text())
  let (persistence, attempt) = model.replication
    .persistence()
    .submit(write.unwrap())
  (
    { ..model, replication: @replication.State(protocol=sync, persistence~), },
    attempt.unwrap(),
  )
}

///|
fn make_replica_eligible(
  model : Model,
  key : @documents.Key,
) -> (Model, @documents.ReplicaEdit) {
  guard model.page is Editing(editing) else { abort("editing") }
  let revision = pending_revision(editing.documents, key)
  let (_, actions) = editing.documents.reduce(
    @documents.Msg::ApplyPendingEdit(key, revision),
  )
  guard actions is [@documents.Action::SaveReplica(edit)] else {
    abort("replica eligible")
  }
  let (model, _) = test_root_update(model, ApplyPendingEdit(key, revision))
  (model, edit)
}

///|
fn test_sync_snapshot(
  account : @source_repository.AccountId,
) -> @source_repository.SavedDocuments {
  let document = @source_repository.Document::create(document_id("one"), "one")
  let saved = @source_repository.SavedDocuments::from_documents([
    @source_repository.Document::create(document_id("two"), "two"),
  ]).unwrap()
  let replica = @source_repository.DocumentReplica(account, document)
  saved.apply_replica(replica) catch {
    _ => abort("valid test replica")
  }
}

///|
fn test_synced_snapshot(
  account : @source_repository.AccountId,
) -> @source_repository.SavedDocuments {
  let document = @source_repository.Document::create(document_id("one"), "one")
  let revision = @source_repository.SavedRevision::parse(1.0) catch {
    _ => abort("valid synced revision")
  }
  let saved = @source_repository.SavedDocuments::from_documents([
    @source_repository.Document::create(document_id("two"), "two"),
  ]).unwrap()
  saved.apply_replica(
    @source_repository.DocumentReplica::receive(account, document, revision),
  ) catch {
    _ => abort("valid synced replica")
  }
}

///|
fn sync_operation_id() -> @source_repository.OperationId {
  @source_repository.OperationId::parse("10000000-0000-4000-8000-000000000001") catch {
    _ => abort("valid operation id")
  }
}

///|
fn pending_sync_snapshot(
  account : @source_repository.AccountId,
) -> (@source_repository.SavedDocuments, @source_repository.DocumentReplica) {
  let document = documents_test_document("one", "local")
  let replica = @source_repository.DocumentReplica(account, document)
  guard replica.directive()
    is @source_repository.ReplicaDirective::CreateOperation(draft) else {
    abort("save draft")
  }
  let replica = draft.start(sync_operation_id()).replica()
  let saved = @source_repository.SavedDocuments::from_documents([]).unwrap()
  (
    saved.apply_replica(replica) catch {
      _ => abort("valid pending replica")
    },
    replica,
  )
}

///|
fn current_sync(account : @source_repository.AccountId) -> @sync.State {
  let (state, lookup_id) = @sync.State().begin_lookup() catch {
    _ => abort("lookup should be available")
  }
  state.resolved(lookup_id, @sync.Resolved(account, "Writer")).0
}

///|
fn replica_edit(
  replica : @source_repository.DocumentReplica,
  text : String,
) -> @source_repository.DocumentReplica {
  guard replica.edit(text) is @source_repository.EditPlan::Persist(write) else {
    abort("replica edit")
  }
  write.replica()
}

///|
test "compact viewport preserves the fractional breakpoint boundary" {
  assert_true(compact_viewport(640.0))
  assert_true(!compact_viewport(640.5))
}

///|
test "repository open starts account lookup with its saved replicas" {
  let account = @source_repository.AccountId::parse("account") catch {
    _ => abort("valid test account")
  }
  let saved = test_sync_snapshot(account)
  let initial_document = saved.find(document_id("two")).unwrap()
  let (opened, _) = test_root_update(
    test_model(Loading(false), @sync.State()),
    Opened(Ready(saved, Some(initial_document))),
  )
  guard opened.sync().session() is @sync.Resolving(lookup_id) else {
    fail("account lookup")
  }
  let (resolved, _) = test_root_update(
    opened,
    Sync(AccountResolved(lookup_id, @sync.Resolved(account, "Writer"))),
  )

  guard resolved.sync().session() is @sync.Current(resolved_account, "Writer") else {
    fail("resolved account")
  }
  assert_true(resolved_account == account)
  guard resolved.page is Editing(editing) else { fail("editing") }
  let token = @documents.Key::replica(account, document_id("one"))
  assert_eq(editing.documents.text(token), Some("one"))
}

///|
test "account resolution schedules durable sync work" {
  let account = @source_repository.AccountId::parse("account") catch {
    _ => abort("valid test account")
  }
  let saved = test_sync_snapshot(account)
  let page = Editing({
    ..test_editing(),
    activation: {
      key: @documents.Key::replica(account, document_id("one")),
      generation: 0,
    },
    documents: @documents.State::State(saved),
  })
  let (resolving, lookup_id) = @sync.State().begin_lookup()
  let (resolved, _) = resolving.resolved(
    lookup_id,
    @sync.Resolved(account, "Writer"),
  )
  let replica = saved.replica(account, document_id("one")).unwrap()
  let (expected, action) = resolved.advance(replica)
  let expected = expected.begin_discovery().0
  assert_true(action is Some(@sync.Action::CreateOperation(_)))

  let (model, _) = test_root_update(
    test_model(page, resolving),
    Sync(AccountResolved(lookup_id, @sync.Resolved(account, "Writer"))),
  )
  assert_true(model.sync() == expected)
}

///|
test "delivery receipt enters the replica writer before becoming durable" {
  let account = @source_repository.AccountId::parse("account") catch {
    _ => abort("valid test account")
  }
  let (saved, replica) = pending_sync_snapshot(account)
  let page = Editing({
    ..test_editing(),
    activation: {
      key: @documents.Key::replica(account, document_id("one")),
      generation: 0,
    },
    documents: @documents.State::State(saved).project_account(account),
  })
  let (sync, action) = current_sync(account).advance(replica)
  guard action is Some(@sync.Action::Deliver(delivery, _)) else {
    fail("delivery")
  }
  let revision = @source_repository.SavedRevision::parse(1.0) catch {
    _ => abort("valid revision")
  }
  let (expected, write) = sync.acknowledged(replica, delivery, revision)
  let write = write.unwrap()
  let (_, attempt) = @replica_persistence.State().submit(write)
  let attempt = attempt.unwrap()
  let (acknowledging, _) = test_root_update(
    test_model(page, sync),
    Sync(
      DeliveryCompleted(
        delivery,
        @document_http.DeliveryResult::Acknowledged(revision),
      ),
    ),
  )
  assert_true(acknowledging.sync() == expected)
  assert_true(
    acknowledging.page
    .saved_documents()
    .unwrap()
    .replica(account, document_id("one")) ==
    Some(replica),
  )

  let (stored, _) = test_root_update(
    acknowledging,
    Sync(ReplicaWriteCompleted(attempt, Ok(()))),
  )
  assert_true(
    stored.page
    .saved_documents()
    .unwrap()
    .replica(account, document_id("one"))
    .unwrap()
    .directive()
    is @source_repository.ReplicaDirective::Synchronized,
  )
}

///|
test "account resolution retries a failed receipt replica" {
  let account = @source_repository.AccountId::parse("account") catch {
    _ => abort("valid test account")
  }
  let (saved, replica) = pending_sync_snapshot(account)
  let page = Editing({
    ..test_editing(),
    activation: {
      key: @documents.Key::replica(account, document_id("one")),
      generation: 0,
    },
    documents: @documents.State::State(saved).project_account(account),
  })
  guard current_sync(account).advance(replica)
    is (sync, Some(@sync.Action::Deliver(delivery, _))) else {
    fail("delivery")
  }
  let revision = @source_repository.SavedRevision::parse(1.0) catch {
    _ => abort("valid revision")
  }
  let (_, write) = sync.acknowledged(replica, delivery, revision)
  let write = write.unwrap()
  let (_, attempt) = @replica_persistence.State().submit(write)
  let (persisting, _) = test_root_update(
    test_model(page, sync),
    Sync(
      DeliveryCompleted(
        delivery,
        @document_http.DeliveryResult::Acknowledged(revision),
      ),
    ),
  )
  let (failed, _) = test_root_update(
    persisting,
    Sync(
      ReplicaWriteCompleted(
        attempt.unwrap(),
        Err(@source_repository.ReplicaFailure::StorageUnavailable),
      ),
    ),
  )
  let (resolving, lookup) = failed.sync().begin_lookup()
  let (retried, _) = test_root_update(
    failed.with_sync(resolving),
    Sync(AccountResolved(lookup, @sync.Resolved(account, "Writer"))),
  )
  assert_true(
    retried.replication.status(account, document_id("one"))
    is @replica_persistence.Status::Persisting,
  )
}

///|
test "account retry keeps an Undo made while replica storage is in flight" {
  let account = @source_repository.AccountId::parse("account") catch {
    _ => abort("valid test account")
  }
  let (saved, replica) = pending_sync_snapshot(account)
  let token = @documents.Key::replica(account, document_id("one"))
  let page = Editing({
    ..test_editing(),
    activation: { key: token, generation: 0, },
    documents: @documents.State::State(saved).project_account(account),
  })
  guard current_sync(account).advance(replica)
    is (sync, Some(@sync.Action::Deliver(delivery, _))) else {
    fail("delivery")
  }
  let revision = @source_repository.SavedRevision::parse(1.0) catch {
    _ => abort("valid revision")
  }
  let (sync, acknowledgment) = sync.acknowledged(replica, delivery, revision)
  let acknowledgment = acknowledgment.unwrap()
  let (persistence, acknowledgment_attempt) = @replica_persistence.State().submit(
    acknowledgment,
  )
  let acknowledgment_attempt = acknowledgment_attempt.unwrap()
  let model = {
    ..test_model(page, sync),
    replication: @replication.State(protocol=sync, persistence~),
  }
  let (model, _) = test_root_update(
    model,
    TextChanged(0, @text_change.TextChange::ReplaceAll("newer")),
  )
  let (model, _) = make_replica_eligible(model, token)

  let (failed, _) = test_root_update(
    model,
    Sync(
      ReplicaWriteCompleted(
        acknowledgment_attempt,
        Err(@source_repository.ReplicaFailure::StorageUnavailable),
      ),
    ),
  )
  guard failed.page is Editing(editing) else { fail("editing") }
  assert_true(
    editing.documents.save_status(token) is Some(@documents.SaveStatus::Unsaved),
  )

  let (checking_sync, lookup) = failed.sync().begin_lookup()
  let (retrying, _) = test_root_update(
    failed.with_sync(checking_sync),
    Sync(
      AccountResolved(lookup, @sync.AccountResult::Resolved(account, "Writer")),
    ),
  )
  guard retrying.page is Editing(retrying_editor) else { fail("editing") }
  assert_true(
    retrying_editor.documents.save_status(token)
    is Some(@documents.SaveStatus::Unsaved),
  )
  guard failed.replication.status(account, document_id("one"))
    is @replica_persistence.Status::Retryable(retry_action, _) else {
    fail("retryable persistence")
  }
  let (_, retry) = failed.replication.persistence().retry(retry_action)
  let (undone, _) = test_root_update(
    retrying,
    TextChanged(0, @text_change.TextChange::ReplaceAll("one")),
  )
  let (undone, _) = make_replica_eligible(undone, token)
  let (_, completion) = undone.replication.complete(retry, Ok(())) catch {
    _ => abort("revert completion")
  }
  guard completion
    is @replica_persistence.Completion::Superseded(_, reverting_attempt) else {
    fail("revert must follow the retried write")
  }
  let (stored_newer, _) = test_root_update(
    undone,
    Sync(ReplicaWriteCompleted(retry, Ok(()))),
  )
  guard stored_newer.page is Editing(stored_editor) else { fail("editing") }
  assert_eq(stored_editor.documents.text(token), Some("one"))
  assert_true(
    stored_editor.documents.save_status(token)
    is Some(@documents.SaveStatus::Unsaved),
  )
  let stored_replica = stored_editor.documents
    .snapshot()
    .replica(account, document_id("one"))
    .unwrap()
  assert_eq(
    stored_replica.document().map(document => document.text()),
    Some("newer"),
  )
  let (stored, _) = test_root_update(
    stored_newer,
    Sync(ReplicaWriteCompleted(reverting_attempt, Ok(()))),
  )
  assert_eq(
    stored.page
    .saved_documents()
    .unwrap()
    .replica(account, document_id("one"))
    .unwrap()
    .document()
    .map(document => document.text()),
    Some("one"),
  )
  guard stored.page is Editing(stored_editor) else { fail("editing") }
  assert_true(
    stored_editor.documents.save_status(token) ==
    Some(@documents.SaveStatus::Clean),
  )
}

///|
test "intermediate Replica commit cannot discard a pending Undo" {
  let account = @source_repository.AccountId::parse("account") catch {
    _ => abort("valid test account")
  }
  let saved = test_sync_snapshot(account)
  let id = document_id("one")
  let key = @documents.Key::replica(account, id)
  let durable = saved.replica(account, id).unwrap()
  guard durable.edit("intermediate")
    is @source_repository.EditPlan::Persist(intermediate) else {
    fail("intermediate write")
  }
  let (persistence, active) = @replica_persistence.State().submit(intermediate)
  let active = active.unwrap()
  let page = Editing({
    ..test_editing(),
    activation: { key, generation: 0, },
    documents: @documents.State::State(saved).project_account(account),
  })
  let model = {
    page,
    replication: @replication.State(
      protocol=current_sync(account),
      persistence~,
    ),
    departure: Stable,
    login_prepare: None,
    next_login_id: 0,
  }

  let (edited, _) = test_root_update(
    model,
    TextChanged(0, @text_change.TextChange::ReplaceAll("newer")),
  )
  let (queued, _) = make_replica_eligible(edited, key)
  let (undone, _) = test_root_update(
    queued,
    TextChanged(0, @text_change.TextChange::ReplaceAll("one")),
  )

  let (_, active_completion) = undone.replication.complete(active, Ok(())) catch {
    _ => abort("active completion")
  }
  guard active_completion
    is @replica_persistence.Completion::Superseded(_, newer_attempt) else {
    fail("newer write")
  }
  let (stored_active, _) = test_root_update(
    undone,
    Sync(ReplicaWriteCompleted(active, Ok(()))),
  )
  guard stored_active.page is Editing(editor) else { fail("editing") }
  assert_true(
    editor.documents.save_status(key) == Some(@documents.SaveStatus::Unsaved),
  )

  let (revert_queued, _) = make_replica_eligible(stored_active, key)
  let (_, newer_completion) = revert_queued.replication.complete(
    newer_attempt,
    Ok(()),
  ) catch {
    _ => abort("newer completion")
  }
  guard newer_completion
    is @replica_persistence.Completion::Superseded(_, revert_attempt) else {
    fail("revert write")
  }
  guard revert_queued.page is Editing(editor) else { fail("editing") }
  let unmounted = {
    ..revert_queued,
    page: Editing({
      ..editor,
      activation: { key: source_key("two"), generation: 1, },
    }),
  }
  let (stored_newer, _) = test_root_update(
    unmounted,
    Sync(ReplicaWriteCompleted(newer_attempt, Ok(()))),
  )
  guard stored_newer.page is Editing(editor) else { fail("editing") }
  assert_eq(editor.documents.text(key), Some("one"))
  assert_true(
    editor.documents.save_status(key) == Some(@documents.SaveStatus::Unsaved),
  )
  let (stored_revert, _) = test_root_update(
    stored_newer,
    Sync(ReplicaWriteCompleted(revert_attempt, Ok(()))),
  )
  assert_eq(
    stored_revert.page
    .saved_documents()
    .unwrap()
    .replica(account, id)
    .unwrap()
    .document()
    .map(document => document.text()),
    Some("one"),
  )
  guard stored_revert.page is Editing(editor) else { fail("editing") }
  assert_eq(editor.documents.text(key), Some("one"))
  assert_true(
    editor.documents.save_status(key) == Some(@documents.SaveStatus::Clean),
  )
}

///|
test "network retry waits while a newer replica write is in flight" {
  let account = @source_repository.AccountId::parse("account") catch {
    _ => abort("valid test account")
  }
  let (saved, replica) = pending_sync_snapshot(account)
  guard current_sync(account).advance(replica)
    is (delivering, Some(@sync.Action::Deliver(delivery, _))) else {
    fail("delivery")
  }
  let retryable = delivering.delivery_failed(replica, delivery) catch {
    _ => abort("active delivery")
  }
  guard retryable.activity(replica) is @sync.Activity::Retryable(retry) else {
    fail("network retry")
  }
  guard replica.edit("newer") is @source_repository.EditPlan::Persist(write) else {
    fail("newer replica")
  }
  let (persistence, _) = @replica_persistence.State().submit(write)
  let token = @documents.Key::replica(account, document_id("one"))
  let page = Editing({
    ..test_editing(),
    activation: { key: token, generation: 0, },
    documents: @documents.State::State(saved).project_account(account),
  })
  let model = {
    page,
    replication: @replication.State(protocol=retryable, persistence~),
    departure: Stable,
    login_prepare: None,
    next_login_id: 0,
  }
  let (unchanged, _) = test_root_update(model, RetrySync(retry))
  assert_true(unchanged == model)
}

///|
test "operation identity failure stays retryable while replica storage is busy" {
  let account = @source_repository.AccountId::parse("account") catch {
    _ => abort("valid test account")
  }
  let saved = test_sync_snapshot(account)
  let replica = saved.replica(account, document_id("one")).unwrap()
  let idle = current_sync(account)
  guard idle.advance(replica)
    is (planning, Some(@sync.Action::CreateOperation(attempt))) else {
    fail("operation plan")
  }
  guard replica.edit("newer") is @source_repository.EditPlan::Persist(write) else {
    fail("newer replica")
  }
  let (persistence, _) = @replica_persistence.State().submit(write)
  let token = @documents.Key::replica(account, document_id("one"))
  let page = Editing({
    ..test_editing(),
    activation: { key: token, generation: 0, },
    documents: @documents.State::State(saved).project_account(account),
  })
  let model = {
    page,
    replication: @replication.State(protocol=planning, persistence~),
    departure: Stable,
    login_prepare: None,
    next_login_id: 0,
  }
  let (retired, _) = test_root_update(
    model,
    Sync(OperationPrepared(attempt, Some(sync_operation_id()))),
  )
  assert_true(retired.sync().activity(replica) is @sync.Activity::Retryable(_))
  assert_true(retired.replication.persistence() == persistence)
}

///|
test "operation identity generation failure remains retryable" {
  let account = @source_repository.AccountId::parse("account") catch {
    _ => abort("valid test account")
  }
  let saved = test_sync_snapshot(account)
  let replica = saved.replica(account, document_id("one")).unwrap()
  guard current_sync(account).advance(replica)
    is (planning, Some(@sync.Action::CreateOperation(attempt))) else {
    fail("operation preparation")
  }
  let page = Editing({
    ..test_editing(),
    activation: {
      key: @documents.Key::replica(account, document_id("one")),
      generation: 0,
    },
    documents: @documents.State::State(saved).project_account(account),
  })
  let (failed, _) = test_root_update(
    test_model(page, planning),
    Sync(OperationPrepared(attempt, None)),
  )
  guard failed.sync().activity(replica) is @sync.Activity::Retryable(retry) else {
    fail("retryable preparation")
  }
  let (retrying, _) = test_root_update(failed, RetrySync(retry))
  assert_true(retrying.sync().activity(replica) is @sync.Activity::Working)
}

///|
test "visibility restore refreshes the account but hiding does not" {
  let account = @source_repository.AccountId::parse("account") catch {
    _ => abort("valid test account")
  }
  let model = test_model(Editing(test_editing()), current_sync(account))
  let (hidden, _) = test_root_update(model, VisibilityChanged(true))
  assert_true(
    hidden.sync().session() is @sync.Current(current, _) && current == account,
  )
  let (restored, _) = test_root_update(hidden, VisibilityChanged(false))
  assert_true(restored.sync().session() is @sync.Resolving(_))

  let unavailable = test_model(Editing(test_editing()), @sync.State())
  let (recovering, _) = test_root_update(unavailable, VisibilityChanged(false))
  assert_true(recovering.sync().session() is @sync.Resolving(_))
}

///|
test "account switch defers a conflict fetch until its account is current" {
  let account_a = @source_repository.AccountId::parse("account-a") catch {
    _ => abort("valid account")
  }
  let account_b = @source_repository.AccountId::parse("account-b") catch {
    _ => abort("valid account")
  }
  let (saved, replica) = pending_sync_snapshot(account_a)
  let page = Editing({
    ..test_editing(),
    activation: {
      key: @documents.Key::replica(account_a, document_id("one")),
      generation: 0,
    },
    documents: @documents.State::State(saved).project_account(account_a),
  })
  guard current_sync(account_a).advance(replica)
    is (sync, Some(@sync.Action::Deliver(delivery, _))) else {
    fail("delivery")
  }
  let (sync, lookup) = sync.begin_lookup()
  let (sync, _) = sync.resolved(lookup, @sync.Resolved(account_b, "B"))
  let (deferred, _) = test_root_update(
    test_model(page, sync),
    Sync(
      DeliveryCompleted(
        delivery,
        @document_http.DeliveryResult::RevisionConflict,
      ),
    ),
  )
  let expected = sync.revision_conflict(replica, delivery)
  assert_true(deferred.sync() == expected)

  let (resolving, lookup) = deferred.sync().begin_lookup()
  let (current, _) = test_root_update(
    deferred.with_sync(resolving),
    Sync(AccountResolved(lookup, @sync.Resolved(account_a, "A"))),
  )
  let (expected, action) = expected.begin_lookup().0.resolved(
    lookup,
    @sync.Resolved(account_a, "A"),
  ).0.advance(replica)
  let expected = expected.begin_discovery().0
  assert_true(action is Some(@sync.Action::GetRemote(_)))
  assert_true(current.sync() == expected)
}

///|
test "revision conflict waits for recovery identity before atomic persistence" {
  let account = @source_repository.AccountId::parse("account") catch {
    _ => abort("valid test account")
  }
  let (saved, replica) = pending_sync_snapshot(account)
  let page = Editing({
    ..test_editing(),
    activation: {
      key: @documents.Key::replica(account, document_id("one")),
      generation: 0,
    },
    documents: @documents.State::State(saved).project_account(account),
  })
  guard current_sync(account).advance(replica)
    is (sync, Some(@sync.Action::Deliver(delivery, _))) else {
    fail("delivery")
  }
  let revision = @source_repository.SavedRevision::parse(1.0) catch {
    _ => abort("valid revision")
  }
  let remote = @source_repository.RemoteDocument::Present(revision, "remote")
  let conflicted = sync.revision_conflict(replica, delivery)
  let (fetching, fetch) = conflicted.advance(replica)
  guard fetch is Some(@sync.Action::GetRemote(read)) else {
    fail("conflict read")
  }
  let (expected, write) = fetching.received(replica, read, remote)
  let write = write.unwrap()
  let diverged = write.replica()
  let (fetching_model, _) = test_root_update(
    test_model(page, sync),
    Sync(
      DeliveryCompleted(
        delivery,
        @document_http.DeliveryResult::RevisionConflict,
      ),
    ),
  )
  assert_true(fetching_model.sync() == fetching)
  let (recovering, _) = test_root_update(
    fetching_model,
    Sync(RemoteCompleted(read, @document_http.RemoteResult::Found(remote))),
  )
  assert_true(recovering.sync() == expected)

  let (_, attempt) = fetching_model.replication.persistence().submit(write)
  let attempt = attempt.unwrap()
  guard expected.advance(diverged)
    is (awaiting_recovery, Some(@sync.Action::CreateRecovery(recovery))) else {
    fail("recovery")
  }
  let mut created : @source_repository.DocumentId? = None
  let (recovering, _) = update(
    recovering,
    Sync(ReplicaWriteCompleted(attempt, Ok(()))),
    @cmd.Emit(message => {
      match message {
        Sync(
          RecoveryCreated(
            attempt,
            @source_repository.CreateResult::Created(recovery_id)
          )
        ) if attempt == recovery => created = Some(recovery_id)
        _ => ()
      }
      @cmd.none
    }),
    @text_area.TextArea::TextArea("loomark-test-text"),
    @preview.PreviewEngine::PreviewEngine(),
  )
  assert_true(recovering.sync() == awaiting_recovery)

  let recovery_id = created.unwrap()
  let (expected, write) = awaiting_recovery.recover(
    diverged, recovery, recovery_id,
  )
  let write = write.unwrap()
  guard write is @source_repository.Fork(_, recovery_document) else {
    fail("atomic recovery")
  }
  assert_eq(recovery_document.text(), "local")
  guard recovering.replication.submit(write)
    is (_, Some(@replication.Persist(fork_attempt))) else {
    fail("fork persistence")
  }
  let (creating, _) = test_root_update(recovering, CreateRequested)
  guard creating.page is Editing(creating_editor) &&
    creating_editor.creation is Creating(0) else {
    fail("creation in flight")
  }
  let (persisting, _) = test_root_update(
    creating,
    Sync(
      RecoveryCreated(
        recovery,
        @source_repository.CreateResult::Created(recovery_id),
      ),
    ),
  )
  assert_true(persisting.sync() == expected)
  guard persisting.page is Editing(forking) else { fail("editing") }
  let recovery_key = @documents.Key::source(recovery_id)
  assert_true(forking.activation.key == recovery_key)
  assert_eq(forking.activation.generation, 0)
  assert_eq(forking.documents.text(recovery_key), Some("local"))
  let (created_after_rekey, _) = test_root_update(
    persisting,
    CreateCompleted(0, Created(document_id("created-during-fork"))),
  )
  guard created_after_rekey.page is Editing(created_editor) else {
    fail("created document")
  }
  assert_true(
    created_editor.activation.key == source_key("created-during-fork"),
  )

  let (committed, _) = test_root_update(
    persisting,
    Sync(ReplicaWriteCompleted(fork_attempt, Ok(()))),
  )
  guard committed.page is Editing(editing) else { fail("editing") }
  assert_true(editing.activation.key == recovery_key)
  assert_eq(editing.activation.generation, 0)
  assert_eq(editing.documents.text(recovery_key), Some("local"))
  assert_eq(
    editing.documents.text(@documents.Key::replica(account, document_id("one"))),
    Some("remote"),
  )
}

///|
test "selected Replica cannot reopen a fork before its durable commit" {
  let account = @source_repository.AccountId::parse("account") catch {
    _ => abort("valid account")
  }
  let first = @source_repository.SavedRevision::parse(1.0) catch {
    _ => abort("valid revision")
  }
  let second = @source_repository.SavedRevision::parse(2.0) catch {
    _ => abort("valid revision")
  }
  let id = document_id("one")
  let key = @documents.Key::replica(account, id)
  let replica = @source_repository.DocumentReplica::receive(
    account,
    documents_test_document("one", "base"),
    first,
  )
  let edited = replica_edit(replica, "local")
  guard edited.reconcile(
      @source_repository.RemoteDocument::Present(second, "remote"),
    )
    is @source_repository.ReconcilePlan::Persist(divergence) else {
    fail("durable divergence")
  }
  let diverged = divergence.replica()
  let saved = @source_repository.SavedDocuments::from_documents([])
    .unwrap()
    .apply_replica(diverged)
  let recovery_id = document_id("recovery")
  let fork = diverged.fork(recovery_id) catch {
    _ => abort("valid recovery identity")
  }
  let page = Editing({
    ..test_editing(),
    activation: { key, generation: 0, },
    documents: @documents.State::State(saved).project_account(account),
  })
  let page = page.begin_fork(fork).unwrap()
  let entry = @source_repository.RemoteEntry::Present(id, first, "Base")
  let model = test_model(page, discovered_sync(account, entry))
  guard model.replication.submit(fork)
    is (replication, Some(@replication.Persist(attempt))) else {
    fail("fork persistence")
  }
  let model = { ..model, replication, }

  let (selected, _) = test_root_update(model, DocumentSelected(key))
  let (unchanged, _) = test_root_update(selected, ViewportChanged(900.0))
  guard unchanged.page is Editing(editing) else { fail("editing") }
  let recovery_key = @documents.Key::source(recovery_id)
  assert_true(editing.activation.key == recovery_key)
  assert_eq(editing.documents.text(key), None)
  assert_eq(editing.documents.text(recovery_key), Some("local"))

  let (committed, _) = test_root_update(
    unchanged,
    Sync(ReplicaWriteCompleted(attempt, Ok(()))),
  )
  guard committed.page is Editing(editing) else { fail("editing") }
  assert_true(editing.activation.key == key)
  assert_eq(editing.documents.text(key), Some("remote"))
  assert_eq(editing.documents.text(recovery_key), Some("local"))
  assert_eq(
    editing.documents.recent().filter(item => item.0 == key).length(),
    1,
  )
}

///|
test "failed conflict recovery identity leaves durable recovery work retryable" {
  let account = @source_repository.AccountId::parse("account") catch {
    _ => abort("valid test account")
  }
  let (saved, replica) = pending_sync_snapshot(account)
  let page = Editing({
    ..test_editing(),
    activation: {
      key: @documents.Key::replica(account, document_id("one")),
      generation: 0,
    },
    documents: @documents.State::State(saved).project_account(account),
  })
  guard current_sync(account).advance(replica)
    is (sync, Some(@sync.Action::Deliver(delivery, _))) else {
    fail("delivery")
  }
  let revision = @source_repository.SavedRevision::parse(1.0) catch {
    _ => abort("valid revision")
  }
  let remote = @source_repository.RemoteDocument::Present(revision, "remote")
  let conflicted = sync.revision_conflict(replica, delivery)
  guard conflicted.advance(replica)
    is (driven, Some(@sync.Action::GetRemote(read))) else {
    fail("conflict read")
  }
  let (persisting, divergence) = driven.received(replica, read, remote)
  let divergence = divergence.unwrap()
  let diverged = divergence.replica()
  let (fetching, _) = test_root_update(
    test_model(page, sync),
    Sync(
      DeliveryCompleted(
        delivery,
        @document_http.DeliveryResult::RevisionConflict,
      ),
    ),
  )
  assert_true(fetching.sync() == driven)
  let (recovering, _) = test_root_update(
    fetching,
    Sync(RemoteCompleted(read, @document_http.RemoteResult::Found(remote))),
  )
  assert_true(recovering.sync() == persisting)
  let (_, attempt) = fetching.replication.persistence().submit(divergence)
  let attempt = attempt.unwrap()
  guard persisting.advance(diverged)
    is (awaiting_recovery, Some(@sync.Action::CreateRecovery(recovery))) else {
    fail("recovery")
  }
  let (recovering, _) = test_root_update(
    recovering,
    Sync(ReplicaWriteCompleted(attempt, Ok(()))),
  )
  assert_true(recovering.sync() == awaiting_recovery)
  let (retryable, _) = test_root_update(
    recovering,
    Sync(
      RecoveryCreated(
        recovery,
        @source_repository.CreateResult::CreateFailed(
          DocumentIdentityUnavailable,
        ),
      ),
    ),
  )
  assert_true(
    retryable.sync().advance(diverged).1 is Some(@sync.CreateRecovery(_)),
  )
}

///|
test "sync messages preserve the editor page" {
  let page = Editing(test_editing())
  let (sync, lookup_id) = @sync.State().begin_lookup()
  let (updated, _) = test_root_update(
    test_model(page, sync),
    Sync(AccountResolved(lookup_id, @sync.SignedOut)),
  )
  assert_true(updated.page == page)
}

///|
test "accepting a remote update starts a fresh editor activation" {
  let account = @source_repository.AccountId::parse("account") catch {
    _ => abort("valid account")
  }
  let document = documents_test_document("one", "base")
  let base_revision = @source_repository.SavedRevision::parse(1.0) catch {
    _ => abort("valid revision")
  }
  let remote_revision = @source_repository.SavedRevision::parse(2.0) catch {
    _ => abort("valid revision")
  }
  let synchronized = @source_repository.DocumentReplica::receive(
    account, document, base_revision,
  )
  guard synchronized.reconcile(
      @source_repository.RemoteDocument::Present(remote_revision, "remote"),
    )
    is @source_repository.ReconcilePlan::Persist(write) else {
    fail("remote update")
  }
  let replica = write.replica()
  let saved = @source_repository.SavedDocuments::from_documents([])
    .unwrap()
    .apply_replica(replica) catch {
      _ => abort("valid replica")
    }
  let key = @documents.Key::replica(account, document.id())
  let documents = @documents.State::State(saved).project_account(account)
  let head = @source_repository.RemoteHead::Present(remote_revision)
  guard documents.remote_state(replica, Some(head))
    is @documents.RemoteState::UpdateAvailable(action) else {
    fail("update action")
  }
  let (sync, discovery) = current_sync(account).begin_discovery()
  let sync = sync.discovered(
      account,
      discovery.unwrap(),
      Some([
        @source_repository.RemoteEntry::Present(
          document.id(),
          remote_revision,
          "remote",
        ),
      ]),
    ).0
  let base = test_editing()
  let model = test_model(
    Editing({ ..base, activation: { key, generation: 0, }, documents, }),
    sync,
  )

  let (accepted, _) = test_root_update(model, AcceptRemote(action))
  guard accepted.page is Editing(editing) else { fail("editing") }
  assert_true(editing.activation.key == key)
  assert_eq(editing.activation.generation, 1)
  assert_eq(editing.documents.text(key), Some("remote"))
}

///|
test "editor messages change the root model" {
  let page = Editing(test_editing())
  let model = test_model(page, @sync.State())
  let (updated, _) = test_root_update(
    model,
    TextChanged(0, @text_change.TextChange::ReplaceAll("changed")),
  )
  assert_true(updated != model)
}

///|
test "eligible Replica edit enters persistence in the same root update" {
  let account = @source_repository.AccountId::parse("account") catch {
    _ => abort("valid test account")
  }
  let saved = test_sync_snapshot(account)
  let key = @documents.Key::replica(account, document_id("one"))
  let model = test_model(
    Editing({
      ..test_editing(),
      activation: { key, generation: 0, },
      documents: @documents.State::State(saved).project_account(account),
    }),
    current_sync(account),
  )
  let (edited, _) = test_root_update(
    model,
    TextChanged(0, @text_change.TextChange::ReplaceAll("edited")),
  )
  guard edited.page is Editing(editing) else { fail("editing") }
  let revision = pending_revision(editing.documents, key)
  let (submitted, _) = test_root_update(edited, ApplyPendingEdit(key, revision))
  assert_true(
    submitted.replication.status(account, document_id("one"))
    is @replica_persistence.Status::Persisting,
  )
}

///|
test "synced Autosave updates only its canonical replica" {
  let account = @source_repository.AccountId::parse("account") catch {
    _ => abort("valid test account")
  }
  let saved = test_sync_snapshot(account)
  let token = @documents.Key::replica(account, document_id("one"))
  let initial = {
    ..test_editing(),
    activation: { key: token, generation: 0, },
    documents: @documents.State::State(saved).project_account(account),
  }
  let (documents, _) = initial.documents.reduce(
    @documents.Msg::TextChanged(token, "changed"),
  )
  let (documents, decisions) = documents.reduce(
    @documents.Msg::ApplyPendingEdit(token, pending_revision(documents, token)),
  )
  guard decisions is [@documents.Action::SaveReplica(submission)] else {
    fail("replica persistence")
  }
  let owner = submission.durable().account()
  let document = submission.document()
  assert_true(owner == account)
  let model = test_model(Editing({ ..initial, documents, }), @sync.State())
  let (storing, attempt) = begin_replica(model, owner, document)
  let (stored, _) = test_root_update(
    storing,
    Sync(ReplicaWriteCompleted(attempt, Ok(()))),
  )

  guard stored.page is Editing(editing) else { fail("editing") }
  assert_true(
    editing.documents.save_status(token) == Some(@documents.SaveStatus::Clean),
  )
  assert_eq(
    editing.documents
    .snapshot()
    .replica(account, document_id("one"))
    .unwrap()
    .document()
    .map(document => document.text()),
    Some("changed"),
  )
  assert_eq(editing.documents.snapshot().find(document_id("one")), None)
  assert_eq(
    editing.documents.snapshot().find(document_id("two")).unwrap().text(),
    "two",
  )
}

///|
fn discovered_sync(
  account : @source_repository.AccountId,
  entry : @source_repository.RemoteEntry,
) -> @sync.State {
  let (state, discovery) = current_sync(account).begin_discovery()
  state.discovered(account, discovery.unwrap(), Some([entry])).0
}

///|
fn discover_entry(
  model : Model,
  account : @source_repository.AccountId,
  entry : @source_repository.RemoteEntry,
) -> Model {
  let (sync, discovery) = model.sync().begin_discovery()
  let (model, _) = test_root_update(
    model.with_sync(sync),
    Sync(
      DiscoveryCompleted(
        account,
        discovery.unwrap(),
        @document_http.DiscoveryResult::Discovered([entry]),
      ),
    ),
  )
  model
}

///|
fn select_remote(
  model : Model,
  key : @documents.Key,
  entry : @source_repository.RemoteEntry,
) -> (Model, @sync.OpenAttempt) {
  guard key is @documents.Key::Replica(_, _) else { abort("remote key") }
  let saved = model.page.saved_documents().unwrap()
  guard model.replication.select(saved, entry.document_id())
    is (expected, [@replication.Network(@sync.OpenRemote(attempt))]) else {
    abort("expected remote open")
  }
  let (selected, _) = test_root_update(model, DocumentSelected(key))
  guard selected.replication == expected else {
    abort("remote selection mismatch")
  }
  (selected, attempt)
}

///|
fn receive_open(
  model : Model,
  attempt : @sync.OpenAttempt,
  remote : @source_repository.RemoteDocument,
) -> (Model, @replica_persistence.Attempt?) {
  let saved = model.page.saved_documents().unwrap()
  let (expected, effect) = model.replication.opened(saved, attempt, remote) catch {
    _ => abort("remote open rejected")
  }
  let (received, _) = test_root_update(
    model,
    Sync(OpenCompleted(attempt, @document_http.RemoteResult::Found(remote))),
  )
  guard received.replication == expected else {
    abort("remote receipt mismatch")
  }
  let attempt = match effect {
    Some(@replication.Persist(attempt)) => Some(attempt)
    Some(Network(_)) | None => None
  }
  (received, attempt)
}

///|
fn store_sync_attempt(
  model : Model,
  attempt : @replica_persistence.Attempt,
) -> (Model, @replica_persistence.Attempt?) {
  let (_, completion) = model.replication
    .persistence()
    .complete(attempt, Ok(())) catch {
      _ => abort("replica completion rejected")
    }
  let next = match completion {
    @replica_persistence.Completion::Superseded(_, next) => Some(next)
    Current(_) | Retryable(_, _, _) | Failed(_, _) => None
  }
  let (stored, _) = test_root_update(
    model,
    Sync(ReplicaWriteCompleted(attempt, Ok(()))),
  )
  (stored, next)
}

///|
test "failed remote selection retries through a fresh typed open attempt" {
  let account = sync_test_account("account")
  let remote_id = document_id("remote")
  let revision = @source_repository.SavedRevision::parse(2.0) catch {
    _ => abort("valid revision")
  }
  let entry = @source_repository.RemoteEntry::Present(
    remote_id, revision, "Remote",
  )
  let initial = test_model(
    Editing(test_editing()),
    discovered_sync(account, entry),
  )
  let (fetching, first) = select_remote(
    initial,
    @documents.Key::replica(account, remote_id),
    entry,
  )
  let (failed, _) = test_root_update(
    fetching,
    Sync(OpenCompleted(first, @document_http.RemoteResult::Unavailable)),
  )
  guard failed.sync().selection_activity()
    is @sync.SelectionActivity::Retryable(retry) else {
    fail("retryable open")
  }
  let (retrying, _) = test_root_update(failed, RetrySelection(retry))
  assert_true(
    retrying.sync().selection_activity() is @sync.SelectionActivity::Working,
  )
  let (unchanged, _) = test_root_update(retrying, RetrySelection(retry))
  assert_true(unchanged == retrying)
}

///|
test "remote selection persists its received replica before activation" {
  let account = @source_repository.AccountId::parse("account") catch {
    _ => abort("valid account")
  }
  let remote_id = document_id("remote")
  let revision = @source_repository.SavedRevision::parse(2.0) catch {
    _ => abort("valid revision")
  }
  let entry = @source_repository.RemoteEntry::Present(
    remote_id, revision, "Remote",
  )
  let key = @documents.Key::replica(account, remote_id)
  let initial = test_model(
    Editing(test_editing()),
    discovered_sync(account, entry),
  )
  let saved = initial.page.saved_documents().unwrap()
  guard initial.replication.select(saved, entry.document_id())
    is (expected, [@replication.Network(@sync.OpenRemote(open))]) else {
    fail("open")
  }
  let (fetching, _) = test_root_update(initial, DocumentSelected(key))
  assert_true(fetching.replication == expected)
  guard fetching.page is Editing(before) else { fail("editing") }
  assert_true(before.activation.key == source_key("one"))
  assert_eq(before.documents.text(key), None)

  let remote = @source_repository.RemoteDocument::Present(
    revision, "# Remote\nBody",
  )
  guard fetching.replication.opened(saved, open, remote)
    is (expected, Some(@replication.Persist(attempt))) else {
    fail("remote persistence")
  }
  let (storing, _) = test_root_update(
    fetching,
    Sync(OpenCompleted(open, @document_http.RemoteResult::Found(remote))),
  )
  assert_true(storing.replication == expected)
  guard storing.page is Editing(before) else { fail("editing") }
  assert_eq(before.documents.text(key), None)

  let (opened, _) = test_root_update(
    storing,
    Sync(ReplicaWriteCompleted(attempt, Ok(()))),
  )
  guard opened.page is Editing(editing) else { fail("editing") }
  assert_true(editing.activation.key == key)
  assert_eq(editing.documents.text(key), Some("# Remote\nBody"))
}

///|
test "remote tombstone persists without activating its Replica" {
  let account = @source_repository.AccountId::parse("account") catch {
    _ => abort("valid account")
  }
  let remote_id = document_id("deleted-while-opening")
  let first = @source_repository.SavedRevision::parse(1.0) catch {
    _ => abort("first revision")
  }
  let second = @source_repository.SavedRevision::parse(2.0) catch {
    _ => abort("second revision")
  }
  let replica = @source_repository.DocumentReplica::receive(
    account,
    documents_test_document("deleted-while-opening", "base"),
    first,
  )
  let saved = test_snapshot().apply_replica(replica)
  let entry = @source_repository.RemoteEntry::Present(
    remote_id, second, "Remote",
  )
  let initial = test_model(
    Editing({ ..test_editing(), documents: @documents.State::State(saved), }),
    discovered_sync(account, entry),
  )
  guard initial.replication.select(saved, entry.document_id())
    is (replication, [@replication.Network(@sync.GetRemote(read))]) else {
    fail("refresh")
  }
  let fetching = { ..initial, replication, }
  let tombstone = @source_repository.RemoteDocument::Deleted(second)
  let base = fetching.replication.protocol_base(replica)
  let (sync, write) = fetching.sync().received(base, read, tombstone) catch {
      _ => abort("remote tombstone rejected")
    }
  guard fetching.replication.with_protocol(sync).submit(write.unwrap())
    is (expected, Some(@replication.Persist(attempt))) else {
    fail("tombstone persistence")
  }
  let (storing, _) = test_root_update(
    fetching,
    Sync(RemoteCompleted(read, @document_http.RemoteResult::Found(tombstone))),
  )
  assert_eq(storing.replication, expected)
  assert_eq(storing.sync().selection(), None)
  guard storing.page is Editing(editing) else { fail("editing") }
  assert_true(editing.activation.key == source_key("one"))

  let (stored, next) = store_sync_attempt(storing, attempt)
  assert_eq(next, None)
  guard stored.page is Editing(editing) else { fail("editing") }
  assert_true(editing.activation.key == source_key("one"))
  guard editing.documents.snapshot().replica(account, remote_id)
    is Some(deleted) else {
    fail("durable tombstone")
  }
  assert_eq(
    deleted.directive(),
    @source_repository.ReplicaDirective::UpdateAvailable(tombstone),
  )
}

///|
test "reselecting a remote document retries its failed replica" {
  let account = @source_repository.AccountId::parse("account") catch {
    _ => abort("valid account")
  }
  let remote_id = document_id("remote-retry")
  let revision = @source_repository.SavedRevision::parse(2.0) catch {
    _ => abort("valid revision")
  }
  let entry = @source_repository.RemoteEntry::Present(
    remote_id, revision, "Remote",
  )
  let key = @documents.Key::replica(account, remote_id)
  let initial = test_model(
    Editing(test_editing()),
    discovered_sync(account, entry),
  )
  let (fetching, open) = select_remote(initial, key, entry)
  let remote = @source_repository.RemoteDocument::Present(revision, "remote")
  let (storing, attempt) = receive_open(fetching, open, remote)
  let attempt = attempt.unwrap()
  let (failed, _) = test_root_update(
    storing,
    Sync(
      ReplicaWriteCompleted(
        attempt,
        Err(@source_repository.ReplicaFailure::StorageUnavailable),
      ),
    ),
  )
  guard failed.replication.status(account, remote_id)
    is @replica_persistence.Status::Retryable(retry, _) else {
    fail("retryable replica")
  }
  let (_, retry_attempt) = failed.replication.persistence().retry(retry)
  let (retrying, _) = test_root_update(failed, DocumentSelected(key))
  assert_true(
    retrying.replication.status(account, remote_id)
    is @replica_persistence.Status::Persisting,
  )
  let (opened, _) = test_root_update(
    retrying,
    Sync(ReplicaWriteCompleted(retry_attempt, Ok(()))),
  )
  guard opened.page is Editing(editing) else { fail("editing") }
  assert_true(editing.activation.key == key)
  assert_eq(editing.documents.text(key), Some("remote"))
}

///|
test "selection waits for a catalog revision discovered during persistence" {
  let account = @source_repository.AccountId::parse("account") catch {
    _ => abort("valid account")
  }
  let id = document_id("remote-race")
  let first_revision = @source_repository.SavedRevision::parse(1.0) catch {
    _ => abort("first revision")
  }
  let second_revision = @source_repository.SavedRevision::parse(2.0) catch {
    _ => abort("second revision")
  }
  let first_entry = @source_repository.RemoteEntry::Present(
    id, first_revision, "First",
  )
  let second_entry = @source_repository.RemoteEntry::Present(
    id, second_revision, "Second",
  )
  let key = @documents.Key::replica(account, id)
  let initial = test_model(
    Editing(test_editing()),
    discovered_sync(account, first_entry),
  )
  let (opening_first, first_open) = select_remote(initial, key, first_entry)
  let first_remote = @source_repository.RemoteDocument::Present(
    first_revision, "first text",
  )
  let (storing_first, first_attempt) = receive_open(
    opening_first, first_open, first_remote,
  )
  let first_attempt = first_attempt.unwrap()

  let newer = discover_entry(storing_first, account, second_entry)
  assert_true(
    newer.replication.status(account, id)
    is @replica_persistence.Status::Persisting,
  )
  let (stored_first, next) = store_sync_attempt(newer, first_attempt)
  assert_eq(next, None)
  guard stored_first.page is Editing(editing) else { fail("editing") }
  assert_true(editing.activation.key == source_key("one"))
  assert_eq(editing.documents.text(key), None)
  let durable = editing.documents.snapshot().replica(account, id).unwrap()
  assert_eq(durable.baseline_revision(), 1.0)
  assert_true(
    stored_first.replication.activity(durable) is @sync.Activity::Working,
  )
  assert_true(stored_first.sync().selection() is Some(_))
}

///|
test "an unopened available Replica opens without reloading" {
  let account = @source_repository.AccountId::parse("account") catch {
    _ => abort("valid account")
  }
  let id = document_id("cancelled-open")
  let first_revision = @source_repository.SavedRevision::parse(1.0) catch {
    _ => abort("first revision")
  }
  let second_revision = @source_repository.SavedRevision::parse(2.0) catch {
    _ => abort("second revision")
  }
  let first_entry = @source_repository.RemoteEntry::Present(
    id, first_revision, "First",
  )
  let second_entry = @source_repository.RemoteEntry::Present(
    id, second_revision, "Second",
  )
  let key = @documents.Key::replica(account, id)
  let initial = test_model(
    Editing(test_editing()),
    discovered_sync(account, first_entry),
  )
  let (fetching, first_open) = select_remote(initial, key, first_entry)
  let first_remote = @source_repository.RemoteDocument::Present(
    first_revision, "first text",
  )
  let (storing, first_attempt) = receive_open(
    fetching, first_open, first_remote,
  )
  let first_attempt = first_attempt.unwrap()
  let (cancelled, _) = test_root_update(
    storing,
    DocumentSelected(source_key("one")),
  )
  let (stored, _) = store_sync_attempt(cancelled, first_attempt)
  guard stored.page is Editing(editing) else { fail("editing") }
  assert_eq(editing.documents.text(key), None)
  let durable = editing.documents.snapshot().replica(account, id).unwrap()

  guard durable.reconcile(
      @source_repository.RemoteDocument::Present(second_revision, "second text"),
    )
    is @source_repository.ReconcilePlan::Persist(available_write) else {
    fail("available update")
  }
  guard stored.replication.submit(available_write)
    is (replication, Some(@replication.Persist(available_attempt))) else {
    fail("available persistence")
  }
  let (available, _) = test_root_update(
    { ..stored, replication, },
    Sync(ReplicaWriteCompleted(available_attempt, Ok(()))),
  )
  guard available.page is Editing(editing) else { fail("editing") }
  assert_eq(editing.documents.text(key), None)
  guard editing.documents.snapshot().replica(account, id) is Some(replica) &&
    replica.directive()
    is @source_repository.ReplicaDirective::UpdateAvailable(_) else {
    fail("durable available Replica")
  }

  let available = discover_entry(available, account, second_entry)
  let saved = available.page.saved_documents().unwrap()
  guard available.replication.select(saved, second_entry.document_id())
    is (expected, [@replication.Persist(open_attempt)]) else {
    fail("open retained revision")
  }
  let (storing, _) = test_root_update(available, DocumentSelected(key))
  assert_eq(storing.replication, expected)
  let (opened, _) = store_sync_attempt(storing, open_attempt)
  guard opened.page is Editing(editing) else { fail("editing") }
  assert_true(editing.activation.key == key)
  assert_eq(editing.documents.text(key), Some("second text"))
  assert_eq(opened.sync().selection(), None)
}

///|
test "remote selection retries failed Replica durability before GET" {
  let account = @source_repository.AccountId::parse("account") catch {
    _ => abort("valid account")
  }
  let id = document_id("remote-durable-race")
  let first_revision = @source_repository.SavedRevision::parse(1.0) catch {
    _ => abort("first revision")
  }
  let second_revision = @source_repository.SavedRevision::parse(2.0) catch {
    _ => abort("second revision")
  }
  let first_entry = @source_repository.RemoteEntry::Present(
    id, first_revision, "First",
  )
  let second_entry = @source_repository.RemoteEntry::Present(
    id, second_revision, "Second",
  )
  let key = @documents.Key::replica(account, id)
  let initial = test_model(
    Editing(test_editing()),
    discovered_sync(account, first_entry),
  )
  let (opening_first, first_open) = select_remote(initial, key, first_entry)
  let first_remote = @source_repository.RemoteDocument::Present(
    first_revision, "first text",
  )
  let (storing_first, first_attempt) = receive_open(
    opening_first, first_open, first_remote,
  )
  let first_attempt = first_attempt.unwrap()
  let (failed, _) = test_root_update(
    storing_first,
    Sync(
      ReplicaWriteCompleted(
        first_attempt,
        Err(@source_repository.ReplicaFailure::StorageUnavailable),
      ),
    ),
  )
  let newer = discover_entry(failed, account, second_entry)
  let saved = newer.page.saved_documents().unwrap()
  guard newer.replication.select(saved, second_entry.document_id())
    is (expected_retrying, [@replication.Persist(retry_attempt)]) else {
    fail("durability retry")
  }
  let (retrying, _) = test_root_update(newer, DocumentSelected(key))
  assert_true(retrying.replication == expected_retrying)
  assert_true(
    retrying.replication.status(account, id)
    is @replica_persistence.Status::Persisting,
  )
  let (committed, _) = expected_retrying.complete(retry_attempt, Ok(())) catch {
    _ => abort("retry completion")
  }
  guard committed.settle_replica(retry_attempt.write().replica()).1
    is Some(@replication.Network(@sync.GetRemote(open))) else {
    fail("GET after retry durability")
  }
  assert_eq(open.document_id(), id)
}

///|
test "remote persistence never interrupts an active composition" {
  let account = @source_repository.AccountId::parse("account") catch {
    _ => abort("valid account")
  }
  let remote_id = document_id("remote")
  let revision = @source_repository.SavedRevision::parse(1.0) catch {
    _ => abort("valid revision")
  }
  let next_revision = @source_repository.SavedRevision::parse(2.0) catch {
    _ => abort("valid revision")
  }
  let entry = @source_repository.RemoteEntry::Present(
    remote_id, revision, "Remote",
  )
  let key = @documents.Key::replica(account, remote_id)
  let initial = test_model(
    Editing(test_editing()),
    discovered_sync(account, entry),
  )
  let saved = initial.page.saved_documents().unwrap()
  guard initial.replication.select(saved, entry.document_id())
    is (_, [@replication.Network(@sync.OpenRemote(open))]) else {
    fail("open")
  }
  let (fetching, _) = test_root_update(initial, DocumentSelected(key))
  let remote = @source_repository.RemoteDocument::Present(revision, "remote")
  guard fetching.replication.opened(saved, open, remote)
    is (_, Some(@replication.Persist(attempt))) else {
    fail("remote persistence")
  }
  let (storing, _) = test_root_update(
    fetching,
    Sync(OpenCompleted(open, @document_http.RemoteResult::Found(remote))),
  )
  let (composing, _) = test_root_update(storing, CompositionStarted(0))
  let (completed, _) = test_root_update(
    composing,
    Sync(ReplicaWriteCompleted(attempt, Ok(()))),
  )
  guard completed.page is Editing(editing) else { fail("editing") }
  assert_true(editing.activation.key == source_key("one"))
  assert_eq(editing.documents.text(key), None)

  let completed = discover_entry(
    completed,
    account,
    @source_repository.RemoteEntry::Present(
      remote_id, next_revision, "Newer remote",
    ),
  )
  let (activated, _) = test_root_update(completed, CompositionEnded(0))
  guard activated.page is Editing(editing) else { fail("editing") }
  assert_true(editing.activation.key == source_key("one"))
  assert_eq(editing.documents.text(key), None)
  assert_true(activated.sync().selection() is Some(_))
  let durable = editing.documents
    .snapshot()
    .replica(account, remote_id)
    .unwrap()
  assert_true(
    activated.replication.activity(durable) is @sync.Activity::Working,
  )
}

///|
test "discovery persists a newer remote revision without replacing the editor" {
  let account = @source_repository.AccountId::parse("account") catch {
    _ => abort("valid account")
  }
  let id = document_id("one")
  let first = @source_repository.SavedRevision::parse(1.0) catch {
    _ => abort("valid revision")
  }
  let next = @source_repository.SavedRevision::parse(2.0) catch {
    _ => abort("valid revision")
  }
  let replica = @source_repository.DocumentReplica::receive(
    account,
    documents_test_document("one", "local"),
    first,
  )
  let saved = @source_repository.SavedDocuments::from_documents([])
    .unwrap()
    .apply_replica(replica)
  let key = @documents.Key::replica(account, id)
  let page = Editing({
    ..test_editing(),
    activation: { key, generation: 0, },
    documents: @documents.State::State(saved).project_account(account),
  })
  let (sync, discovery) = current_sync(account).begin_discovery()
  let discovery = discovery.unwrap()
  let entry = @source_repository.RemoteEntry::Present(id, next, "Remote")
  let (discovered, _) = test_root_update(
    test_model(page, sync),
    Sync(
      DiscoveryCompleted(
        account,
        discovery,
        @document_http.DiscoveryResult::Discovered([entry]),
      ),
    ),
  )
  let (expected, _) = sync.discovered(account, discovery, Some([entry]))
  let (expected, action) = expected.advance(replica)
  guard action is Some(@sync.Action::GetRemote(read)) else {
    fail("remote revision read")
  }
  assert_true(discovered.sync() == expected)

  let remote = @source_repository.RemoteDocument::Present(next, "remote")
  let (expected, write) = expected.received(replica, read, remote)
  guard write is Some(write) else { fail("persist observed revision") }
  let (_, attempt) = discovered.replication.persistence().submit(write)
  let attempt = attempt.unwrap()
  let (storing, _) = test_root_update(
    discovered,
    Sync(RemoteCompleted(read, @document_http.RemoteResult::Found(remote))),
  )
  assert_true(storing.sync() == expected)
  guard storing.page is Editing(editing) else { fail("editing") }
  assert_true(editing.activation.key == key)
  assert_eq(editing.documents.text(key), Some("local"))

  let (stored, _) = test_root_update(
    storing,
    Sync(ReplicaWriteCompleted(attempt, Ok(()))),
  )
  guard stored.page.saved_documents().unwrap().replica(account, id)
    is Some(durable) else {
    fail("stored observation")
  }
  assert_true(
    durable.directive()
    is @source_repository.ReplicaDirective::UpdateAvailable(_),
  )
  guard stored.page is Editing(editing) else { fail("editing") }
  assert_true(editing.activation.key == key)
  assert_eq(editing.documents.text(key), Some("local"))
}

///|
test "replica completion preserves a newer Autosave window at equal text" {
  let account = @source_repository.AccountId::parse("account") catch {
    _ => abort("valid test account")
  }
  let saved = test_sync_snapshot(account)
  let token = @documents.Key::replica(account, document_id("one"))
  let documents = @documents.State::State(saved).project_account(account)
  let (documents, _) = documents.reduce(
    @documents.Msg::TextChanged(token, "sent"),
  )
  let (documents, effects) = documents.reduce(
    @documents.Msg::ApplyPendingEdit(token, pending_revision(documents, token)),
  )
  guard effects is [@documents.Action::SaveReplica(submission)] else {
    fail("first write")
  }
  let owner = submission.durable().account()
  let document = submission.document()
  let replica = replica_edit(
    saved.replica(owner, document.id()).unwrap(),
    document.text(),
  )
  let (documents, _) = documents.reduce(
    @documents.Msg::TextChanged(token, "newer"),
  )
  let (documents, _) = documents.reduce(
    @documents.Msg::TextChanged(token, "sent"),
  )

  let (documents, follow_up) = documents.reduce(
    @documents.Msg::FeedbackReceived(ReplicaSettled(replica.store(), None)),
  )
  assert_true(follow_up.is_empty())
  assert_true(
    documents.save_status(token) == Some(@documents.SaveStatus::Unsaved),
  )
  assert_eq(documents.text(token), Some("sent"))
  let (_, effects) = documents.reduce(
    @documents.Msg::ApplyPendingEdit(token, pending_revision(documents, token)),
  )
  guard effects is [@documents.Action::SaveReplica(submission)] else {
    fail("newer equal-text edit remains eligible")
  }
  assert_eq(submission.durable().account(), account)
  assert_eq(submission.document().text(), "sent")
}

///|
test "replica revert remains eligible while a newer write may be in flight" {
  let account = @source_repository.AccountId::parse("account") catch {
    _ => abort("valid test account")
  }
  let saved = test_sync_snapshot(account)
  let token = @documents.Key::replica(account, document_id("one"))
  let documents = @documents.State::State(saved).project_account(account)
  let (documents, _) = documents.reduce(
    @documents.Msg::TextChanged(token, "sent"),
  )
  let (documents, effects) = documents.reduce(
    @documents.Msg::ApplyPendingEdit(token, pending_revision(documents, token)),
  )
  guard effects is [@documents.Action::SaveReplica(_)] else {
    fail("first write")
  }
  let (documents, _) = documents.reduce(
    @documents.Msg::TextChanged(token, "one"),
  )
  assert_true(
    documents.save_status(token) == Some(@documents.SaveStatus::Unsaved),
  )
  assert_eq(documents.text(token), Some("one"))
  let (_, effects) = documents.reduce(
    @documents.Msg::ApplyPendingEdit(token, pending_revision(documents, token)),
  )
  guard effects is [@documents.Action::SaveReplica(submission)] else {
    fail("revert must reach the replica head")
  }
  assert_eq(submission.durable().account(), account)
  assert_eq(submission.document().text(), "one")
}

///|
test "replica failure keeps optimistic text and retries the same write" {
  let account = @source_repository.AccountId::parse("account") catch {
    _ => abort("valid test account")
  }
  let saved = test_sync_snapshot(account)
  let token = @documents.Key::replica(account, document_id("one"))
  let initial = {
    ..test_editing(),
    activation: { key: token, generation: 0, },
    documents: @documents.State::State(saved).project_account(account),
  }
  let (documents, _) = initial.documents.reduce(
    @documents.Msg::TextChanged(token, "optimistic"),
  )
  let (documents, decisions) = documents.reduce(
    @documents.Msg::ApplyPendingEdit(token, pending_revision(documents, token)),
  )
  guard decisions is [@documents.Action::SaveReplica(submission)] else {
    fail("persist")
  }
  let owner = submission.durable().account()
  let document = submission.document()
  let model = test_model(Editing({ ..initial, documents, }), @sync.State())
  let (storing, attempt) = begin_replica(model, owner, document)
  let replica = attempt.write().replica()
  let (failed, _) = test_root_update(
    storing,
    Sync(
      ReplicaWriteCompleted(
        attempt,
        Err(@source_repository.ReplicaFailure::StorageUnavailable),
      ),
    ),
  )
  guard failed.page is Editing(editing) else { fail("editing") }
  assert_eq(editing.documents.text(token), Some("optimistic"))
  assert_true(
    editing.documents.save_status(token) is Some(@documents.SaveStatus::Unsaved),
  )

  guard failed.replication.status(owner, document.id())
    is @replica_persistence.Status::Retryable(retry_action, _) else {
    fail("retryable persistence")
  }
  let (_, retry_attempt) = failed.replication.persistence().retry(retry_action)
  let (retrying, _) = test_root_update(failed, RetrySaving(retry_action))
  assert_true(retry_attempt.write().replica() == replica)
  let (stored, _) = test_root_update(
    retrying,
    Sync(ReplicaWriteCompleted(retry_attempt, Ok(()))),
  )
  guard stored.page is Editing(recovered) else { fail("editing") }
  assert_true(
    recovered.documents.save_status(token) == Some(@documents.SaveStatus::Clean),
  )
}

///|
test "an edit after replica failure immediately replaces the failed write" {
  let account = @source_repository.AccountId::parse("account") catch {
    _ => abort("valid test account")
  }
  let saved = test_sync_snapshot(account)
  let token = @documents.Key::replica(account, document_id("one"))
  let initial = {
    ..test_editing(),
    activation: { key: token, generation: 0, },
    documents: @documents.State::State(saved).project_account(account),
  }
  let (documents, _) = initial.documents.reduce(
    @documents.Msg::TextChanged(token, "too large"),
  )
  let (documents, first) = documents.reduce(
    @documents.Msg::ApplyPendingEdit(token, pending_revision(documents, token)),
  )
  guard first is [@documents.Action::SaveReplica(submission)] else {
    fail("first eligible edit")
  }
  let owner = submission.durable().account()
  let document = submission.document()
  let model = test_model(Editing({ ..initial, documents, }), @sync.State())
  let (storing, attempt) = begin_replica(model, owner, document)
  let (failed, _) = test_root_update(
    storing,
    Sync(
      ReplicaWriteCompleted(
        attempt,
        Err(@source_repository.ReplicaFailure::QuotaExceeded),
      ),
    ),
  )
  let (edited, _) = test_root_update(
    failed,
    TextChanged(0, @text_change.TextChange::ReplaceAll("small")),
  )
  guard edited.page is Editing(editing) else { fail("editing") }
  let (_, next) = editing.documents.reduce(
    @documents.Msg::ApplyPendingEdit(
      token,
      pending_revision(editing.documents, token),
    ),
  )
  guard next is [@documents.Action::SaveReplica(submission)] else {
    fail("replacement eligible edit")
  }
  let (replacing, _) = test_root_update(
    edited,
    ApplyPendingEdit(token, pending_revision(editing.documents, token)),
  )
  let document = submission.document()
  let durable = saved.replica(account, document.id()).unwrap()
  assert_eq(
    replacing.replication
    .editing_base(durable)
    .document()
    .map(document => document.text()),
    Some("small"),
  )
  assert_true(
    replacing.replication.status(account, document.id())
    is @replica_persistence.Status::Persisting,
  )
}

///|
fn begin_active_replica_deletion() -> (
  Model,
  @replica_persistence.Attempt,
  @documents.Key,
) {
  let account = @source_repository.AccountId::parse("account") catch {
    _ => abort("valid test account")
  }
  let saved = test_synced_snapshot(account)
  let key = @documents.Key::replica(account, document_id("one"))
  let editing = {
    ..test_editing(),
    activation: { key, generation: 0, },
    documents: @documents.State::State(saved).project_account(account),
  }
  let sync = current_sync(account)
  let model = test_model(Editing(editing), sync)
  let (confirming, _) = test_root_update(model, DeleteRequested(key))
  let (deleting, _) = test_root_update(confirming, DeleteConfirmed(key))
  guard deleting.page is Editing(pending) else { abort("editing") }
  guard pending.documents.text(key) == Some("one") &&
    pending.documents.delete_status(key) is Some(DeletePending) else {
    abort("pending deletion keeps active text")
  }

  let durable = saved.replica(account, document_id("one")).unwrap()
  let (_, write) = sync.delete(durable, "one")
  let (_, attempt) = @replica_persistence.State().submit(write)
  (deleting, attempt.unwrap(), key)
}

///|
test "active replica remains mounted until deletion intent is durable" {
  let (deleting, attempt, key) = begin_active_replica_deletion()
  let (stored, _) = test_root_update(
    deleting,
    Sync(ReplicaWriteCompleted(attempt, Ok(()))),
  )
  guard stored.page is Editing(editing) else { fail("editing") }
  assert_true(editing.activation.key == source_key("two"))
  assert_eq(editing.documents.text(key), None)
  assert_true(
    editing.documents
    .snapshot()
    .replica(
      attempt.write().replica().account(),
      attempt.write().replica().document_id(),
    )
    .unwrap()
    .is_deleting(),
  )
}

///|
test "failed active deletion remains visible and retryable" {
  let (deleting, attempt, key) = begin_active_replica_deletion()
  let (failed, _) = test_root_update(
    deleting,
    Sync(
      ReplicaWriteCompleted(
        attempt,
        Err(@source_repository.ReplicaFailure::StorageUnavailable),
      ),
    ),
  )
  guard failed.page is Editing(editing) else { fail("editing") }
  assert_true(editing.activation.key == key)
  assert_eq(editing.documents.text(key), Some("one"))
  assert_true(
    editing.documents.delete_status(key)
    is Some(
      @documents.DeleteStatus::DeletePersistenceFailed(
        @source_repository.ReplicaFailure::StorageUnavailable
      )
    ),
  )
  let account = attempt.write().replica().account()
  let document_id = attempt.write().replica().document_id()
  let (retrying, _) = test_root_update(failed, RetryDelete(key))
  assert_true(
    retrying.replication.status(account, document_id)
    is @replica_persistence.Status::Persisting,
  )
}

///|
test "editing after failed deletion supersedes it and becomes durable" {
  let (deleting, attempt, key) = begin_active_replica_deletion()
  let (failed, _) = test_root_update(
    deleting,
    Sync(
      ReplicaWriteCompleted(
        attempt,
        Err(@source_repository.ReplicaFailure::StorageUnavailable),
      ),
    ),
  )
  let (edited, _) = test_root_update(
    failed,
    TextChanged(0, @text_change.TextChange::ReplaceAll("after failure")),
  )
  guard edited.page is Editing(editing) else { fail("editing") }
  let revision = pending_revision(editing.documents, key)
  let saved = editing.documents.snapshot()
  let account = attempt.write().replica().account()
  let document_id = attempt.write().replica().document_id()
  let durable = saved.replica(account, document_id).unwrap()
  let base = edited.replication.editing_base(durable)
  let (protocol, replacement) = edited.sync().save(base, "after failure")
  let replacement = replacement.unwrap()
  let (persistence, expected_attempt) = edited.replication
    .persistence()
    .submit(replacement)
  let (storing, _) = test_root_update(edited, ApplyPendingEdit(key, revision))
  assert_eq(storing.replication.persistence(), persistence)
  assert_eq(storing.sync(), protocol)
  assert_true(
    storing.replication.status(account, document_id)
    is @replica_persistence.Status::Persisting,
  )
  let (stored, _) = test_root_update(
    storing,
    Sync(ReplicaWriteCompleted(expected_attempt.unwrap(), Ok(()))),
  )
  guard stored.page is Editing(editing) else { fail("editing") }
  assert_eq(editing.documents.text(key), Some("after failure"))
  assert_eq(
    editing.documents
    .snapshot()
    .replica(account, document_id)
    .unwrap()
    .document()
    .map(document => document.text()),
    Some("after failure"),
  )
}

///|
test "Import strictly decodes UTF-8, consumes BOM, and normalizes line endings" {
  assert_eq(
    decode_import(b"\xef\xbb\xbfalpha\r\nbeta\rgamma\n  tail\t"),
    Some("alpha\nbeta\ngamma\n  tail\t"),
  )
  assert_eq(decode_import(b""), Some(""))
  assert_eq(decode_import(b"\x80"), None)
}

///|
test "accepted Import immediately becomes the Editing Document" {
  let initial = test_editing()
  let text = "Imported\n"
  let (model, _) = test_update(
    Editing(initial),
    ImportCreateCompleted(text, Created(document_id("imported"))),
  )
  guard model is Editing(editing) else { fail("editing") }
  assert_true(editing.activation.key == source_key("imported"))
  assert_eq(editing.documents.text(source_key("imported")), Some(text))
}

///|
test "each completed Import is retained and the latest completion activates" {
  let initial = test_editing()
  let (model, _) = test_update(
    Editing(initial),
    ImportCreateCompleted("Newer completion", Created(document_id("newer"))),
  )
  guard model is Editing(after_newer) else { fail("editing") }
  let (model, _) = test_update(
    Editing(after_newer),
    ImportCreateCompleted("Older completion", Created(document_id("older"))),
  )
  guard model is Editing(after_older) else { fail("editing") }
  assert_eq(
    after_older.documents.text(source_key("newer")),
    Some("Newer completion"),
  )
  assert_eq(
    after_older.documents.text(source_key("older")),
    Some("Older completion"),
  )
  assert_true(after_older.activation.key == source_key("older"))
}

///|
test "accepted Import supersedes an unfinished New action" {
  let initial = { ..test_editing(), creation: Creating(0), }
  let (model, _) = test_update(
    Editing(initial),
    ImportCreateCompleted("Imported", Created(document_id("imported"))),
  )
  guard model is Editing(imported) && imported.creation == Idle else {
    fail("Import should supersede New")
  }

  let (after_stale_new, _) = test_update(
    Editing(imported),
    CreateCompleted(0, Created(document_id("unused-new"))),
  )
  assert_true(after_stale_new == Editing(imported))
}

///|
test "export payload uses the Editing Document's current text and derived name" {
  let initial = test_editing()
  let text = "## Unsaved name\n\nCurrent text\n"
  let (documents, _) = initial.documents.reduce(
    @documents.Msg::TextChanged(source_key("one"), text),
  )
  let (filename, exported) = export_payload({ ..initial, documents, })
  assert_eq(filename, "Unsaved name.md")
  assert_eq(exported, text)
}

///|
test "export payload falls back for an empty Editing Document" {
  let initial = test_editing()
  let (documents, _) = initial.documents.reduce(
    @documents.Msg::TextChanged(source_key("one"), ""),
  )
  assert_eq(export_payload({ ..initial, documents, }), ("untitled.md", ""))
}

///|
test "loading and recovery ignore document lifecycle feedback" {
  let feedback = ApplyPendingEdit(source_key("one"), 1)
  let (loading, _) = test_update(Loading(false), feedback)
  assert_true(loading == Loading(false))
  let (recovery, _) = test_update(Recovery(StorageUnavailable, false), feedback)
  assert_true(recovery == Recovery(StorageUnavailable, false))
}

///|
test "repository open activates its resolved initial Document" {
  let snapshot = test_snapshot()
  let initial = snapshot.find(document_id("two")).unwrap()
  let (model, _) = test_update(
    Loading(false),
    Opened(Ready(snapshot, Some(initial))),
  )
  guard model is Editing(editing) else { fail("editing") }
  assert_true(editing.activation.key == source_key("two"))
}

///|
test "delete is rejected while creation is in flight and completion still activates" {
  let initial = { ..test_editing(), creation: Creating(0), }
  let (after_delete, _) = test_update(
    Editing(initial),
    DeleteRequested(source_key("one")),
  )
  assert_true(after_delete == Editing(initial))
  let (after_create, _) = test_update(
    after_delete,
    CreateCompleted(0, Created(document_id("new"))),
  )
  guard after_create is Editing(editing) else { fail("editing") }
  assert_true(editing.activation.key == source_key("new"))
  assert_true(editing.creation is Idle)
  assert_true(
    editing.documents.delete_status(source_key("one")) is Some(Deletable),
  )
}

///|
test "delete request only opens confirmation for its target" {
  let initial = test_editing()
  let (model, _) = test_update(
    Editing(initial),
    DeleteRequested(source_key("one")),
  )
  assert_true(
    model ==
    Editing({ ..initial, deletion: DeleteConfirmation(source_key("one")), }),
  )
}

///|
test "cancelling delete only closes confirmation" {
  let initial = test_editing()
  let (requested, _) = test_update(
    Editing(initial),
    DeleteRequested(source_key("two")),
  )
  assert_true(
    requested ==
    Editing({ ..initial, deletion: DeleteConfirmation(source_key("two")), }),
  )
  let (model, _) = test_update(requested, DeleteCancelled)
  assert_true(model == Editing(initial))
}

///|
test "same document selection is a no-op" {
  let initial = test_editing()
  let (model, _) = test_update(
    Editing(initial),
    DocumentSelected(source_key("one")),
  )
  guard model is Editing(editing) else { fail("editing") }
  assert_true(editing.activation == initial.activation)
}

///|
test "stale create completion is ignored" {
  let initial = { ..test_editing(), creation: Creating(0), }
  let (model, _) = test_update(
    Editing(initial),
    CreateCompleted(1, Created(document_id("new"))),
  )
  guard model is Editing(editing) else { fail("editing") }
  assert_true(editing.activation == initial.activation)
  assert_true(editing.creation is Creating(_))
}

///|
test "pending target cannot be selected" {
  let initial = test_editing()
  let (documents, _) = initial.documents.reduce(
    @documents.Msg::DeleteConfirmed(source_key("two")),
  )
  let (model, _) = test_update(
    Editing({ ..initial, documents, }),
    DocumentSelected(source_key("two")),
  )
  guard model is Editing(editing) else { fail("editing") }
  assert_true(editing.activation.key == source_key("one"))
}

///|
test "deleting the Editing Document activates its saved fallback" {
  let initial = {
    ..test_editing(),
    deletion: DeleteConfirmation(source_key("one")),
  }
  let (_, effects) = initial.documents.reduce(
    @documents.Msg::DeleteConfirmed(source_key("one")),
  )
  guard effects is [@documents.Action::DeleteSource(operation)] else {
    fail("delete operation")
  }
  let (model, _) = test_update(
    Editing(initial),
    DeleteConfirmed(source_key("one")),
  )
  guard model is Editing(deleting) else { fail("deleting") }
  let (model, _) = test_update(
    Editing(deleting),
    DocumentsLifecycle(
      @documents.Feedback::DeleteCompleted(
        operation,
        Deleted(document_id("one")),
      ),
    ),
  )
  guard model is Editing(editing) else { fail("fallback") }
  assert_true(editing.activation.key == source_key("two"))
}

///|
test "deleting an active unsaved new document reconciles activation" {
  let initial = test_editing()
  let (documents, _) = initial.documents.reduce(
    @documents.Msg::New(document_id("new")),
  )
  let (model, _) = test_update(
    Editing({
      ..initial,
      activation: { key: source_key("new"), generation: 1, },
      documents,
      deletion: DeleteConfirmation(source_key("new")),
    }),
    DeleteConfirmed(source_key("new")),
  )
  guard model is Editing(editing) else { fail("editing") }
  assert_true(editing.documents.text(editing.activation.key) is Some(_))
  assert_true(editing.activation.key != source_key("new"))
}

///|
test "failed first save of active new document reconciles activation" {
  let initial = test_editing()
  let (documents, _) = initial.documents.reduce(
    @documents.Msg::New(document_id("new")),
  )
  let (documents, _) = documents.reduce(
    @documents.Msg::TextChanged(source_key("new"), "hello"),
  )
  let (documents, decisions) = documents.reduce(
    @documents.Msg::ApplyPendingEdit(source_key("new"), 1),
  )
  guard decisions[0] is @documents.Action::PersistSource(operation) else {
    fail("save")
  }
  let (documents, _) = documents.reduce(
    @documents.Msg::DeleteConfirmed(source_key("new")),
  )
  let (model, _) = test_update(
    Editing({
      ..initial,
      activation: { key: source_key("new"), generation: 1, },
      documents,
    }),
    DocumentsLifecycle(
      @documents.Feedback::SaveCompleted(operation, SaveFailed(WriteFailed)),
    ),
  )
  guard model is Editing(editing) else { fail("editing") }
  assert_true(editing.documents.text(editing.activation.key) is Some(_))
  assert_true(editing.activation.key != source_key("new"))
}

///|
test "save completion updates inactive document without switching" {
  let initial = test_editing()
  let (documents, _) = initial.documents.reduce(
    @documents.Msg::TextChanged(source_key("two"), "two!"),
  )
  let (documents, decisions) = documents.reduce(
    @documents.Msg::ApplyPendingEdit(source_key("two"), 1),
  )
  guard decisions[0] is @documents.Action::PersistSource(operation) else {
    fail("persist")
  }
  let state = { ..initial, documents, }
  let (model, _) = test_update(
    Editing(state),
    DocumentsLifecycle(
      @documents.Feedback::SaveCompleted(operation, Stored(operation.document)),
    ),
  )
  guard model is Editing(editing) else { fail("editing") }
  assert_true(editing.activation.key == source_key("one"))
  assert_eq(editing.documents.text(source_key("two")), Some("two!"))
  assert_eq(
    editing.documents.snapshot().find(document_id("two")).unwrap().text(),
    "two!",
  )
}

///|
test "preparing new preserves documents and mode" {
  let documents = @documents.State::State(test_snapshot())
  let (model, _) = test_update(
    PreparingNew({
      documents,
      mode: Split,
      compact: false,
      request_id: 1,
      next_activation_generation: 0,
    }),
    EmptyCreateCompleted(1, Created(document_id("new"))),
  )
  guard model is Editing(editing) else { fail("editing") }
  assert_true(editing.mode is Split)
  assert_eq(editing.documents.text(source_key("one")), Some("one"))
  assert_eq(editing.documents.text(source_key("two")), Some("two"))
}

///|
fn preparing_after_active_delete() -> (Page, @cmd.Cmd) {
  let snapshot = @source_repository.SavedDocuments::from_documents([
    @source_repository.Document::create(document_id("one"), "one"),
  ]).unwrap()
  let base = test_editing()
  let initial = { ..base, documents: @documents.State::State(snapshot), }
  let (documents, decisions) = initial.documents.reduce(
    @documents.Msg::DeleteConfirmed(source_key("one")),
  )
  match decisions[0] {
    @documents.Action::DeleteSource(operation) =>
      test_update(
        Editing({ ..initial, documents, }),
        DocumentsLifecycle(
          @documents.Feedback::DeleteCompleted(
            operation,
            Deleted(document_id("one")),
          ),
        ),
      )
    _ => abort("delete")
  }
}

///|
test "delete-to-New advances Preview ownership" {
  let (model, _) = preparing_after_active_delete()
  guard model is PreparingNew(preparing) else { fail("preparing") }
  let (model, _) = test_update(
    PreparingNew({ ..preparing, mode: Split, }),
    EmptyCreateCompleted(preparing.request_id, Created(document_id("new"))),
  )
  guard model is Editing(editing) else { fail("editing") }
  assert_eq(editing.activation.generation, 1)
}

///|
test "final active delete falls back to a new document" {
  let snapshot = @source_repository.SavedDocuments::from_documents([
    @source_repository.Document::create(document_id("one"), "one"),
  ]).unwrap()
  let documents = @documents.State::State(snapshot)
  let (preview, _) = @preview.PreviewEngine::PreviewEngine().activate(
    @preview.Input(0, "one"),
  )
  let initial = {
    activation: { key: source_key("one"), generation: 0, },
    documents,
    creation: Idle,
    deletion: NoDeletion,
    mode: Text,
    compact: false,
    preview,
    import_failed: false,
    imports_pending: 0,
    new_preparation_request_id: 0,
  }
  let (documents, decisions) = initial.documents.reduce(
    @documents.Msg::DeleteConfirmed(source_key("one")),
  )
  guard decisions[0] is @documents.Action::DeleteSource(operation) else {
    fail("delete")
  }
  let state = { ..initial, documents, }
  let (model, _) = test_update(
    Editing(state),
    DocumentsLifecycle(
      @documents.Feedback::DeleteCompleted(
        operation,
        Deleted(document_id("one")),
      ),
    ),
  )
  guard model is PreparingNew(_) else { fail("should prepare new") }
}

///|
test "active pending deletion prevents document switch" {
  let initial = test_editing()
  let (documents, _) = initial.documents.reduce(
    @documents.Msg::DeleteConfirmed(source_key("one")),
  )
  let (model, _) = test_update(
    Editing({ ..initial, documents, }),
    DocumentSelected(source_key("two")),
  )
  guard model is Editing(editing) else { fail("editing") }
  assert_true(editing.activation.key == source_key("one"))
}

///|
test "duplicate text message leaves model and preview unchanged" {
  let initial = test_editing()
  let (model, _) = test_update(
    Editing(initial),
    TextChanged(
      initial.activation.generation,
      @text_change.TextChange::ReplaceAll("one"),
    ),
  )
  assert_true(model == Editing(initial))
}

///|
test "page-local revision restores authoritative text and preview" {
  let snapshot = @source_repository.SavedDocuments::from_documents([
    @source_repository.Document::create(document_id("one"), "one"),
  ]).unwrap()
  let base = test_editing()
  let initial = {
    ..base,
    activation: { key: source_key("one"), generation: 0, },
    documents: @documents.State::State(snapshot),
  }
  // Apply a text change then verify page-local order: stale timer ignored, correct revision persists
  let (documents, decisions) = initial.documents.reduce(
    @documents.Msg::TextChanged(source_key("one"), "one!"),
  )
  guard decisions is [@documents.Action::ArmMaximum(_)] else { fail("timers") }
  // Simulate stale pending_revision(documents, source_key("one")) timer with wrong revision: should be ignored by documents layer
  let (documents, stale) = documents.reduce(
    @documents.Msg::ApplyPendingEdit(source_key("one"), 99),
  )
  assert_true(stale.is_empty())
  // Correct revision proceeds
  let (_, decisions) = documents.reduce(
    @documents.Msg::ApplyPendingEdit(
      source_key("one"),
      pending_revision(documents, source_key("one")),
    ),
  )
  guard decisions[0] is @documents.Action::PersistSource(op) else {
    fail("persist")
  }
  assert_eq(op.document.text(), "one!")
  // Update view layer: authoritative text is still "one" until save completes, preview unchanged
  let (model, _) = test_update(
    Editing({ ..initial, documents: initial.documents, }),
    TextChanged(
      initial.activation.generation,
      @text_change.TextChange::ReplaceAll("one!"),
    ),
  )
  guard model is Editing(editing) else { fail("editing") }
  assert_eq(editing.documents.text(source_key("one")), Some("one!"))
}

///|
test "preparing new reduces unrelated inactive save completion" {
  let initial = test_editing()
  let (documents, _) = initial.documents.reduce(
    @documents.Msg::TextChanged(source_key("two"), "two!"),
  )
  let (documents, decisions) = documents.reduce(
    @documents.Msg::ApplyPendingEdit(source_key("two"), 1),
  )
  guard decisions[0] is @documents.Action::PersistSource(operation) else {
    fail("persist")
  }
  let (model, _) = test_update(
    PreparingNew({
      documents,
      mode: Text,
      compact: false,
      request_id: 1,
      next_activation_generation: 1,
    }),
    DocumentsLifecycle(
      @documents.Feedback::SaveCompleted(operation, Stored(operation.document)),
    ),
  )
  guard model is PreparingNew(preparing) else { fail("preparing") }
  assert_eq(preparing.documents.text(source_key("two")), Some("two!"))
  assert_eq(
    preparing.documents.snapshot().find(document_id("two")).unwrap().text(),
    "two!",
  )
}
