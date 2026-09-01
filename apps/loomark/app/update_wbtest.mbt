///|
fn test_snapshot() -> @source_repository.RepositorySnapshot {
  @source_repository.RepositorySnapshot::from_sources([
    @source_repository.SourceRecord::new("one", "one").unwrap(),
    @source_repository.SourceRecord::new("two", "two").unwrap(),
  ]).unwrap()
}

///|
fn test_editing() -> EditingState {
  let snapshot = test_snapshot()
  let documents = initial_documents(snapshot)
  let (preview, _) = @preview.PreviewEngine::PreviewEngine().activate(
    @preview.Input(0, "one"),
  )
  {
    activation: { document_id: "one", generation: 0 },
    documents,
    creation: Idle,
    deletion: NoDeletion,
    mode: Text,
    compact: false,
    preview,
    new_preparation_request_id: 0,
  }
}

///|
fn test_update(model : Model, msg : Msg) -> (Model, @cmd.Cmd) {
  update(
    model,
    msg,
    @cmd.Emit(_ => @cmd.none),
    @text_area.TextArea::TextArea("loomark-test-text"),
    @preview.PreviewEngine::PreviewEngine(),
  )
}

///|
test "loading and recovery ignore document lifecycle feedback" {
  let feedback = DocumentsLifecycle(
    QuietElapsed("one", documents_test_order(1L)),
  )
  let (loading, _) = test_update(Loading(false), feedback)
  assert_true(loading == Loading(false))
  let (recovery, _) = test_update(Recovery(StorageUnavailable, false), feedback)
  assert_true(recovery == Recovery(StorageUnavailable, false))
}

///|
test "active delete is accepted and composition defers confirmation" {
  let initial = test_editing()
  let (model, _) = test_update(Editing(initial), DeleteRequested("one"))
  guard model is Editing({ deletion: DeleteConfirmation("one"), .. }) else {
    fail("active delete confirmation")
  }
  let (documents, _) = initial.documents.reduce(
    DocumentsCompositionStarted("one"),
  )
  let composing = { ..initial, documents, }
  let (model, _) = test_update(Editing(composing), DeleteRequested("one"))
  guard model is Editing({ deletion: DeleteDeferred("one"), .. }) else {
    fail("deferred active confirmation")
  }
  let (model, _) = test_update(Editing(composing), DeleteRequested("two"))
  guard model is Editing({ deletion: DeleteDeferred("two"), .. }) else {
    fail("active composition also defers a non-active target")
  }
}

///|
test "same document selection is a no-op" {
  let initial = test_editing()
  let (model, _) = test_update(Editing(initial), DocumentSelected("one"))
  guard model is Editing(editing) else { fail("editing") }
  assert_true(editing.activation == initial.activation)
}

///|
test "stale create completion is ignored" {
  let initial = { ..test_editing(), creation: Creating }
  let (model, _) = test_update(
    Editing(initial),
    CreateCompleted("other", Created("new")),
  )
  guard model is Editing(editing) else { fail("editing") }
  assert_true(editing.activation == initial.activation)
  assert_true(editing.creation is Creating)
}

///|
test "pending target cannot be selected" {
  let initial = test_editing()
  let (documents, _) = initial.documents.reduce(DeleteConfirmed("two"))
  let (model, _) = test_update(
    Editing({ ..initial, documents, }),
    DocumentSelected("two"),
  )
  guard model is Editing(editing) else { fail("editing") }
  assert_eq(editing.activation.document_id, "one")
}

///|
test "deleting an active unsaved new document reconciles activation" {
  let initial = test_editing()
  let (documents, _) = initial.documents.reduce(DocumentsNew("new"))
  let (model, _) = test_update(
    Editing({
      ..initial,
      activation: { document_id: "new", generation: 1 },
      documents,
      deletion: DeleteConfirmation("new"),
    }),
    DeleteConfirmed("new"),
  )
  guard model is Editing(editing) else { fail("editing") }
  assert_true(editing.documents.text(editing.activation.document_id) is Some(_))
  assert_true(editing.activation.document_id != "new")
}

///|
test "failed first save of active new document reconciles activation" {
  let initial = test_editing()
  let (documents, _) = initial.documents.reduce(DocumentsNew("new"))
  let (documents, _) = documents.reduce(
    DocumentsTextChanged("new", "hello", documents_test_order(0L)),
  )
  let (documents, decisions) = documents.reduce(
    DocumentsFeedbackReceived(QuietElapsed("new", documents_test_order(1L))),
  )
  guard decisions[0] is DocumentsPersist(operation) else { fail("save") }
  let (documents, _) = documents.reduce(DeleteConfirmed("new"))
  let (model, _) = test_update(
    Editing({
      ..initial,
      activation: { document_id: "new", generation: 1 },
      documents,
    }),
    DocumentsLifecycle(SaveCompleted(operation, Failed(WriteFailed))),
  )
  guard model is Editing(editing) else { fail("editing") }
  assert_true(editing.documents.text(editing.activation.document_id) is Some(_))
  assert_true(editing.activation.document_id != "new")
}

///|
test "save completion updates inactive document without switching" {
  let initial = test_editing()
  let (documents, _) = initial.documents.reduce(
    DocumentsTextChanged(
      "two",
      "two!",
      @source_repository.ChangeOrder::from_int64(0L).unwrap(),
    ),
  )
  let (documents, decisions) = documents.reduce(
    DocumentsFeedbackReceived(
      QuietElapsed(
        "two",
        @source_repository.ChangeOrder::from_int64(1L).unwrap(),
      ),
    ),
  )
  guard decisions[0] is DocumentsDecision::DocumentsPersist(operation) else {
    fail("persist")
  }
  let state = { ..initial, documents, }
  let (model, _) = test_update(
    Editing(state),
    DocumentsLifecycle(SaveCompleted(operation, Stored(operation.source))),
  )
  guard model is Editing(editing) else { fail("editing") }
  assert_eq(editing.activation.document_id, "one")
  assert_eq(editing.documents.text("two"), Some("two!"))
  assert_eq(editing.documents.snapshot().source("two").unwrap().text(), "two!")
}

///|
test "preparing new preserves documents and mode" {
  let documents = initial_documents(test_snapshot())
  let (model, _) = test_update(
    PreparingNew({
      documents,
      mode: Split,
      compact: false,
      request_id: 1,
      next_activation_generation: 0,
    }),
    EmptyCreateCompleted(1, Created("new")),
  )
  guard model is Editing(editing) else { fail("editing") }
  assert_true(editing.mode is Split)
  assert_eq(editing.documents.text("one"), Some("one"))
  assert_eq(editing.documents.text("two"), Some("two"))
}

///|
test "delete-to-New advances Preview ownership" {
  let (model, _) = preparing_after_probe_timeout()
  guard model is PreparingNew(preparing) else { fail("preparing") }
  let (model, _) = test_update(
    PreparingNew({ ..preparing, mode: Split }),
    EmptyCreateCompleted(preparing.request_id, Created("new")),
  )
  guard model is Editing(editing) else { fail("editing") }
  assert_eq(editing.activation.generation, 1)
}

///|
test "final active delete falls back to a new document" {
  let snapshot = @source_repository.RepositorySnapshot::from_sources([
    @source_repository.SourceRecord::new("one", "one").unwrap(),
  ]).unwrap()
  let documents = initial_documents(snapshot)
  let (preview, _) = @preview.PreviewEngine::PreviewEngine().activate(
    @preview.Input(0, "one"),
  )
  let initial = {
    activation: { document_id: "one", generation: 0 },
    documents,
    creation: Idle,
    deletion: NoDeletion,
    mode: Text,
    compact: false,
    preview,
    new_preparation_request_id: 0,
  }
  let (documents, decisions) = initial.documents.reduce(DeleteConfirmed("one"))
  guard decisions[0] is DeleteSource(operation) else { fail("delete") }
  let state = { ..initial, documents, }
  let (model, _) = test_update(
    Editing(state),
    DocumentsLifecycle(DeleteCompleted(operation, Deleted("one"))),
  )
  guard model is PreparingNew(_) else { fail("should prepare new") }
}

///|
test "active pending deletion prevents document switch" {
  let initial = test_editing()
  let (documents, _) = initial.documents.reduce(DeleteConfirmed("one"))
  let (model, _) = test_update(
    Editing({ ..initial, documents, }),
    DocumentSelected("two"),
  )
  guard model is Editing(editing) else { fail("editing") }
  assert_eq(editing.activation.document_id, "one")
}

///|
test "composition end opens deferred active deletion confirmation" {
  let initial = test_editing()
  let (documents, _) = initial.documents.reduce(
    DocumentsCompositionStarted("one"),
  )
  let state = { ..initial, documents, deletion: DeleteDeferred("one") }
  let (model, _) = test_update(
    Editing(state),
    CompositionEnded(initial.activation),
  )
  guard model is Editing(editing) else { fail("editing") }
  assert_true(editing.deletion == DeleteConfirmation("one"))
  assert_false(editing.documents.is_composing("one"))
}

///|
test "probe timeout selects fallback and late failure keeps that selection" {
  let initial = test_editing()
  let (documents, decisions) = initial.documents.reduce(DeleteConfirmed("one"))
  guard decisions[0] is DeleteSource(operation) else { fail("delete") }
  let state = { ..initial, documents, }
  let (model, _) = test_update(
    Editing(state),
    DocumentsLifecycle(DeleteWatchdogElapsed(operation)),
  )
  let (model, _) = test_update(
    model,
    DocumentsLifecycle(DeleteProbeElapsed(operation)),
  )
  guard model is Editing(editing) else { fail("editing") }
  assert_eq(editing.activation.document_id, "two")
  let (model, _) = test_update(
    model,
    DocumentsLifecycle(DeleteCompleted(operation, Failed(WriteFailed))),
  )
  guard model is Editing(editing) else { fail("editing") }
  assert_eq(editing.activation.document_id, "two")
  assert_true(editing.documents.delete_status("one") is Some(Failed(_, _)))
}

///|
test "duplicate text message leaves model and preview unchanged" {
  let initial = test_editing()
  let (model, command) = test_update(
    Editing(initial),
    TextChanged(initial.activation, @text_change.TextChange::ReplaceAll("one")),
  )
  assert_true(model == Editing(initial))
  assert_false(@debug.to_string(command).contains("Preview"))
}

///|
test "change order exhaustion restores authoritative text and preview" {
  let maximum = @source_repository.ChangeOrder::from_int64(
    9_007_199_254_740_991L,
  ).unwrap()
  let snapshot = @source_repository.RepositorySnapshot::from_sources([
    @source_repository.SourceRecord::new("one", "one", change_order=maximum).unwrap(),
  ]).unwrap()
  let base = test_editing()
  let initial = {
    ..base,
    activation: { document_id: "one", generation: 0 },
    documents: initial_documents(snapshot),
  }
  let (model, _) = test_update(
    Editing(initial),
    TextChanged(
      initial.activation,
      @text_change.TextChange::ReplaceAll("changed"),
    ),
  )
  guard model is Editing(editing) else { fail("editing") }
  assert_eq(editing.documents.text("one"), Some("one"))
  assert_true(editing.preview == initial.preview)
}

///|
fn preparing_after_probe_timeout() -> (Model, DeleteOperation?) {
  let snapshot = @source_repository.RepositorySnapshot::from_sources([
    @source_repository.SourceRecord::new("one", "one").unwrap(),
  ]).unwrap()
  let base = test_editing()
  let initial = { ..base, documents: initial_documents(snapshot) }
  let (documents, decisions) = initial.documents.reduce(DeleteConfirmed("one"))
  match decisions[0] {
    DeleteSource(operation) => {
      let (model, _) = test_update(
        Editing({ ..initial, documents, }),
        DocumentsLifecycle(DeleteWatchdogElapsed(operation)),
      )
      let (model, _) = test_update(
        model,
        DocumentsLifecycle(DeleteProbeElapsed(operation)),
      )
      (model, Some(operation))
    }
    _ => (Editing(initial), None)
  }
}

///|
test "preparing new retains late delete failure for matching creation" {
  let (model, operation) = preparing_after_probe_timeout()
  let (model, _) = test_update(
    model,
    DocumentsLifecycle(DeleteCompleted(operation.unwrap(), Failed(WriteFailed))),
  )
  let (model, _) = test_update(model, EmptyCreateCompleted(1, Created("new")))
  guard model is Editing(editing) else { fail("editing") }
  assert_eq(editing.activation.document_id, "new")
  assert_true(editing.documents.delete_status("one") is Some(Failed(_, _)))
}

///|
test "preparing new ignores stale empty creation completion" {
  let (model, _) = preparing_after_probe_timeout()
  let (model, _) = test_update(model, EmptyCreateCompleted(0, Created("old")))
  guard model is PreparingNew({ request_id: 1, .. }) else { fail("preparing") }
}

///|
test "preparing new applies late delete success before creation" {
  let (model, operation) = preparing_after_probe_timeout()
  let (model, _) = test_update(
    model,
    DocumentsLifecycle(DeleteCompleted(operation.unwrap(), Deleted("one"))),
  )
  let (model, _) = test_update(model, EmptyCreateCompleted(1, Created("new")))
  guard model is Editing(editing) else { fail("editing") }
  assert_eq(editing.activation.document_id, "new")
  assert_eq(editing.documents.text("one"), None)
}

///|
test "preparing new reduces unrelated inactive save completion" {
  let initial = test_editing()
  let (documents, _) = initial.documents.reduce(
    DocumentsTextChanged(
      "two",
      "two!",
      @source_repository.ChangeOrder::from_int64(0L).unwrap(),
    ),
  )
  let (documents, decisions) = documents.reduce(
    DocumentsFeedbackReceived(
      QuietElapsed(
        "two",
        @source_repository.ChangeOrder::from_int64(1L).unwrap(),
      ),
    ),
  )
  guard decisions[0] is DocumentsPersist(operation) else { fail("persist") }
  let (model, _) = test_update(
    PreparingNew({
      documents,
      mode: Text,
      compact: false,
      request_id: 1,
      next_activation_generation: 1,
    }),
    DocumentsLifecycle(SaveCompleted(operation, Stored(operation.source))),
  )
  guard model is PreparingNew(preparing) else { fail("preparing") }
  assert_eq(preparing.documents.text("two"), Some("two!"))
  assert_eq(
    preparing.documents.snapshot().source("two").unwrap().text(),
    "two!",
  )
}
