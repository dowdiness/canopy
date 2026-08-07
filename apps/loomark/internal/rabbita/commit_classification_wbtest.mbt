///|
/// Classification boundary matrix:
///
/// | receipt result | domain term | source_revision | committed_change_count | changed |
/// | --- | --- | --- | --- | --- |
/// | Applied | history-changing commit | +1 | +1 | true |
/// | Unchanged | history no-op | unchanged | unchanged | false |
///
/// Unrelated model fields pass through untouched in both cases. The
/// classification is independent of source equality: Applied advances
/// history regardless of whether the resulting Markdown source differs.
/// Selection extraction and preview demand stay in the calling shell.

///|
fn test_model(document : @markdown.MarkdownDocumentSnapshot) -> DriverModel {
  {
    state: @core.ApplicationState::ApplicationState(@core.Raw),
    document,
    document_id: @archive.LoomarkDocumentId::from_string("test-doc") catch {
      _ => abort("test document id must construct")
    },
    archive_persistence_enabled: false,
    semantic_document: None,
    semantic_read_count: 0,
    split_preview_open: false,
    compact_split: false,
    active_block_key: None,
    replica_id: "replica-a",
    source_revision: 5,
    text_input_generation: 0,
    fatal: false,
    error: None,
    error_code: None,
    error_operation: None,
    error_count: 0,
    committed_change_count: 3,
    fail_next_editor_commit: false,
    resize_count: 0,
    selection: None,
    measurement: None,
    event_detail: None,
    event_count: 0,
    control_ready: false,
    event_install_count: 0,
    event_unload_count: 0,
    listening: false,
    rejection: None,
    archive_tracker: @repository.LocalArchiveRequestTracker::new(),
    local_storage_warning: false,
  }
}

///|
test "history-changing commit advances both counters and reports changed" {
  let editor = try! @markdown.MarkdownEditor(
    agent_id="agent-a",
    source="# Title",
  )
  let document = editor.snapshot()
  let model = test_model(document)
  let (next, changed) = classify_commit(
    model,
    @markdown.MarkdownCommitResult::Applied(document, None),
  )
  assert_eq(next.source_revision, 6)
  assert_eq(next.committed_change_count, 4)
  assert_true(changed)
  assert_eq(next.document.source(), "# Title")
}

///|
test "history no-op leaves counters untouched and reports unchanged" {
  let editor = try! @markdown.MarkdownEditor(
    agent_id="agent-a",
    source="# Title",
  )
  let document = editor.snapshot()
  let model = test_model(document)
  let (next, changed) = classify_commit(
    model,
    @markdown.MarkdownCommitResult::Unchanged(document),
  )
  assert_eq(next.source_revision, 5)
  assert_eq(next.committed_change_count, 3)
  assert_false(changed)
  assert_eq(next.document.source(), "# Title")
}

///|
test "classification preserves unrelated model fields" {
  let editor = try! @markdown.MarkdownEditor(
    agent_id="agent-a",
    source="# Title",
  )
  let document = editor.snapshot()
  let model = {
    ..test_model(document),
    fatal: true,
    error: Some("boom"),
    split_preview_open: true,
  }
  let (next, _) = classify_commit(
    model,
    @markdown.MarkdownCommitResult::Applied(document, None),
  )
  assert_true(next.fatal)
  assert_eq(next.error, Some("boom"))
  assert_true(next.split_preview_open)
  assert_eq(next.document_id.value(), "test-doc")
  assert_eq(next.replica_id, "replica-a")
}
