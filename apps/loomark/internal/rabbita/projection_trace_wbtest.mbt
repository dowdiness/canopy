///|
fn projection_trace_test_context(
  source? : String = "# Before\n",
  split_preview_open? : Bool = false,
) -> (@markdown.MarkdownEditor, @md_markdown.MarkdownSemanticAttachment, DriverModel) {
  let (editor, attachment) = try! @markdown.MarkdownEditor::with_semantic_attachment(
    agent_id="projection-trace-writer",
    source~,
  )
  let model = {
    ..test_model(try! editor.snapshot(), editor.version()),
    split_preview_open,
  }
  (editor, attachment, model)
}

///|
fn run_projection_trace_event(
  editor : @markdown.MarkdownEditor,
  attachment : @md_markdown.MarkdownSemanticAttachment,
  model : DriverModel,
  event : DriverEvent,
) -> DriverModel {
  let latest_model : @ref.Ref[DriverModel?] = @ref.Ref(Some(model))
  let emit : @cmd.Emit[DriverEvent] = @cmd.Emit(_ => @rabbita_runtime.none)
  let (next, _) = try! update_model(
    editor,
    attachment,
    RawInputCoordinator::RawInputCoordinator(None),
    BlockInputCoordinator::BlockInputCoordinator(),
    model,
    latest_model,
    event,
    emit,
  )
  next
}

///|
fn run_projection_trace_preview_edit(
  editor : @markdown.MarkdownEditor,
  attachment : @md_markdown.MarkdownSemanticAttachment,
  model : DriverModel,
) -> DriverModel {
  run_projection_trace_event(editor, attachment, model, Editing(ReplaceSource("# After\n")))
}

///|
fn run_projection_trace_recovered_event(
  session : @ref.Ref[EditorSession],
  model : DriverModel,
  event : DriverEvent,
) -> DriverModel {
  let latest_model : @ref.Ref[DriverModel?] = @ref.Ref(Some(model))
  let emit : @cmd.Emit[DriverEvent] = @cmd.Emit(_ => @rabbita_runtime.none)
  let raw_input_coordinator = RawInputCoordinator::RawInputCoordinator(None)
  let block_input_coordinator = BlockInputCoordinator::BlockInputCoordinator()
  let active = session.val
  let (next, _) = update_model(
    active.editor,
    active.attachment,
    raw_input_coordinator,
    block_input_coordinator,
    model,
    latest_model,
    event,
    emit,
  ) catch {
    Failure::Failure(_) as failure => {
      raw_input_coordinator.cancel_pending()
      block_input_coordinator.cancel_pending()
      let (recovered, command) = recover_after_parser_failure(
        session, model, failure, emit,
      )
      publish(recovered, Some(raw_input_coordinator), None)
      (recovered, command)
    }
    @markdown.MarkdownEditorError::Committed(..) as committed => {
      raw_input_coordinator.cancel_pending()
      block_input_coordinator.cancel_pending()
      let (recovered, command) = recover_after_parser_failure(
        session, model, committed, emit,
      )
      publish(recovered, Some(raw_input_coordinator), None)
      (recovered, command)
    }
    error => {
      raw_input_coordinator.cancel_pending()
      block_input_coordinator.cancel_pending()
      let (quarantined, command) = quarantine_outer_error(session, model, error)
      publish(quarantined, Some(raw_input_coordinator), None)
      (quarantined, command)
    }
  }
  next
}

///|
fn projection_trace_phases() -> Array[Int] {
  let phases : Array[Int] = []
  for index in 0..<projection_trace_count() {
    match projection_trace_phase(index) {
      Some(phase) => phases.push(phase)
      None => fail("missing trace phase")
    }
  }
  phases
}


///|
fn projection_trace_enable_counting() -> @ref.Ref[Int] {
  let ticks : @ref.Ref[Int] = @ref.Ref(0)
  projection_trace_enable(
    capacity=32,
    clock=() => {
      ticks.val += 1
      ticks.val
    },
  )
  ticks
}

///|
fn assert_projection_trace_phase_status_reason(
  phases : Array[Int],
  statuses : Array[Int],
  reasons : Array[Int],
) -> Unit raise {
  assert_eq(phases.length(), statuses.length())
  assert_eq(phases.length(), reasons.length())
  assert_eq(projection_trace_count(), phases.length())
  for index in 0..<phases.length() {
    assert_eq(projection_trace_phase(index), Some(phases[index]))
    assert_eq(projection_trace_status(index), Some(statuses[index]))
    assert_eq(projection_trace_reason(index), Some(reasons[index]))
  }
}


///|
test "accepted preview-demand edit records one correlated synchronous A-F trace" {
  let ticks = projection_trace_enable_counting()
  let (editor, attachment, model) = projection_trace_test_context(split_preview_open=true)
  let next = run_projection_trace_preview_edit(editor, attachment, model)

  assert_eq(next.document.source(), "# After\n")
  assert_eq(projection_trace_phases(), [
    PROJECTION_TRACE_PHASE_A0,
    PROJECTION_TRACE_PHASE_C,
    PROJECTION_TRACE_PHASE_A1,
    PROJECTION_TRACE_PHASE_D,
    PROJECTION_TRACE_PHASE_E,
    PROJECTION_TRACE_PHASE_F,
  ])
  assert_eq(ticks.val, 6)
  let request_id = projection_trace_request_id(0)
  let group_work_id = projection_trace_group_work_id(0)
  let presentation_id = projection_trace_presentation_id(0)
  for index in 0..<projection_trace_count() {
    assert_eq(projection_trace_status(index), Some(PROJECTION_TRACE_STATUS_RECORDED))
    assert_eq(projection_trace_reason(index), Some(PROJECTION_TRACE_REASON_NONE))
    assert_eq(projection_trace_request_id(index), request_id)
    assert_eq(projection_trace_group_work_id(index), group_work_id)
    assert_eq(projection_trace_presentation_id(index), presentation_id)
    assert_eq(projection_trace_timestamp(index), Some(index + 1))
  }
  projection_trace_disable()
}

///|
test "enabled and disabled preview edits are behaviorally equivalent" {
  let enabled_ticks = projection_trace_enable_counting()
  let (enabled_editor, enabled_attachment, enabled_model) = projection_trace_test_context(
    split_preview_open=true,
  )
  let enabled = run_projection_trace_preview_edit(
    enabled_editor, enabled_attachment, enabled_model,
  )
  assert_true(projection_trace_count() > 0)
  assert_true(enabled_ticks.val > 0)

  let disabled_ticks : @ref.Ref[Int] = @ref.Ref(0)
  projection_trace_enable(
    capacity=32,
    clock=() => {
      disabled_ticks.val += 1
      disabled_ticks.val
    },
  )
  projection_trace_disable()
  let (disabled_editor, disabled_attachment, disabled_model) = projection_trace_test_context(
    split_preview_open=true,
  )
  let disabled = run_projection_trace_preview_edit(
    disabled_editor, disabled_attachment, disabled_model,
  )

  assert_eq(disabled.document.source(), enabled.document.source())
  assert_eq(disabled.source_revision, enabled.source_revision)
  assert_eq(disabled.semantic_read_count, enabled.semantic_read_count)
  assert_eq(disabled.committed_change_count, enabled.committed_change_count)
  assert_eq(disabled.state.mode(), enabled.state.mode())
  assert_eq(disabled.split_preview_open, enabled.split_preview_open)
  assert_eq(disabled.semantic_document is Some(_), enabled.semantic_document is Some(_))
  assert_eq(projection_trace_count(), 0)
  assert_eq(disabled_ticks.val, 0)
}

///|
test "accepted post-commit export failure preserves A0-A1 and does not authorize retry" {
  let ticks = projection_trace_enable_counting()
  let (editor, _, model) = projection_trace_test_context()
  let request_id = projection_trace_begin_request()
  let observed = try! editor.commit_with_receipt_observing(
    @markdown.MarkdownEditRequest::ReplaceSource("# Accepted\n"),
    phase => projection_trace_observe_authority(request_id, phase),
  )
  let receipt = match observed {
    Ok(receipt) => receipt
    Err(_) => abort("expected accepted receipt")
  }
  ignore(receipt)
  let version_after_commit = editor.version()
  let (accepted, frontier_advanced, changed) = try! commit_archive_error(
    editor,
    model,
    @markdown.MarkdownArchiveError::ExportFailed(detail="positive control"),
  )

  assert_true(frontier_advanced)
  assert_true(changed)
  assert_true(accepted.document_version != model.document_version)
  assert_eq(accepted.source_revision, model.source_revision + 1)
  assert_eq(accepted.committed_change_count, model.committed_change_count + 1)
  assert_eq(accepted.document.source(), "# Accepted\n")
  assert_eq(editor.version(), version_after_commit)
  assert_eq(accepted.document_version, version_after_commit)
  assert_projection_trace_phase_status_reason(
    [
      PROJECTION_TRACE_PHASE_A0,
      PROJECTION_TRACE_PHASE_C,
      PROJECTION_TRACE_PHASE_A1,
    ],
    [
      PROJECTION_TRACE_STATUS_RECORDED,
      PROJECTION_TRACE_STATUS_RECORDED,
      PROJECTION_TRACE_STATUS_RECORDED,
    ],
    [
      PROJECTION_TRACE_REASON_NONE,
      PROJECTION_TRACE_REASON_NONE,
      PROJECTION_TRACE_REASON_NONE,
    ],
  )
  for index in 0..<3 {
    assert_eq(projection_trace_request_id(index), Some(request_id))
  }
  assert_eq(ticks.val, 3)
  projection_trace_clear_request(request_id)
  projection_trace_disable()
}

///|
test "rejected authority request records omission reason" {
  ignore(projection_trace_enable_counting())
  let (editor, _, model) = projection_trace_test_context()
  let emit : @cmd.Emit[DriverEvent] = @cmd.Emit(_ => @rabbita_runtime.none)
  let (next, _, accepted, changed, _) = try! commit_edit_request(
    editor,
    { ..model, fail_next_editor_commit: true },
    @markdown.MarkdownEditRequest::ReplaceSource("# Ignored\n"),
    "rejected",
    emit,
  )

  assert_false(accepted)
  assert_false(changed)
  assert_eq(next.document.source(), model.document.source())
  assert_eq(projection_trace_phase(0), Some(PROJECTION_TRACE_PHASE_A0))
  assert_eq(projection_trace_status(0), Some(PROJECTION_TRACE_STATUS_OMITTED))
  assert_eq(projection_trace_reason(0), Some(PROJECTION_TRACE_REASON_NOT_ACCEPTED))
  projection_trace_disable()
}

///|
test "demand-only Preview records C-F without A0 or A1" {
  ignore(projection_trace_enable_counting())
  let (editor, attachment, model) = projection_trace_test_context()
  let next = run_projection_trace_event(
    editor,
    attachment,
    model,
    Navigation(SelectPreview),
  )

  assert_true(preview_requested(next))
  assert_eq(next.semantic_read_count, model.semantic_read_count + 1)
  assert_projection_trace_phase_status_reason(
    [
      PROJECTION_TRACE_PHASE_C,
      PROJECTION_TRACE_PHASE_D,
      PROJECTION_TRACE_PHASE_E,
      PROJECTION_TRACE_PHASE_F,
    ],
    [
      PROJECTION_TRACE_STATUS_RECORDED,
      PROJECTION_TRACE_STATUS_RECORDED,
      PROJECTION_TRACE_STATUS_RECORDED,
      PROJECTION_TRACE_STATUS_RECORDED,
    ],
    [
      PROJECTION_TRACE_REASON_NONE,
      PROJECTION_TRACE_REASON_NONE,
      PROJECTION_TRACE_REASON_NONE,
      PROJECTION_TRACE_REASON_NONE,
    ],
  )
  projection_trace_disable()
}

///|
test "source-equal causal advance changes document version without source revision" {
  let ticks = projection_trace_enable_counting()
  let (editor, _, model) = projection_trace_test_context(source="# Title")
  let emit : @cmd.Emit[DriverEvent] = @cmd.Emit(_ => @rabbita_runtime.none)
  let (next, _, accepted, changed, _) = try! commit_edit_request(
    editor,
    model,
    @markdown.MarkdownEditRequest::ReplaceText(start=0, delete_len=1, inserted="#"),
    "source-equal",
    emit,
  )

  assert_true(accepted)
  assert_false(changed)
  assert_eq(next.document.source(), model.document.source())
  assert_true(next.document_version != model.document_version)
  assert_eq(next.source_revision, model.source_revision)
  assert_eq(next.committed_change_count, model.committed_change_count + 1)
  assert_eq(projection_trace_phases(), [
    PROJECTION_TRACE_PHASE_A0,
    PROJECTION_TRACE_PHASE_A1,
  ])
  assert_eq(projection_trace_status(0), Some(PROJECTION_TRACE_STATUS_RECORDED))
  assert_eq(projection_trace_reason(0), Some(PROJECTION_TRACE_REASON_NONE))
  assert_eq(projection_trace_status(1), Some(PROJECTION_TRACE_STATUS_RECORDED))
  assert_eq(projection_trace_reason(1), Some(PROJECTION_TRACE_REASON_NONE))
  assert_eq(ticks.val, 2)
  projection_trace_disable()
}

///|
test "NoDemand creates no group work and does not tick the clock" {
  let ticks = projection_trace_enable_counting()
  let (editor, attachment, model) = projection_trace_test_context()
  let next = run_projection_trace_event(editor, attachment, model, Navigation(SelectRaw))

  assert_false(preview_requested(next))
  assert_eq(projection_trace_count(), 0)
  assert_eq(projection_trace_phase(0), None)
  assert_eq(projection_trace_status(0), None)
  assert_eq(projection_trace_reason(0), None)
  assert_eq(ticks.val, 0)
  projection_trace_disable()
}

///|
test "recovery replacement invalidates old projection work with final outcome" {
  let ticks = projection_trace_enable_counting()
  let (editor, attachment, model) = projection_trace_test_context(split_preview_open=true)
  let accepted_history_before_failure = try! editor.history_since()
  let session = @ref.Ref(EditorSession::{ editor, attachment })
  let recovered = run_projection_trace_recovered_event(
    session,
    { ..model, force_parser_failure: true },
    Editing(ReplaceSource("# After\n")),
  )

  assert_eq(recovered.document.source(), "# After\n")
  assert_eq(recovered.source_revision, model.source_revision + 1)
  assert_eq(recovered.committed_change_count, model.committed_change_count + 1)
  assert_eq(recovered.reconstruction_attempt_count, 1)
  assert_eq(recovered.error_code, Some("editor-recovered"))
  assert_true(recovered.runtime_state is EditorRuntimeState::Healthy)
  assert_eq(session.val.editor.portable_markdown(), "# After\n")
  assert_true(try! (session.val.editor.history_since() != accepted_history_before_failure))
  assert_projection_trace_phase_status_reason(
    [
      PROJECTION_TRACE_PHASE_A0,
      PROJECTION_TRACE_PHASE_C,
      PROJECTION_TRACE_PHASE_A1,
      PROJECTION_TRACE_PHASE_F,
    ],
    [
      PROJECTION_TRACE_STATUS_RECORDED,
      PROJECTION_TRACE_STATUS_RECORDED,
      PROJECTION_TRACE_STATUS_RECORDED,
      PROJECTION_TRACE_STATUS_OMITTED,
    ],
    [
      PROJECTION_TRACE_REASON_NONE,
      PROJECTION_TRACE_REASON_NONE,
      PROJECTION_TRACE_REASON_NONE,
      PROJECTION_TRACE_REASON_GENERATION_INVALIDATED,
    ],
  )
  let request_id = projection_trace_request_id(0)
  let group_work_id = projection_trace_group_work_id(0)
  for index in 0..<projection_trace_count() {
    assert_eq(projection_trace_request_id(index), request_id)
    assert_eq(projection_trace_group_work_id(index), group_work_id)
  }
  assert_eq(ticks.val, 4)
  projection_trace_driver_model_adopted()
  projection_trace_published()
  assert_eq(projection_trace_count(), 4)
  projection_trace_disable()
}
