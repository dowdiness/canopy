///|
fn test_repository() -> @source_repository.RepositorySnapshot {
  @source_repository.RepositorySnapshot::from_sources([
    @source_repository.SourceRecord::new("document-1", "# Old\n").unwrap(),
  ]).unwrap()
}

///|
fn test_editing_state(text : String, save : SaveState) -> EditingState {
  {
    document_id: "document-1",
    text,
    composing: false,
    save,
    mode: Text,
    focused_mode: Text,
    compact: false,
    preview: Unrequested,
    repository: test_repository(),
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
test "opened snapshot installs repository" {
  let snapshot = @source_repository.RepositorySnapshot::from_sources([
    @source_repository.SourceRecord::new("document-b", "# B\n").unwrap(),
    @source_repository.SourceRecord::new("document-a", "# A\n").unwrap(),
  ]).unwrap()
  let (model, _) = test_update(
    Loading(false),
    Opened(@source_repository.OpenResult::Ready(snapshot)),
  )
  guard model is Editing(editing) else { fail("expected Editing") }
  assert_eq(editing.document_id, "document-a")
  assert_eq(editing.repository, snapshot)
}

///|
test "TextChanged remains free of repository IO" {
  let (model, command) = test_update(
    Editing(test_editing_state("# Old\n", Saved)),
    TextChanged(@text_change.TextChange::ReplaceAll("# New\n")),
  )
  guard model is Editing(editing) else { fail("expected Editing") }
  assert_eq(editing.text, "# New\n")
  assert_true(editing.save == Waiting)
  assert_false(@debug.to_string(command).contains("IndexedDB"))
}

///|
test "SaveRequested uses the repository snapshot" {
  let (model, command) = test_update(
    Editing(test_editing_state("# New\n", Waiting)),
    SaveRequested("# New\n"),
  )
  guard model is Editing(editing) else { fail("expected Editing") }
  assert_true(editing.save == Saving("# New\n"))
  assert_true(@debug.to_string(command).contains("IndexedDBPut"))
}

///|
test "successful save installs returned snapshot" {
  let initial = test_editing_state("# New\n", Saving("# New\n"))
  let next = @source_repository.RepositorySnapshot::from_sources([
    @source_repository.SourceRecord::new("document-1", "# New\n").unwrap(),
  ]).unwrap()
  let (model, _) = test_update(
    Editing(initial),
    SaveCompleted(
      "document-1",
      "# New\n",
      @source_repository.SaveResult::Stored(next),
    ),
  )
  guard model is Editing(editing) else { fail("expected Editing") }
  assert_true(editing.save == Saved)
  assert_eq(editing.repository, next)
}

///|
test "stale completion remains fenced by identity and candidate" {
  let initial = test_editing_state("# Latest\n", Saving("# Latest\n"))
  let (model, _) = test_update(
    Editing(initial),
    SaveCompleted(
      "document-1",
      "# Old\n",
      @source_repository.SaveResult::Stored(test_repository()),
    ),
  )
  assert_true(model == Editing(initial))
}

///|
test "stale success immediately saves the latest text" {
  let initial = test_editing_state("# Latest\n", Saving("# Old\n"))
  let (model, command) = test_update(
    Editing(initial),
    SaveCompleted(
      "document-1",
      "# Old\n",
      @source_repository.SaveResult::Stored(test_repository()),
    ),
  )
  guard model is Editing(editing) else { fail("expected Editing") }
  assert_true(editing.save == Saving("# Latest\n"))
  let rendered = @debug.to_string(command)
  assert_true(rendered.contains("IndexedDBPut"))
  assert_true(rendered.contains("# Latest"))
}

///|
test "failure handling and foreign completion preserve active state" {
  let initial = test_editing_state("# New\n", Saving("# New\n"))
  let (failed, _) = test_update(
    Editing(initial),
    SaveCompleted(
      "document-1",
      "# New\n",
      @source_repository.SaveResult::Failed(
        @source_repository.SaveFailure::WriteFailed,
      ),
    ),
  )
  guard failed is Editing(editing) else { fail("expected Editing") }
  assert_true(
    editing.save == Failed(@source_repository.SaveFailure::WriteFailed),
  )
  let (foreign, _) = test_update(
    Editing(initial),
    SaveCompleted(
      "document-2",
      "# New\n",
      @source_repository.SaveResult::Stored(test_repository()),
    ),
  )
  assert_true(foreign == Editing(initial))
}

///|
test "same-document stale success and failure cannot replace active save" {
  let initial = test_editing_state("# Latest\n", Saving("# Latest\n"))
  let stale_success = SaveCompleted(
    "document-1",
    "# Old\n",
    @source_repository.SaveResult::Stored(test_repository()),
  )
  let stale_failure = SaveCompleted(
    "document-1",
    "# Old\n",
    @source_repository.SaveResult::Failed(
      @source_repository.SaveFailure::WriteFailed,
    ),
  )
  let (after_success, _) = test_update(Editing(initial), stale_success)
  let (after_failure, _) = test_update(Editing(initial), stale_failure)
  assert_true(after_success == Editing(initial))
  assert_true(after_failure == Editing(initial))
}
