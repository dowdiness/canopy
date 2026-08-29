///|
fn test_app_catalog(
  document_id : String,
  name : String?,
) -> @source_repository.Catalog {
  @source_repository.Catalog::from_entries([
    @source_repository.CatalogEntry::new(document_id, name).unwrap(),
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
    catalog: test_app_catalog("document-1", Some("Old")),
    repository_issues: [],
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
test "opened snapshot selects the first lexical Document ID" {
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
  assert_eq(editing.text, "# A\n")
  assert_true(editing.save == Saved)
  assert_eq(editing.catalog, snapshot.catalog())
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
test "SaveRequested starts a Source record transaction" {
  let (model, command) = test_update(
    Editing(test_editing_state("# New\n", Waiting)),
    SaveRequested("# New\n"),
  )
  guard model is Editing(editing) else { fail("expected Editing") }
  assert_true(editing.save == Saving("# New\n"))
  let rendered = @debug.to_string(command)
  assert_true(rendered.contains("IndexedDBPut"))
  assert_true(rendered.contains("source/v1/document-1"))
}

///|
test "successful Source save installs catalog and retains non-fatal issues" {
  let initial = {
    ..test_editing_state("# New\n", Saving("# New\n")),
    repository_issues: [
      @source_repository.RepositoryIssue::UnknownRecord("other"),
    ],
  }
  let next = test_app_catalog("document-1", Some("New"))
  let success = @source_repository.SaveSuccess::new(next, [
    @source_repository.RepositoryIssue::CatalogWriteFailure,
  ])
  let (model, _) = test_update(
    Editing(initial),
    SaveCompleted(
      "document-1",
      "# New\n",
      @source_repository.SaveResult::Stored(success),
    ),
  )
  guard model is Editing(editing) else { fail("expected Editing") }
  assert_true(editing.save == Saved)
  assert_eq(editing.catalog, next)
  assert_eq(editing.repository_issues, [
    @source_repository.RepositoryIssue::UnknownRecord("other"),
    @source_repository.RepositoryIssue::CatalogWriteFailure,
  ])
}

///|
test "stale successful completion immediately saves the latest Source" {
  let initial = test_editing_state("# Latest\n", Saving("# Old\n"))
  let completed_catalog = test_app_catalog("document-1", Some("Old"))
  let (model, command) = test_update(
    Editing(initial),
    SaveCompleted(
      "document-1",
      "# Old\n",
      @source_repository.SaveResult::Stored(
        @source_repository.SaveSuccess::new(completed_catalog, []),
      ),
    ),
  )
  guard model is Editing(editing) else { fail("expected Editing") }
  assert_true(editing.save == Saving("# Latest\n"))
  let rendered = @debug.to_string(command)
  assert_true(rendered.contains("source/v1/document-1"))
  assert_true(rendered.contains("# Latest"))
}

///|
test "Source failure and another Document completion cannot claim saved state" {
  let initial = test_editing_state("# New\n", Saving("# New\n"))
  let (failed_model, _) = test_update(
    Editing(initial),
    SaveCompleted(
      "document-1",
      "# New\n",
      @source_repository.SaveResult::Failed(
        @source_repository.SaveFailure::WriteFailed,
      ),
    ),
  )
  guard failed_model is Editing(failed) else { fail("expected Editing") }
  assert_true(
    failed.save == Failed(@source_repository.SaveFailure::WriteFailed),
  )

  let next = test_app_catalog("document-1", Some("New"))
  let foreign = SaveCompleted(
    "document-2",
    "# New\n",
    @source_repository.SaveResult::Stored(
      @source_repository.SaveSuccess::new(next, []),
    ),
  )
  let (unchanged, _) = test_update(Editing(initial), foreign)
  assert_true(unchanged == Editing(initial))
}
