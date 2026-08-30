///|
fn test_repository() -> @source_repository.RepositorySnapshot {
  @source_repository.RepositorySnapshot::from_sources([
    @source_repository.SourceRecord::new("document-1", "# Old\n").unwrap(),
  ]).unwrap()
}

///|
fn test_editing_state(text : String, save : SaveState) -> EditingState {
  {
    activation: { document_id: "document-1", generation: 0 },
    text,
    composing: false,
    save,
    creation: Idle,
    mode: Text,
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
  assert_eq(editing.activation.document_id, "document-a")
  assert_eq(editing.repository, snapshot)
}

///|
test "saved document selection activates its exact Source without writing" {
  let snapshot = @source_repository.RepositorySnapshot::from_sources([
    @source_repository.SourceRecord::new("document-1", "# First\n").unwrap(),
    @source_repository.SourceRecord::new("document-2", "# Second\n").unwrap(),
  ]).unwrap()
  let initial = {
    ..test_editing_state("# First\n", Saved),
    repository: snapshot,
  }
  let (model, command) = test_update(
    Editing(initial),
    DocumentSelected("document-2"),
  )
  guard model is Editing(editing) else { fail("expected Editing") }
  assert_eq(editing.activation.document_id, "document-2")
  assert_eq(editing.activation.generation, 1)
  assert_eq(editing.text, "# Second\n")
  assert_true(editing.save == Saved)
  assert_true(editing.preview == Unrequested)
  assert_false(@debug.to_string(command).contains("IndexedDB"))
}

///|
test "stale activation cannot change current text" {
  let initial = {
    ..test_editing_state("# Current\n", Saved),
    activation: { document_id: "document-1", generation: 1 },
  }
  let stale : Activation = { document_id: "document-1", generation: 0 }
  let (model, _) = test_update(
    Editing(initial),
    TextChanged(stale, @text_change.TextChange::ReplaceAll("# Stale\n")),
  )
  assert_true(model == Editing(initial))
}

///|
test "stale activation cannot process a prepared Preview result" {
  let initial = {
    ..test_editing_state("# Current\n", Saved),
    activation: { document_id: "document-1", generation: 1 },
    preview: Preparing,
  }
  let stale : Activation = { document_id: "document-1", generation: 0 }
  let (model, _) = test_update(
    Editing(initial),
    PreviewPrepared(stale, initial.text, Err(OutOfSync)),
  )
  assert_true(model == Editing(initial))
}

///|
test "TextChanged remains free of repository IO" {
  let (model, command) = test_update(
    Editing(test_editing_state("# Old\n", Saved)),
    TextChanged(
      { document_id: "document-1", generation: 0 },
      @text_change.TextChange::ReplaceAll("# New\n"),
    ),
  )
  guard model is Editing(editing) else { fail("expected Editing") }
  assert_eq(editing.text, "# New\n")
  assert_true(editing.save == Waiting)
  assert_false(@debug.to_string(command).contains("IndexedDB"))
}

///|
test "New Document serializes creation from a saved activation" {
  let initial = test_editing_state("# Current\n", Saved)
  let (model, command) = test_update(Editing(initial), CreateRequested)
  guard model is Editing(editing) else { fail("expected Editing") }
  assert_true(editing.creation == Creating)
  assert_true(editing.activation == initial.activation)
  assert_eq(editing.text, initial.text)
  assert_eq(editing.repository, initial.repository)
  assert_true(@debug.to_string(command).contains("IndexedDBPut"))
}

///|
test "acknowledged creation installs the next Snapshot and activates baseline" {
  let initial = {
    ..test_editing_state("# Current\n", Saved),
    creation: Creating,
  }
  let next = @source_repository.RepositorySnapshot::from_sources([
    @source_repository.SourceRecord::new("document-1", "# Current\n").unwrap(),
    @source_repository.SourceRecord::new("document-2", "# Untitled\n").unwrap(),
  ]).unwrap()
  let (model, command) = test_update(
    Editing(initial),
    CreateCompleted(
      initial.activation,
      @source_repository.CreateResult::Created(next, "document-2"),
    ),
  )
  guard model is Editing(editing) else { fail("expected Editing") }
  assert_eq(editing.activation.document_id, "document-2")
  assert_eq(editing.activation.generation, 1)
  assert_eq(editing.text, "# Untitled\n")
  assert_true(editing.save == Saved)
  assert_true(editing.creation == Idle)
  assert_eq(editing.repository, next)
  assert_false(@debug.to_string(command).contains("IndexedDB"))
}

///|
test "creation failure preserves the active document and Snapshot" {
  let initial = {
    ..test_editing_state("# Current\n", Saved),
    creation: Creating,
  }
  let (model, _) = test_update(
    Editing(initial),
    CreateCompleted(
      initial.activation,
      @source_repository.CreateResult::Failed(
        @source_repository.CreateFailure::QuotaExceeded,
      ),
    ),
  )
  guard model is Editing(editing) else { fail("expected Editing") }
  assert_true(editing.activation == initial.activation)
  assert_eq(editing.text, initial.text)
  assert_true(editing.save == initial.save)
  assert_true(
    editing.creation ==
    CreationFailed(@source_repository.CreateFailure::QuotaExceeded),
  )
  assert_true(editing.preview == initial.preview)
  assert_eq(editing.repository, initial.repository)
}

///|
test "unacknowledged text prevents switching and creation" {
  let snapshot = @source_repository.RepositorySnapshot::from_sources([
    @source_repository.SourceRecord::new("document-1", "# Waiting\n").unwrap(),
    @source_repository.SourceRecord::new("document-2", "# Other\n").unwrap(),
  ]).unwrap()
  let initial = {
    ..test_editing_state("# Waiting\n", Waiting),
    repository: snapshot,
  }
  let (selected, _) = test_update(
    Editing(initial),
    DocumentSelected("document-2"),
  )
  let (created, _) = test_update(Editing(initial), CreateRequested)
  assert_true(selected == Editing(initial))
  assert_true(created == Editing(initial))
}

///|
test "queued text input cannot change a creating document" {
  let initial = {
    ..test_editing_state("# Current\n", Saved),
    creation: Creating,
  }
  let (model, _) = test_update(
    Editing(initial),
    TextChanged(
      initial.activation,
      @text_change.TextChange::ReplaceAll("# Queued\n"),
    ),
  )
  assert_true(model == Editing(initial))
}

///|
test "SaveRequested uses the repository snapshot" {
  let initial = test_editing_state("# New\n", Waiting)
  let (model, command) = test_update(
    Editing(initial),
    SaveRequested(initial.activation, "# New\n"),
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
      initial.activation,
      "# New\n",
      @source_repository.SaveResult::Stored(next),
    ),
  )
  guard model is Editing(editing) else { fail("expected Editing") }
  assert_true(editing.save == Saved)
  assert_eq(editing.repository, next)
}

///|
test "stale completion remains fenced by activation and candidate" {
  let initial = {
    ..test_editing_state("# Latest\n", Saving("# Latest\n")),
    activation: { document_id: "document-1", generation: 1 },
  }
  let stale : Activation = { document_id: "document-1", generation: 0 }
  let (model, _) = test_update(
    Editing(initial),
    SaveCompleted(
      stale,
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
      initial.activation,
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
      initial.activation,
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
      { document_id: "document-2", generation: 0 },
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
    initial.activation,
    "# Old\n",
    @source_repository.SaveResult::Stored(test_repository()),
  )
  let stale_failure = SaveCompleted(
    initial.activation,
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
