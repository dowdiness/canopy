///|
/// Version-frontier classification tests.
fn test_model(
  document : @markdown.MarkdownDocumentSnapshot,
  version : @markdown.MarkdownDocumentVersion,
) -> DriverModel {
  {
    state: @core.ApplicationState::ApplicationState(@core.Raw),
    runtime_state: EditorRuntimeState::Healthy,
    document,
    document_version: version,
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
    force_parser_failure: false,
    force_reconstruction_failure: false,
    reconstruction_attempt_count: 0,
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
test "history-changing commit advances counters and reports source change" {
  let editor = try! @markdown.MarkdownEditor(
    agent_id="agent-a",
    source="# Title",
  )
  let model = test_model(editor.snapshot(), editor.version())
  let receipt = match
    (try! editor.commit_with_receipt(
      @markdown.MarkdownEditRequest::ReplaceSource("## Changed"),
    )) {
    Ok(receipt) => receipt
    Err(_) => abort("expected receipt")
  }
  let (next, accepted, changed) = classify_commit(model, receipt)
  assert_eq(next.source_revision, 6)
  assert_eq(next.committed_change_count, 4)
  assert_true(accepted)
  assert_true(changed)
  assert_eq(next.document.source(), "## Changed")
}

///|
test "source-preserving commit still advances the frontier exactly once" {
  let editor = try! @markdown.MarkdownEditor(
    agent_id="agent-a",
    source="# Title",
  )
  let model = test_model(editor.snapshot(), editor.version())
  let receipt = match
    (try! editor.commit_with_receipt(
      @markdown.MarkdownEditRequest::ReplaceText(
        start=0,
        delete_len=1,
        inserted="#",
      ),
    )) {
    Ok(receipt) => receipt
    Err(_) => abort("expected receipt")
  }
  let (next, accepted, changed) = classify_commit(model, receipt)
  assert_eq(next.source_revision, 5)
  assert_eq(next.committed_change_count, 4)
  assert_true(accepted)
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
    ..test_model(document, editor.version()),
    fatal: true,
    error: Some("boom"),
    split_preview_open: true,
  }
  let receipt = match
    (try! editor.commit_with_receipt(
      @markdown.MarkdownEditRequest::ReplaceSource("changed"),
    )) {
    Ok(receipt) => receipt
    Err(_) => abort("expected receipt")
  }
  let (next, _, _) = classify_commit(model, receipt)
  assert_true(next.fatal)
  assert_eq(next.error, Some("boom"))
  assert_true(next.split_preview_open)
  assert_eq(next.document_id.value(), "test-doc")
  assert_eq(next.replica_id, "replica-a")
}
