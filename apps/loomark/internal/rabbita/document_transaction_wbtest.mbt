///|
#cfg(target="js")
extern "js" fn markdown_archive_export_failure_arm(detail : String) -> Unit =
  #|(detail) => {
  #|  globalThis.__canopyMarkdownArchiveExportFailure = { detail, count: 0 };
  #|}

///|
#cfg(target="js")
extern "js" fn markdown_archive_export_failure_reset() -> Unit =
  #|() => { delete globalThis.__canopyMarkdownArchiveExportFailure; }

///|
#cfg(target="js")
extern "js" fn markdown_archive_export_failure_count() -> Int =
  #|() => {
  #|  const injection = globalThis.__canopyMarkdownArchiveExportFailure;
  #|  return injection == null ? 0 : (injection.count ?? 0);
  #|}

///|
fn document_transaction_test_model(
  document : @markdown.MarkdownDocumentSnapshot,
  version : @markdown.MarkdownDocumentVersion,
) -> DriverModel {
  {
    state: @core.ApplicationState::ApplicationState(@core.Raw),
    runtime_state: EditorRuntimeState::Healthy,
    document,
    document_version: version,
    document_id: @archive.LoomarkDocumentId::from_string(
      "document-transaction-test",
    ) catch {
      _ => abort("test document id must construct")
    },
    raw_selection: None,
    archive_persistence_enabled: false,
    semantic_document: None,
    preview_artifact: None,
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
    archive_tracker: @repository.LocalArchiveRequestTracker::new(),
    local_storage_warning: false,
  }
}

///|
#cfg(target="js")
test "commit_edit_request preserves accepted frontier after export failure" {
  markdown_archive_export_failure_reset()
  defer markdown_archive_export_failure_reset()
  projection_trace_enable(capacity=8, clock=() => 1)
  defer projection_trace_disable()
  let editor = try! @markdown.MarkdownEditor(
    agent_id="archive-export-failure-writer",
    source="# Before\n",
  )
  let model = document_transaction_test_model(
    editor.snapshot(),
    editor.version(),
  )
  let emit : @cmd.Emit[DriverEvent] = @cmd.Emit(_ => @rabbita_runtime.none)

  markdown_archive_export_failure_arm("history_since export failed")
  let (next, result, accepted, changed, _command) = try! commit_edit_request(
    editor,
    model,
    @markdown.MarkdownEditRequest::ReplaceSource("# After\n"),
    "export-failure",
    emit,
  )

  assert_true(result is None)
  assert_true(accepted)
  assert_true(changed)
  assert_eq(markdown_archive_export_failure_count(), 1)
  assert_eq(editor.portable_markdown(), "# After\n")
  assert_eq(next.document.source(), "# After\n")
  assert_true(next.document_version != model.document_version)
  assert_eq(next.document_version, editor.version())
  assert_eq(next.committed_change_count, model.committed_change_count + 1)
  assert_eq(next.source_revision, model.source_revision + 1)
  assert_false(next.fail_next_editor_commit)
  assert_false(next.force_parser_failure)
  assert_eq(projection_trace_count(), 4)
  let retained_request_id = projection_trace_request_id(1)
  assert_true(retained_request_id != Some(0))
  assert_eq(projection_trace_phase(0), Some(PROJECTION_TRACE_PHASE_A0))
  assert_eq(projection_trace_phase(1), Some(PROJECTION_TRACE_PHASE_C))
  assert_eq(projection_trace_phase(2), Some(PROJECTION_TRACE_PHASE_A1))
  assert_eq(projection_trace_phase(3), Some(PROJECTION_TRACE_PHASE_B))
  assert_eq(projection_trace_request_id(3), retained_request_id)
  for index in 0..<4 {
    assert_eq(
      projection_trace_status(index),
      Some(PROJECTION_TRACE_STATUS_RECORDED),
    )
    assert_eq(
      projection_trace_reason(index),
      Some(PROJECTION_TRACE_REASON_NONE),
    )
  }

  projection_trace_semantic_attachment_read()
  projection_trace_driver_model_adopted()
  projection_trace_adopted_not_presented()
  assert_eq(projection_trace_count(), 8)
  for index in 4..<8 {
    assert_eq(projection_trace_request_id(index), retained_request_id)
  }
  assert_eq(projection_trace_phase(4), Some(0))
  assert_eq(projection_trace_phase(5), Some(PROJECTION_TRACE_PHASE_D))
  assert_eq(projection_trace_phase(6), Some(PROJECTION_TRACE_PHASE_E))
  assert_eq(projection_trace_phase(7), Some(PROJECTION_TRACE_PHASE_F))
}
