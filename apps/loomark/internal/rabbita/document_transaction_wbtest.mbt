///|
fn document_transaction_test_model(
  document : @markdown.MarkdownDocumentSnapshot,
  version : @markdown.MarkdownDocumentVersion,
) -> DriverModel {
  let document_id = @archive.LoomarkDocumentId::from_string(
    "document-transaction-test",
  ) catch {
    _ => abort("test document id must construct")
  }
  {
    state: @core.ApplicationState::ApplicationState(@core.Raw),
    runtime_state: EditorRuntimeState::Healthy,
    document,
    document_version: version,
    document_id,
    raw_selection: None,
    archive_persistence_enabled: false,
    bootstrap_pending: false,
    semantic_document: None,
    preview_artifact: None,
    raw_preview: RawPreviewModel::enabled(),
    semantic_read_count: 0,
    split_preview_open: false,
    compact_split: false,
    active_block_key: None,
    replica_id: "replica-a",
    source_revision: 7,
    text_input_generation: 0,
    fatal: false,
    error: None,
    error_code: None,
    error_operation: None,
    error_count: 0,
    committed_change_count: 11,
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
    archive_queue: @repository.LocalArchivePersistenceQueue::LocalArchivePersistenceQueue(
      document_id~,
      queue_epoch="replica-a",
      current=version,
      durable=Some(version),
    ),
  }
}

///|
#cfg(target="js")
test "accepted edit remains on the interactive path" {
  let editor = try! @markdown.MarkdownEditor(
    agent_id="interactive-edit-writer",
    source="# Before\n",
  )
  let model = {
    ..document_transaction_test_model(editor.snapshot(), editor.version()),
    archive_persistence_enabled: true,
  }
  let emit : @cmd.Emit[DriverEvent] = @cmd.Emit(_ => @rabbita_runtime.none)

  let (next, result, accepted, changed, _command) = try! commit_edit_request(
    editor,
    model,
    @markdown.MarkdownEditRequest::ReplaceSource("# After\n"),
    "interactive-edit",
    emit,
  )

  assert_true(result is Some(_))
  assert_true(accepted)
  assert_true(changed)
  assert_eq(editor.portable_markdown(), "# After\n")
  assert_eq(next.document.source(), "# After\n")
  assert_true(next.document_version != model.document_version)
  assert_eq(next.document_version, editor.version())
}

///|
#cfg(target="js")
test "accepted edit records no archive preparation phases" {
  projection_trace_enable(capacity=16, clock=() => 1)
  defer projection_trace_disable()
  let editor = try! @markdown.MarkdownEditor(
    agent_id="persistence-trace-writer",
    source="# Before\n",
  )
  let model = {
    ..document_transaction_test_model(editor.snapshot(), editor.version()),
    archive_persistence_enabled: true,
  }
  let emit : @cmd.Emit[DriverEvent] = @cmd.Emit(_ => @rabbita_runtime.none)

  let (_next, result, accepted, changed, _command) = try! commit_edit_request(
    editor,
    model,
    @markdown.MarkdownEditRequest::ReplaceSource("# After\n"),
    "persistence-trace",
    emit,
  )

  assert_true(result is Some(_))
  assert_true(accepted)
  assert_true(changed)
  assert_eq(projection_trace_phases(), [
    PROJECTION_TRACE_PHASE_A0,
    PROJECTION_TRACE_PHASE_C,
    PROJECTION_TRACE_PHASE_A1,
    PROJECTION_TRACE_PHASE_B,
    PROJECTION_TRACE_PHASE_H1,
    PROJECTION_TRACE_PHASE_H2,
  ])
}
