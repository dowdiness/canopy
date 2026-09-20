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
    new_preparation_request_id: 0,
  }
}

///|
fn test_update(model : Page, msg : Msg) -> (Page, @cmd.Cmd) {
  update_page(
    model,
    msg,
    @cmd.Emit(_ => @cmd.none),
    @text_area.TextArea::TextArea("loomark-test-text"),
    @preview.PreviewEngine::PreviewEngine(),
  )
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
fn begin_checkpoint(
  model : Model,
  account : @source_repository.AccountId,
  document : @source_repository.Document,
) -> (Model, @sync.RequestId, @source_repository.SyncCheckpoint) {
  let saved = model.page.saved_documents().unwrap()
  let durable = saved.checkpoint(account, document.id()).unwrap()
  let (sync, attempt) = model.sync.save(durable, document.text())
  let attempt = attempt.unwrap()
  ({ ..model, sync, }, attempt.request_id(), attempt.write().checkpoint())
}

///|
fn test_sync_snapshot(
  account : @source_repository.AccountId,
) -> @source_repository.SavedDocuments {
  let document = @source_repository.Document::create(document_id("one"), "one")
  let saved = @source_repository.SavedDocuments::from_documents([
    @source_repository.Document::create(document_id("two"), "two"),
  ]).unwrap()
  let checkpoint = @source_repository.SyncCheckpoint::enroll(account, document)
  saved.apply_checkpoint(checkpoint) catch {
    _ => abort("valid test checkpoint")
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
) -> (@source_repository.SavedDocuments, @source_repository.SyncCheckpoint) {
  let document = documents_test_document("one", "local")
  let enrolled = @source_repository.SyncCheckpoint::enroll(account, document)
  guard enrolled.plan_save() is @source_repository.OperationPlan::Start(draft) else {
    abort("save draft")
  }
  let checkpoint = draft.start(sync_operation_id()).checkpoint()
  let saved = @source_repository.SavedDocuments::from_documents([]).unwrap()
  (
    saved.apply_checkpoint(checkpoint) catch {
      _ => abort("valid pending checkpoint")
    },
    checkpoint,
  )
}

///|
fn current_sync(account : @source_repository.AccountId) -> @sync.State {
  let (state, lookup_id) = @sync.State().begin_lookup()
  state.resolved(lookup_id, @sync.Resolved(account, "Writer")).0
}

///|
fn checkpoint_edit(
  checkpoint : @source_repository.SyncCheckpoint,
  text : String,
) -> @source_repository.SyncCheckpoint {
  guard checkpoint.edit(text) is @source_repository.EditPlan::Persist(write) else {
    abort("checkpoint edit")
  }
  write.checkpoint()
}

///|
test "compact viewport preserves the fractional breakpoint boundary" {
  assert_true(compact_viewport(640.0))
  assert_true(!compact_viewport(640.5))
}

///|
test "repository open starts account lookup with its saved checkpoints" {
  let account = @source_repository.AccountId::parse("account") catch {
    _ => abort("valid test account")
  }
  let saved = test_sync_snapshot(account)
  let initial_document = saved.find(document_id("two")).unwrap()
  let (opened, _) = test_root_update(
    { page: Loading(false), sync: @sync.State(), },
    Opened(Ready(saved, Some(initial_document))),
  )
  guard opened.sync.session() is @sync.Resolving(lookup_id) else {
    fail("account lookup")
  }
  let (resolved, _) = test_root_update(
    opened,
    Sync(AccountResolved(lookup_id, @sync.Resolved(account, "Writer"))),
  )

  guard resolved.sync.session() is @sync.Current(resolved_account, "Writer") else {
    fail("resolved account")
  }
  assert_true(resolved_account == account)
  guard resolved.page is Editing(editing) else { fail("editing") }
  let token = @documents.Key::checkpoint(account, document_id("one"))
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
      key: @documents.Key::checkpoint(account, document_id("one")),
      generation: 0,
    },
    documents: @documents.State::State(saved),
  })
  let (resolving, lookup_id) = @sync.State().begin_lookup()
  let (resolved, _) = resolving.resolved(
    lookup_id,
    @sync.Resolved(account, "Writer"),
  )
  let checkpoint = saved.checkpoint(account, document_id("one")).unwrap()
  let (expected, action) = resolved.drive(checkpoint)
  let expected = expected.begin_discovery().0
  assert_true(action is Some(@sync.Action::CreateOperation(_, _, _)))

  let (model, _) = test_root_update(
    { page, sync: resolving, },
    Sync(AccountResolved(lookup_id, @sync.Resolved(account, "Writer"))),
  )
  assert_true(model.sync == expected)
}

///|
test "delivery receipt enters the checkpoint writer before becoming durable" {
  let account = @source_repository.AccountId::parse("account") catch {
    _ => abort("valid test account")
  }
  let (saved, checkpoint) = pending_sync_snapshot(account)
  let page = Editing({
    ..test_editing(),
    activation: {
      key: @documents.Key::checkpoint(account, document_id("one")),
      generation: 0,
    },
    documents: @documents.State::State(saved).project_account(account),
  })
  let (sync, action) = current_sync(account).drive(checkpoint)
  guard action is Some(@sync.Action::Deliver(effect, _, _, _)) else {
    fail("delivery")
  }
  let revision = @source_repository.SavedRevision::parse(1.0) catch {
    _ => abort("valid revision")
  }
  let (expected, attempt) = sync.acknowledged(
    checkpoint,
    effect,
    sync_operation_id(),
    revision,
  )
  let attempt = attempt.unwrap()
  let (acknowledging, _) = test_root_update(
    { page, sync, },
    Sync(
      DeliveryCompleted(
        effect,
        account,
        document_id("one"),
        sync_operation_id(),
        @document_http.DeliveryResult::Acknowledged(revision),
      ),
    ),
  )
  assert_true(acknowledging.sync == expected)
  assert_true(
    acknowledging.page
    .saved_documents()
    .unwrap()
    .checkpoint(account, document_id("one")) ==
    Some(checkpoint),
  )

  let (stored, _) = test_root_update(
    acknowledging,
    Sync(
      CheckpointCompleted(
        attempt.request_id(),
        @source_repository.CheckpointStored(attempt.write().checkpoint()),
      ),
    ),
  )
  assert_true(
    stored.page
    .saved_documents()
    .unwrap()
    .checkpoint(account, document_id("one"))
    .unwrap()
    .directive()
    is @source_repository.SyncDirective::Synchronized,
  )
}

///|
test "failed acknowledgment exposes the newest queued text for retry" {
  let account = @source_repository.AccountId::parse("account") catch {
    _ => abort("valid test account")
  }
  let (saved, checkpoint) = pending_sync_snapshot(account)
  let token = @documents.Key::checkpoint(account, document_id("one"))
  let page = Editing({
    ..test_editing(),
    activation: { key: token, generation: 0, },
    documents: @documents.State::State(saved).project_account(account),
  })
  guard current_sync(account).drive(checkpoint)
    is (sync, Some(@sync.Action::Deliver(effect, _, _, _))) else {
    fail("delivery")
  }
  let revision = @source_repository.SavedRevision::parse(1.0) catch {
    _ => abort("valid revision")
  }
  let (sync, acknowledgment) = sync.acknowledged(
    checkpoint,
    effect,
    sync_operation_id(),
    revision,
  )
  let acknowledgment = acknowledgment.unwrap()
  let model = { page, sync, }
  let (model, _) = test_root_update(
    model,
    TextChanged(
      { key: token, generation: 0, },
      @text_change.TextChange::ReplaceAll("newer"),
    ),
  )
  guard model.page is Editing(editing) else { fail("editing") }
  let (model, _) = test_root_update(
    model,
    ApplyPendingEdit(token, pending_revision(editing.documents, token)),
  )
  let newer = documents_test_document("one", "newer")
  let (model, _) = test_root_update(model, SaveCheckpoint(account, newer))

  let (failed, _) = test_root_update(
    model,
    Sync(
      CheckpointCompleted(
        acknowledgment.request_id(),
        @source_repository.CheckpointFailed(
          acknowledgment.write().checkpoint(),
          @source_repository.CheckpointFailure::StorageUnavailable,
        ),
      ),
    ),
  )
  guard failed.page is Editing(editing) else { fail("editing") }
  assert_true(
    editing.documents.save_status(token)
    is Some(@documents.SaveStatus::SaveFailed(StorageUnavailable)),
  )

  let durable = editing.documents
    .snapshot()
    .checkpoint(account, document_id("one"))
    .unwrap()
  let (expected, retry) = failed.sync.save(durable, "newer")
  let retry = retry.unwrap()
  let (retrying, _) = test_root_update(failed, SaveCheckpoint(account, newer))
  assert_true(retrying.sync == expected)
  let (stored, _) = test_root_update(
    retrying,
    Sync(
      CheckpointCompleted(
        retry.request_id(),
        @source_repository.CheckpointStored(retry.write().checkpoint()),
      ),
    ),
  )
  assert_eq(
    stored.page
    .saved_documents()
    .unwrap()
    .checkpoint(account, document_id("one"))
    .unwrap()
    .document()
    .text(),
    "newer",
  )
}

///|
test "visibility restore refreshes the account but hiding does not" {
  let account = @source_repository.AccountId::parse("account") catch {
    _ => abort("valid test account")
  }
  let model = { page: Editing(test_editing()), sync: current_sync(account), }
  let (hidden, _) = test_root_update(model, VisibilityChanged(true))
  assert_true(
    hidden.sync.session() is @sync.Current(current, _) && current == account,
  )
  let (restored, _) = test_root_update(hidden, VisibilityChanged(false))
  assert_true(restored.sync.session() is @sync.Resolving(_))

  let unavailable = { page: Editing(test_editing()), sync: @sync.State(), }
  let (recovering, _) = test_root_update(unavailable, VisibilityChanged(false))
  assert_true(recovering.sync.session() is @sync.Resolving(_))
}

///|
test "account switch defers a conflict fetch until its account is current" {
  let account_a = @source_repository.AccountId::parse("account-a") catch {
    _ => abort("valid account")
  }
  let account_b = @source_repository.AccountId::parse("account-b") catch {
    _ => abort("valid account")
  }
  let (saved, checkpoint) = pending_sync_snapshot(account_a)
  let page = Editing({
    ..test_editing(),
    activation: {
      key: @documents.Key::checkpoint(account_a, document_id("one")),
      generation: 0,
    },
    documents: @documents.State::State(saved).project_account(account_a),
  })
  guard current_sync(account_a).drive(checkpoint)
    is (sync, Some(@sync.Action::Deliver(effect, _, _, _))) else {
    fail("delivery")
  }
  let (sync, lookup) = sync.begin_lookup()
  let (sync, _) = sync.resolved(lookup, @sync.Resolved(account_b, "B"))
  let (deferred, _) = test_root_update(
    { page, sync, },
    Sync(
      DeliveryCompleted(
        effect,
        account_a,
        document_id("one"),
        sync_operation_id(),
        @document_http.DeliveryResult::RevisionConflict,
      ),
    ),
  )
  let expected = sync.revision_conflict(checkpoint, effect, sync_operation_id())
  assert_true(deferred.sync == expected)

  let (resolving, lookup) = deferred.sync.begin_lookup()
  let (current, _) = test_root_update(
    { ..deferred, sync: resolving, },
    Sync(AccountResolved(lookup, @sync.Resolved(account_a, "A"))),
  )
  let (expected, action) = expected.begin_lookup().0.resolved(
    lookup,
    @sync.Resolved(account_a, "A"),
  ).0.drive(checkpoint)
  let expected = expected.begin_discovery().0
  assert_true(action is Some(@sync.Action::GetRemote(_, _, _, _)))
  assert_true(current.sync == expected)
}

///|
test "revision conflict waits for recovery identity before atomic persistence" {
  let account = @source_repository.AccountId::parse("account") catch {
    _ => abort("valid test account")
  }
  let (saved, checkpoint) = pending_sync_snapshot(account)
  let page = Editing({
    ..test_editing(),
    activation: {
      key: @documents.Key::checkpoint(account, document_id("one")),
      generation: 0,
    },
    documents: @documents.State::State(saved).project_account(account),
  })
  guard current_sync(account).drive(checkpoint)
    is (sync, Some(@sync.Action::Deliver(delivery, _, _, _))) else {
    fail("delivery")
  }
  let revision = @source_repository.SavedRevision::parse(1.0) catch {
    _ => abort("valid revision")
  }
  let remote = @source_repository.RemoteDocument::Present(revision, "remote")
  let conflicted = sync.revision_conflict(
    checkpoint,
    delivery,
    sync_operation_id(),
  )
  let (fetching, fetch) = conflicted.drive(checkpoint)
  guard fetch is Some(@sync.Action::GetRemote(read_effect, _, _, read)) else {
    fail("conflict read")
  }
  let (expected, attempt) = fetching.received(
    checkpoint, read_effect, read, remote,
  )
  let attempt = attempt.unwrap()
  let diverged = attempt.write().checkpoint()
  let (fetching_model, _) = test_root_update(
    { page, sync, },
    Sync(
      DeliveryCompleted(
        delivery,
        account,
        document_id("one"),
        sync_operation_id(),
        @document_http.DeliveryResult::RevisionConflict,
      ),
    ),
  )
  assert_true(fetching_model.sync == fetching)
  let (recovering, _) = test_root_update(
    fetching_model,
    Sync(
      RemoteCompleted(
        read_effect,
        account,
        document_id("one"),
        read,
        @document_http.RemoteResult::Found(remote),
      ),
    ),
  )
  assert_true(recovering.sync == expected)

  let (durable, _) = expected.stored(attempt.request_id(), diverged)
  guard durable.drive(diverged)
    is (
      awaiting_recovery,
      Some(@sync.Action::CreateRecovery(recovery_effect, _, _)),
    ) else {
    fail("recovery")
  }
  let mut created : @source_repository.DocumentId? = None
  let (recovering, _) = update(
    recovering,
    Sync(
      CheckpointCompleted(
        attempt.request_id(),
        @source_repository.CheckpointStored(diverged),
      ),
    ),
    @cmd.Emit(message => {
      match message {
        Sync(
          RecoveryCreated(
            effect,
            owner,
            source,
            @source_repository.CreateResult::Created(recovery_id)
          )
        ) if effect == recovery_effect &&
          owner == account &&
          source == document_id("one") => created = Some(recovery_id)
        _ => ()
      }
      @cmd.none
    }),
    @text_area.TextArea::TextArea("loomark-test-text"),
    @preview.PreviewEngine::PreviewEngine(),
  )
  assert_true(recovering.sync == awaiting_recovery)

  let recovery_id = created.unwrap()
  let (expected, attempt) = awaiting_recovery.recover(
    diverged, recovery_effect, recovery_id,
  )
  guard attempt.unwrap().write()
    is @source_repository.CheckpointAndRecovery(_, recovery) else {
    fail("atomic recovery")
  }
  assert_eq(recovery.text(), "local")
  let (persisting, _) = test_root_update(
    recovering,
    Sync(
      RecoveryCreated(
        recovery_effect,
        account,
        document_id("one"),
        @source_repository.CreateResult::Created(recovery_id),
      ),
    ),
  )
  assert_true(persisting.sync == expected)
}

///|
test "failed conflict recovery identity leaves durable recovery work retryable" {
  let account = @source_repository.AccountId::parse("account") catch {
    _ => abort("valid test account")
  }
  let (saved, checkpoint) = pending_sync_snapshot(account)
  let page = Editing({
    ..test_editing(),
    activation: {
      key: @documents.Key::checkpoint(account, document_id("one")),
      generation: 0,
    },
    documents: @documents.State::State(saved).project_account(account),
  })
  guard current_sync(account).drive(checkpoint)
    is (sync, Some(@sync.Action::Deliver(delivery, _, _, _))) else {
    fail("delivery")
  }
  let revision = @source_repository.SavedRevision::parse(1.0) catch {
    _ => abort("valid revision")
  }
  let remote = @source_repository.RemoteDocument::Present(revision, "remote")
  let conflicted = sync.revision_conflict(
    checkpoint,
    delivery,
    sync_operation_id(),
  )
  guard conflicted.drive(checkpoint)
    is (driven, Some(@sync.Action::GetRemote(read_effect, _, _, read))) else {
    fail("conflict read")
  }
  let (persisting, divergence) = driven.received(
    checkpoint, read_effect, read, remote,
  )
  let divergence = divergence.unwrap()
  let diverged = divergence.write().checkpoint()
  let (fetching, _) = test_root_update(
    { page, sync, },
    Sync(
      DeliveryCompleted(
        delivery,
        account,
        document_id("one"),
        sync_operation_id(),
        @document_http.DeliveryResult::RevisionConflict,
      ),
    ),
  )
  assert_true(fetching.sync == driven)
  let (recovering, _) = test_root_update(
    fetching,
    Sync(
      RemoteCompleted(
        read_effect,
        account,
        document_id("one"),
        read,
        @document_http.RemoteResult::Found(remote),
      ),
    ),
  )
  assert_true(recovering.sync == persisting)
  let (durable, _) = persisting.stored(divergence.request_id(), diverged)
  guard durable.drive(diverged)
    is (
      awaiting_recovery,
      Some(@sync.Action::CreateRecovery(recovery_effect, _, _)),
    ) else {
    fail("recovery")
  }
  let (recovering, _) = test_root_update(
    recovering,
    Sync(
      CheckpointCompleted(
        divergence.request_id(),
        @source_repository.CheckpointStored(diverged),
      ),
    ),
  )
  assert_true(recovering.sync == awaiting_recovery)
  let (retryable, _) = test_root_update(
    recovering,
    Sync(
      RecoveryCreated(
        recovery_effect,
        account,
        document_id("one"),
        @source_repository.CreateResult::CreateFailed(
          DocumentIdentityUnavailable,
        ),
      ),
    ),
  )
  assert_true(
    retryable.sync.drive(diverged).1 is Some(@sync.CreateRecovery(_, _, _)),
  )
}

///|
test "sync messages preserve the editor page" {
  let page = Editing(test_editing())
  let (sync, lookup_id) = @sync.State().begin_lookup()
  let (updated, _) = test_root_update(
    { page, sync, },
    Sync(AccountResolved(lookup_id, @sync.SignedOut)),
  )
  assert_true(updated.page == page)
}

///|
test "editor messages change the root model" {
  let page = Editing(test_editing())
  let model = { page, sync: @sync.State(), }
  let (updated, _) = test_root_update(
    model,
    TextChanged(
      { key: source_key("one"), generation: 0, },
      @text_change.TextChange::ReplaceAll("changed"),
    ),
  )
  assert_true(updated != model)
}

///|
test "synced Autosave updates only its canonical checkpoint" {
  let account = @source_repository.AccountId::parse("account") catch {
    _ => abort("valid test account")
  }
  let saved = test_sync_snapshot(account)
  let token = @documents.Key::checkpoint(account, document_id("one"))
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
  guard decisions is [@documents.Effect::SaveCheckpoint(owner, document)] else {
    fail("checkpoint persistence")
  }
  assert_true(owner == account)
  let model = { page: Editing({ ..initial, documents, }), sync: @sync.State(), }
  let (storing, request_id, checkpoint) = begin_checkpoint(
    model, owner, document,
  )
  let (stored, _) = test_root_update(
    storing,
    Sync(
      CheckpointCompleted(
        request_id,
        @source_repository.CheckpointResult::CheckpointStored(checkpoint),
      ),
    ),
  )

  guard stored.page is Editing(editing) else { fail("editing") }
  assert_true(
    editing.documents.save_status(token) == Some(@documents.SaveStatus::Clean),
  )
  assert_eq(
    editing.documents
    .snapshot()
    .checkpoint(account, document_id("one"))
    .unwrap()
    .document()
    .text(),
    "changed",
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
  let (sync, discovery) = model.sync.begin_discovery()
  let (sync, accepted) = sync.discovered(
    account,
    discovery.unwrap(),
    Some([entry]),
  )
  guard accepted else { abort("discovery rejected") }
  { ..model, sync, }
}

///|
fn select_remote(
  model : Model,
  key : @documents.Key,
  entry : @source_repository.RemoteEntry,
) -> (Model, @sync.EffectId, @sync.RemoteRead) {
  guard model.sync.begin_open(entry)
    is (expected, None, Some(@sync.GetRemote(effect, _, _, read))) else {
    abort("expected remote open")
  }
  let (selected, _) = test_root_update(model, DocumentSelected(key))
  guard selected.sync == expected else { abort("remote selection mismatch") }
  (selected, effect, read)
}

///|
fn receive_open(
  model : Model,
  account : @source_repository.AccountId,
  document_id : @source_repository.DocumentId,
  effect : @sync.EffectId,
  read : @sync.RemoteRead,
  remote : @source_repository.RemoteDocument,
) -> (Model, @sync.Attempt?) {
  guard read is @sync.RemoteRead::Open(intent, expected_revision) else {
    abort("expected open read")
  }
  let durable = match model.page.saved_documents() {
    Some(saved) => saved.checkpoint(account, document_id)
    None => None
  }
  let (expected, attempt) = model.sync.opened(
    effect, account, document_id, intent, expected_revision, durable, remote,
  ) catch {
    _ => abort("remote open rejected")
  }
  let (received, _) = test_root_update(
    model,
    Sync(
      RemoteCompleted(
        effect,
        account,
        document_id,
        read,
        @document_http.RemoteResult::Found(remote),
      ),
    ),
  )
  guard received.sync == expected else { abort("remote receipt mismatch") }
  (received, attempt)
}

///|
fn store_sync_attempt(
  model : Model,
  attempt : @sync.Attempt,
) -> (Model, @sync.Attempt?) {
  let checkpoint = attempt.write().checkpoint()
  let (_, next) = model.sync.stored(attempt.request_id(), checkpoint) catch {
    _ => abort("checkpoint completion rejected")
  }
  let (stored, _) = test_root_update(
    model,
    Sync(
      CheckpointCompleted(
        attempt.request_id(),
        @source_repository.CheckpointStored(checkpoint),
      ),
    ),
  )
  (stored, next)
}

///|
test "remote selection persists its received checkpoint before activation" {
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
  let key = @documents.Key::checkpoint(account, remote_id)
  let initial = {
    page: Editing(test_editing()),
    sync: discovered_sync(account, entry),
  }
  guard initial.sync.begin_open(entry)
    is (expected, None, Some(@sync.GetRemote(effect, _, _, read))) &&
    read is @sync.RemoteRead::Open(intent, expected_revision) else {
    fail("open")
  }
  let (fetching, _) = test_root_update(initial, DocumentSelected(key))
  assert_true(fetching.sync == expected)
  guard fetching.page is Editing(before) else { fail("editing") }
  assert_true(before.activation.key == source_key("one"))
  assert_eq(before.documents.text(key), None)

  let remote = @source_repository.RemoteDocument::Present(
    revision, "# Remote\nBody",
  )
  let (expected, attempt) = fetching.sync.opened(
    effect,
    account,
    remote_id,
    intent,
    expected_revision,
    None,
    remote,
  )
  let attempt = attempt.unwrap()
  let (storing, _) = test_root_update(
    fetching,
    Sync(
      RemoteCompleted(
        effect,
        account,
        remote_id,
        read,
        @document_http.RemoteResult::Found(remote),
      ),
    ),
  )
  assert_true(storing.sync == expected)
  guard storing.page is Editing(before) else { fail("editing") }
  assert_eq(before.documents.text(key), None)

  let (opened, _) = test_root_update(
    storing,
    Sync(
      CheckpointCompleted(
        attempt.request_id(),
        @source_repository.CheckpointStored(attempt.write().checkpoint()),
      ),
    ),
  )
  guard opened.page is Editing(editing) else { fail("editing") }
  assert_true(editing.activation.key == key)
  assert_eq(editing.documents.text(key), Some("# Remote\nBody"))
}

///|
test "newer remote GET queues one successor and activates only its text" {
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
  let key = @documents.Key::checkpoint(account, id)
  let initial = {
    page: Editing(test_editing()),
    sync: discovered_sync(account, first_entry),
  }
  let (opening_first, first_effect, first_read) = select_remote(
    initial, key, first_entry,
  )
  let first_remote = @source_repository.RemoteDocument::Present(
    first_revision, "first text",
  )
  let (storing_first, first_attempt) = receive_open(
    opening_first, account, id, first_effect, first_read, first_remote,
  )
  let first_attempt = first_attempt.unwrap()

  let newer = discover_entry(storing_first, account, second_entry)
  let (opening_second, second_effect, second_read) = select_remote(
    newer, key, second_entry,
  )
  let second_remote = @source_repository.RemoteDocument::Present(
    second_revision, "second text",
  )
  let (queued, duplicate) = receive_open(
    opening_second, account, id, second_effect, second_read, second_remote,
  )
  assert_eq(duplicate, None)

  let (stored_first, second_attempt) = store_sync_attempt(queued, first_attempt)
  guard stored_first.page is Editing(editing) else { fail("editing") }
  assert_eq(editing.documents.text(key), None)
  assert_true(editing.activation.key == source_key("one"))

  let second_attempt = second_attempt.unwrap()
  assert_eq(
    second_attempt.write().checkpoint().generation(),
    first_attempt.write().checkpoint().generation() + 1.0,
  )
  let (opened, next) = store_sync_attempt(stored_first, second_attempt)
  assert_eq(next, None)
  guard opened.page is Editing(editing) else { fail("editing") }
  assert_true(editing.activation.key == key)
  assert_eq(editing.documents.text(key), Some("second text"))
  assert_eq(
    editing.documents
    .snapshot()
    .checkpoint(account, id)
    .unwrap()
    .baseline_revision(),
    2.0,
  )
}

///|
test "newer remote GET advances a checkpoint stored while it was in flight" {
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
  let key = @documents.Key::checkpoint(account, id)
  let initial = {
    page: Editing(test_editing()),
    sync: discovered_sync(account, first_entry),
  }
  let (opening_first, first_effect, first_read) = select_remote(
    initial, key, first_entry,
  )
  let first_remote = @source_repository.RemoteDocument::Present(
    first_revision, "first text",
  )
  let (storing_first, first_attempt) = receive_open(
    opening_first, account, id, first_effect, first_read, first_remote,
  )
  let first_attempt = first_attempt.unwrap()

  let newer = discover_entry(storing_first, account, second_entry)
  let (opening_second, second_effect, second_read) = select_remote(
    newer, key, second_entry,
  )
  let (stored_first, next) = store_sync_attempt(opening_second, first_attempt)
  assert_eq(next, None)
  guard stored_first.page is Editing(editing) else { fail("editing") }
  assert_eq(editing.documents.text(key), None)

  let second_remote = @source_repository.RemoteDocument::Present(
    second_revision, "second text",
  )
  let (storing_second, second_attempt) = receive_open(
    stored_first, account, id, second_effect, second_read, second_remote,
  )
  let second_attempt = second_attempt.unwrap()
  assert_eq(
    second_attempt.write().checkpoint().generation(),
    first_attempt.write().checkpoint().generation() + 1.0,
  )
  let (opened, next) = store_sync_attempt(storing_second, second_attempt)
  assert_eq(next, None)
  guard opened.page is Editing(editing) else { fail("editing") }
  assert_true(editing.activation.key == key)
  assert_eq(editing.documents.text(key), Some("second text"))
  assert_eq(
    editing.documents
    .snapshot()
    .checkpoint(account, id)
    .unwrap()
    .baseline_revision(),
    2.0,
  )
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
  let entry = @source_repository.RemoteEntry::Present(
    remote_id, revision, "Remote",
  )
  let key = @documents.Key::checkpoint(account, remote_id)
  let initial = {
    page: Editing(test_editing()),
    sync: discovered_sync(account, entry),
  }
  guard initial.sync.begin_open(entry)
    is (_, None, Some(@sync.GetRemote(effect, _, _, read))) &&
    read is @sync.RemoteRead::Open(intent, expected) else {
    fail("open")
  }
  let (fetching, _) = test_root_update(initial, DocumentSelected(key))
  let remote = @source_repository.RemoteDocument::Present(revision, "remote")
  let attempt = fetching.sync.opened(
    effect,
    account,
    remote_id,
    intent,
    expected,
    None,
    remote,
  ).1.unwrap()
  let (storing, _) = test_root_update(
    fetching,
    Sync(
      RemoteCompleted(
        effect,
        account,
        remote_id,
        read,
        @document_http.RemoteResult::Found(remote),
      ),
    ),
  )
  let (composing, _) = test_root_update(
    storing,
    CompositionStarted({ key: source_key("one"), generation: 0, }),
  )
  let (completed, _) = test_root_update(
    composing,
    Sync(
      CheckpointCompleted(
        attempt.request_id(),
        @source_repository.CheckpointStored(attempt.write().checkpoint()),
      ),
    ),
  )
  guard completed.page is Editing(editing) else { fail("editing") }
  assert_true(editing.activation.key == source_key("one"))
  assert_eq(editing.documents.text(key), None)

  let (activated, _) = test_root_update(
    completed,
    CompositionEnded({ key: source_key("one"), generation: 0, }),
  )
  guard activated.page is Editing(editing) else { fail("editing") }
  assert_true(editing.activation.key == key)
  assert_eq(editing.documents.text(key), Some("remote"))
  assert_eq(activated.sync.pending_open(), None)
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
  let checkpoint = @source_repository.SyncCheckpoint::receive(
    account,
    documents_test_document("one", "local"),
    first,
  )
  let saved = @source_repository.SavedDocuments::from_documents([])
    .unwrap()
    .apply_checkpoint(checkpoint)
  let key = @documents.Key::checkpoint(account, id)
  let page = Editing({
    ..test_editing(),
    activation: { key, generation: 0, },
    documents: @documents.State::State(saved).project_account(account),
  })
  let (sync, discovery) = current_sync(account).begin_discovery()
  let discovery = discovery.unwrap()
  let entry = @source_repository.RemoteEntry::Present(id, next, "Remote")
  let (discovered, _) = test_root_update(
    { page, sync, },
    Sync(
      DiscoveryCompleted(
        account,
        discovery,
        @document_http.DiscoveryResult::Discovered([entry]),
      ),
    ),
  )
  let (expected, _) = sync.discovered(account, discovery, Some([entry]))
  let (expected, action) = expected.drive(checkpoint)
  guard action is Some(@sync.Action::GetRemote(effect, _, _, read)) else {
    fail("remote revision read")
  }
  assert_true(discovered.sync == expected)

  let remote = @source_repository.RemoteDocument::Present(next, "remote")
  let (expected, attempt) = expected.received(checkpoint, effect, read, remote)
  guard attempt is Some(attempt) else { fail("persist observed revision") }
  let (storing, _) = test_root_update(
    discovered,
    Sync(
      RemoteCompleted(
        effect,
        account,
        id,
        read,
        @document_http.RemoteResult::Found(remote),
      ),
    ),
  )
  assert_true(storing.sync == expected)
  guard storing.page is Editing(editing) else { fail("editing") }
  assert_true(editing.activation.key == key)
  assert_eq(editing.documents.text(key), Some("local"))

  let (stored, _) = test_root_update(
    storing,
    Sync(
      CheckpointCompleted(
        attempt.request_id(),
        @source_repository.CheckpointStored(attempt.write().checkpoint()),
      ),
    ),
  )
  guard stored.page.saved_documents().unwrap().checkpoint(account, id)
    is Some(durable) else {
    fail("stored observation")
  }
  assert_true(
    durable.directive() is @source_repository.SyncDirective::UpdateAvailable(_),
  )
  guard stored.page is Editing(editing) else { fail("editing") }
  assert_true(editing.activation.key == key)
  assert_eq(editing.documents.text(key), Some("local"))
}

///|
test "synced completion recognizes newer text that returned to stored text" {
  let account = @source_repository.AccountId::parse("account") catch {
    _ => abort("valid test account")
  }
  let saved = test_sync_snapshot(account)
  let token = @documents.Key::checkpoint(account, document_id("one"))
  let documents = @documents.State::State(saved).project_account(account)
  let (documents, _) = documents.reduce(
    @documents.Msg::TextChanged(token, "sent"),
  )
  let (documents, effects) = documents.reduce(
    @documents.Msg::ApplyPendingEdit(token, pending_revision(documents, token)),
  )
  guard effects is [@documents.Effect::SaveCheckpoint(owner, document)] else {
    fail("first write")
  }
  let checkpoint = checkpoint_edit(
    saved.checkpoint(owner, document.id()).unwrap(),
    document.text(),
  )
  let (documents, _) = documents.reduce(
    @documents.Msg::TextChanged(token, "newer"),
  )
  let (documents, _) = documents.reduce(
    @documents.Msg::TextChanged(token, "sent"),
  )

  let (documents, follow_up) = documents.reduce(
    @documents.Msg::FeedbackReceived(
      CheckpointCompleted(CheckpointStored(checkpoint)),
    ),
  )
  assert_true(follow_up.is_empty())
  assert_true(
    documents.save_status(token) == Some(@documents.SaveStatus::Clean),
  )
  assert_eq(documents.text(token), Some("sent"))
}

///|
test "failed synced write recognizes a newer revert to durable text" {
  let account = @source_repository.AccountId::parse("account") catch {
    _ => abort("valid test account")
  }
  let saved = test_sync_snapshot(account)
  let token = @documents.Key::checkpoint(account, document_id("one"))
  let documents = @documents.State::State(saved).project_account(account)
  let (documents, _) = documents.reduce(
    @documents.Msg::TextChanged(token, "sent"),
  )
  let (documents, effects) = documents.reduce(
    @documents.Msg::ApplyPendingEdit(token, pending_revision(documents, token)),
  )
  guard effects is [@documents.Effect::SaveCheckpoint(owner, document)] else {
    fail("first write")
  }
  let checkpoint = checkpoint_edit(
    saved.checkpoint(owner, document.id()).unwrap(),
    document.text(),
  )
  let (documents, _) = documents.reduce(
    @documents.Msg::TextChanged(token, "one"),
  )

  let (documents, follow_up) = documents.reduce(
    @documents.Msg::FeedbackReceived(
      CheckpointCompleted(
        CheckpointFailed(
          checkpoint,
          @source_repository.CheckpointFailure::WriteFailed,
        ),
      ),
    ),
  )
  assert_true(follow_up.is_empty())
  assert_true(
    documents.save_status(token) == Some(@documents.SaveStatus::Clean),
  )
  assert_eq(documents.text(token), Some("one"))
}

///|
test "checkpoint failure keeps optimistic text and retries the same write" {
  let account = @source_repository.AccountId::parse("account") catch {
    _ => abort("valid test account")
  }
  let saved = test_sync_snapshot(account)
  let token = @documents.Key::checkpoint(account, document_id("one"))
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
  guard decisions is [@documents.Effect::SaveCheckpoint(owner, document)] else {
    fail("persist")
  }
  let model = { page: Editing({ ..initial, documents, }), sync: @sync.State(), }
  let (storing, request_id, checkpoint) = begin_checkpoint(
    model, owner, document,
  )
  let (failed, _) = test_root_update(
    storing,
    Sync(
      CheckpointCompleted(
        request_id,
        @source_repository.CheckpointResult::CheckpointFailed(
          checkpoint,
          @source_repository.CheckpointFailure::StorageUnavailable,
        ),
      ),
    ),
  )
  guard failed.page is Editing(editing) else { fail("editing") }
  assert_eq(editing.documents.text(token), Some("optimistic"))
  assert_true(
    editing.documents.save_status(token)
    is Some(@documents.SaveStatus::SaveFailed(StorageUnavailable)),
  )

  let (retrying_page, retry_decisions) = editing.documents.reduce(
    @documents.Msg::RetrySave(token),
  )
  guard retry_decisions
    is [@documents.Effect::SaveCheckpoint(retry_owner, retry_document)] else {
    fail("retry")
  }
  let (retrying, retry_request_id, retry_checkpoint) = begin_checkpoint(
    { ..failed, page: Editing({ ..editing, documents: retrying_page, }), },
    retry_owner,
    retry_document,
  )
  assert_true(retry_checkpoint == checkpoint)
  let (stored, _) = test_root_update(
    retrying,
    Sync(
      CheckpointCompleted(
        retry_request_id,
        @source_repository.CheckpointResult::CheckpointStored(checkpoint),
      ),
    ),
  )
  guard stored.page is Editing(recovered) else { fail("editing") }
  assert_true(
    recovered.documents.save_status(token) == Some(@documents.SaveStatus::Clean),
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
  let initial = { ..test_editing(), creation: Creating, }
  let (model, _) = test_update(
    Editing(initial),
    ImportCreateCompleted("Imported", Created(document_id("imported"))),
  )
  guard model is Editing(imported) && imported.creation == Idle else {
    fail("Import should supersede New")
  }

  let (after_stale_new, _) = test_update(
    Editing(imported),
    CreateCompleted(source_key("one"), Created(document_id("unused-new"))),
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
  let initial = { ..test_editing(), creation: Creating, }
  let (after_delete, _) = test_update(
    Editing(initial),
    DeleteRequested(source_key("one")),
  )
  assert_true(after_delete == Editing(initial))
  let (after_create, _) = test_update(
    after_delete,
    CreateCompleted(source_key("one"), Created(document_id("new"))),
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
  let initial = { ..test_editing(), creation: Creating, }
  let (model, _) = test_update(
    Editing(initial),
    CreateCompleted(source_key("other"), Created(document_id("new"))),
  )
  guard model is Editing(editing) else { fail("editing") }
  assert_true(editing.activation == initial.activation)
  assert_true(editing.creation is Creating)
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
  guard effects is [@documents.Effect::DeleteSource(operation)] else {
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
  guard decisions[0] is @documents.Effect::PersistSource(operation) else {
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
  guard decisions[0] is @documents.Effect::PersistSource(operation) else {
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
    @documents.Effect::DeleteSource(operation) =>
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
    new_preparation_request_id: 0,
  }
  let (documents, decisions) = initial.documents.reduce(
    @documents.Msg::DeleteConfirmed(source_key("one")),
  )
  guard decisions[0] is @documents.Effect::DeleteSource(operation) else {
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
    TextChanged(initial.activation, @text_change.TextChange::ReplaceAll("one")),
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
  guard decisions is [@documents.Effect::ArmMaximum(_, _)] else {
    fail("timers")
  }
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
  guard decisions[0] is @documents.Effect::PersistSource(op) else {
    fail("persist")
  }
  assert_eq(op.document.text(), "one!")
  // Update view layer: authoritative text is still "one" until save completes, preview unchanged
  let (model, _) = test_update(
    Editing({ ..initial, documents: initial.documents, }),
    TextChanged(initial.activation, @text_change.TextChange::ReplaceAll("one!")),
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
  guard decisions[0] is @documents.Effect::PersistSource(operation) else {
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
