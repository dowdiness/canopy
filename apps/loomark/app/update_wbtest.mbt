///|
fn document_id(value : String) -> @source_repository.DocumentId {
  @source_repository.DocumentId::parse(value) catch {
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
  write : @source_repository.CheckpointWrite,
) -> (Model, @sync.RequestId) {
  let (sync, attempt) = model.sync.persist(write)
  let attempt = attempt.unwrap()
  ({ ..model, sync, }, attempt.request_id())
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
  guard decisions is [@documents.Effect::PersistCheckpoint(write)] else {
    fail("checkpoint persistence")
  }
  let model = { page: Editing({ ..initial, documents, }), sync: @sync.State(), }
  let (storing, request_id) = begin_checkpoint(model, write)
  let (stored, _) = test_root_update(
    storing,
    Sync(
      CheckpointCompleted(
        request_id,
        @source_repository.CheckpointResult::CheckpointStored(
          write.checkpoint(),
        ),
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
  guard effects is [@documents.Effect::PersistCheckpoint(write)] else {
    fail("first write")
  }
  let (documents, _) = documents.reduce(
    @documents.Msg::TextChanged(token, "newer"),
  )
  let (documents, _) = documents.reduce(
    @documents.Msg::TextChanged(token, "sent"),
  )

  let (documents, follow_up) = documents.reduce(
    @documents.Msg::FeedbackReceived(
      CheckpointCompleted(CheckpointStored(write.checkpoint())),
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
  guard effects is [@documents.Effect::PersistCheckpoint(write)] else {
    fail("first write")
  }
  let (documents, _) = documents.reduce(
    @documents.Msg::TextChanged(token, "one"),
  )

  let (documents, follow_up) = documents.reduce(
    @documents.Msg::FeedbackReceived(
      CheckpointCompleted(
        CheckpointFailed(
          write.checkpoint(),
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
  guard decisions is [@documents.Effect::PersistCheckpoint(write)] else {
    fail("persist")
  }
  let checkpoint = write.checkpoint()
  let model = { page: Editing({ ..initial, documents, }), sync: @sync.State(), }
  let (storing, request_id) = begin_checkpoint(model, write)
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
  guard retry_decisions is [@documents.Effect::PersistCheckpoint(retry)] else {
    fail("retry")
  }
  let (retrying, retry_request_id) = begin_checkpoint(
    { ..failed, page: Editing({ ..editing, documents: retrying_page, }), },
    retry,
  )
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
