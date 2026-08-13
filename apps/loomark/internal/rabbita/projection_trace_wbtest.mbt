///|
fn projection_trace_test_context(
  source? : String = "# Before\n",
  split_preview_open? : Bool = false,
) -> (
  @markdown.MarkdownEditor,
  @md_markdown.MarkdownSemanticAttachment,
  DriverModel,
) {
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
  run_projection_trace_event(
    editor,
    attachment,
    model,
    Editing(ReplaceSource("# After\n")),
  )
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
  projection_trace_enable(capacity=32, clock=() => {
    ticks.val += 1
    ticks.val
  })
  ticks
}

///|
test "accepted preview-demand edit records independent synchronous trace axes" {
  let ticks = projection_trace_enable_counting()
  defer projection_trace_disable()
  let (editor, attachment, model) = projection_trace_test_context(
    split_preview_open=true,
  )
  let next = run_projection_trace_preview_edit(editor, attachment, model)
  assert_eq(next.document.source(), "# After\n")
  assert_eq(projection_trace_phases(), [
    PROJECTION_TRACE_PHASE_A0,
    PROJECTION_TRACE_PHASE_C,
    PROJECTION_TRACE_PHASE_A1,
    PROJECTION_TRACE_PHASE_B,
    PROJECTION_TRACE_PHASE_D,
    PROJECTION_TRACE_PHASE_E,
    PROJECTION_TRACE_PHASE_F,
  ])
  assert_eq(ticks.val, 7)
  let event_id = projection_trace_event_id(0)
  let request_id = projection_trace_request_id(1)
  let group_work_id = projection_trace_group_work_id(4)
  assert_true(event_id != Some(0))
  assert_true(request_id != Some(0))
  assert_true(group_work_id != Some(0))
  assert_eq(projection_trace_request_id(0), Some(0))
  assert_eq(projection_trace_group_work_id(0), Some(0))
  assert_eq(projection_trace_presentation_id(0), Some(0))
  assert_eq(projection_trace_event_id(2), event_id)
  assert_eq(projection_trace_request_id(2), Some(0))
  assert_eq(projection_trace_request_id(3), request_id)
  for index in 4..<7 {
    assert_eq(projection_trace_request_id(index), request_id)
    assert_eq(projection_trace_group_work_id(index), group_work_id)
    assert_eq(projection_trace_presentation_id(index), Some(0))
  }
  assert_eq(
    projection_trace_status(5),
    Some(PROJECTION_TRACE_STATUS_ADOPTION_ACCEPTED),
  )
  assert_eq(
    projection_trace_group_outcome(6),
    Some(PROJECTION_TRACE_GROUP_OUTCOME_ADOPTED_NOT_PRESENTED),
  )
  assert_eq(
    projection_trace_reason(6),
    Some(PROJECTION_TRACE_REASON_PRESENTATION_NOT_OBSERVED),
  )
}

///|
test "enabled and disabled preview edits are behaviorally equivalent" {
  let enabled_ticks = projection_trace_enable_counting()
  defer projection_trace_disable()
  let (enabled_editor, enabled_attachment, enabled_model) = projection_trace_test_context(
    split_preview_open=true,
  )
  let enabled = run_projection_trace_preview_edit(
    enabled_editor, enabled_attachment, enabled_model,
  )
  assert_true(projection_trace_count() > 0)
  assert_true(enabled_ticks.val > 0)

  let disabled_ticks : @ref.Ref[Int] = @ref.Ref(0)
  projection_trace_enable(capacity=32, clock=() => {
    disabled_ticks.val += 1
    disabled_ticks.val
  })
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
  assert_eq(
    disabled.semantic_document is Some(_),
    enabled.semantic_document is Some(_),
  )
  assert_eq(projection_trace_count(), 0)
  assert_eq(disabled_ticks.val, 0)
}

///|

///|
test "rejected authority request records omission reason" {
  ignore(projection_trace_enable_counting())
  defer projection_trace_disable()
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
  assert_eq(
    projection_trace_reason(0),
    Some(PROJECTION_TRACE_REASON_NOT_ACCEPTED),
  )
  projection_trace_disable()
}

///|
test "demand-only Preview records C-F without authority phases" {
  ignore(projection_trace_enable_counting())
  defer projection_trace_disable()
  let (editor, attachment, model) = projection_trace_test_context()
  let next = run_projection_trace_event(
    editor,
    attachment,
    model,
    Navigation(SelectPreview),
  )
  assert_true(preview_requested(next))
  assert_eq(next.semantic_read_count, model.semantic_read_count + 1)
  assert_eq(projection_trace_phases(), [
    PROJECTION_TRACE_PHASE_C,
    PROJECTION_TRACE_PHASE_D,
    PROJECTION_TRACE_PHASE_E,
    PROJECTION_TRACE_PHASE_F,
  ])
  assert_eq(
    projection_trace_group_outcome(3),
    Some(PROJECTION_TRACE_GROUP_OUTCOME_ADOPTED_NOT_PRESENTED),
  )
  assert_eq(
    projection_trace_reason(3),
    Some(PROJECTION_TRACE_REASON_PRESENTATION_NOT_OBSERVED),
  )
}

///|
test "source-equal causal advance synchronizes the projection mirror" {
  let ticks = projection_trace_enable_counting()
  defer projection_trace_disable()
  let (editor, attachment, model) = projection_trace_test_context(
    source="# Title",
  )
  let emit : @cmd.Emit[DriverEvent] = @cmd.Emit(_ => @rabbita_runtime.none)
  let (next, _, accepted, changed, _) = try! commit_edit_request(
    editor,
    model,
    @markdown.MarkdownEditRequest::ReplaceText(
      start=0,
      delete_len=1,
      inserted="#",
    ),
    "source-equal",
    emit,
  )
  assert_true(accepted)
  assert_false(changed)
  assert_eq(next.document.source(), model.document.source())
  assert_true(next.document_version != model.document_version)
  assert_eq(next.source_revision, model.source_revision)
  assert_eq(next.committed_change_count, model.committed_change_count + 1)
  ignore(
    update_preview_after_authority(attachment, next, false, accepted~, changed~),
  )
  assert_eq(projection_trace_phases(), [
    PROJECTION_TRACE_PHASE_A0,
    PROJECTION_TRACE_PHASE_C,
    PROJECTION_TRACE_PHASE_A1,
    PROJECTION_TRACE_PHASE_B,
    0,
  ])
  assert_eq(
    projection_trace_request_disposition(4),
    Some(PROJECTION_TRACE_REQUEST_NO_DEMAND),
  )
  assert_eq(projection_trace_reason(4), Some(PROJECTION_TRACE_REASON_NO_DEMAND))
  assert_eq(ticks.val, 5)
}

///|
test "source-equal demanded Preview republishes retained artifact" {
  let (editor, attachment, initial_model) = projection_trace_test_context(
    source="# Title",
    split_preview_open=true,
  )
  let model = {
    ..initial_model,
    semantic_document: Some(attachment.document()),
  }
  let ticks = projection_trace_enable_counting()
  defer projection_trace_disable()
  let emit : @cmd.Emit[DriverEvent] = @cmd.Emit(_ => @rabbita_runtime.none)
  let (next, _, accepted, changed, _) = try! commit_edit_request(
    editor,
    model,
    @markdown.MarkdownEditRequest::ReplaceText(
      start=0,
      delete_len=1,
      inserted="#",
    ),
    "source-equal-preview",
    emit,
  )
  assert_true(accepted)
  assert_false(changed)
  ignore(
    update_preview_after_authority(attachment, next, true, accepted~, changed~),
  )
  projection_trace_driver_model_adopted()
  projection_trace_adopted_not_presented()
  assert_eq(projection_trace_phases(), [
    PROJECTION_TRACE_PHASE_A0,
    PROJECTION_TRACE_PHASE_C,
    PROJECTION_TRACE_PHASE_A1,
    PROJECTION_TRACE_PHASE_B,
    PROJECTION_TRACE_PHASE_D,
    PROJECTION_TRACE_PHASE_E,
    PROJECTION_TRACE_PHASE_F,
  ])
  let work_id = projection_trace_group_work_id(4)
  assert_true(work_id != Some(0))
  assert_eq(projection_trace_group_work_id(5), work_id)
  assert_eq(projection_trace_group_work_id(6), work_id)
  assert_eq(
    projection_trace_group_outcome(6),
    Some(PROJECTION_TRACE_GROUP_OUTCOME_ADOPTED_NOT_PRESENTED),
  )
  assert_eq(ticks.val, 7)
}

///|
test "source-equal authority request adopts newly demanded Preview once" {
  let (editor, attachment, model) = projection_trace_test_context(
    source="# Title",
    split_preview_open=true,
  )
  let ticks = projection_trace_enable_counting()
  defer projection_trace_disable()
  let emit : @cmd.Emit[DriverEvent] = @cmd.Emit(_ => @rabbita_runtime.none)
  let (next, _, accepted, changed, _) = try! commit_edit_request(
    editor,
    model,
    @markdown.MarkdownEditRequest::ReplaceText(
      start=0,
      delete_len=1,
      inserted="#",
    ),
    "source-equal-new-preview",
    emit,
  )
  ignore(
    update_preview_after_authority(attachment, next, false, accepted~, changed~),
  )
  projection_trace_driver_model_adopted()
  projection_trace_adopted_not_presented()
  assert_eq(projection_trace_phases(), [
    PROJECTION_TRACE_PHASE_A0,
    PROJECTION_TRACE_PHASE_C,
    PROJECTION_TRACE_PHASE_A1,
    PROJECTION_TRACE_PHASE_B,
    PROJECTION_TRACE_PHASE_D,
    PROJECTION_TRACE_PHASE_E,
    PROJECTION_TRACE_PHASE_F,
  ])
  let request_id = projection_trace_request_id(1)
  for index in 3..<7 {
    assert_eq(projection_trace_request_id(index), request_id)
  }
  let work_id = projection_trace_group_work_id(4)
  assert_true(work_id != Some(0))
  assert_eq(projection_trace_group_work_id(5), work_id)
  assert_eq(projection_trace_group_work_id(6), work_id)
  assert_eq(projection_trace_terminal_count(work_id.unwrap_or(0)), 1)
  assert_eq(ticks.val, 7)
}

///|
test "NoDemand creates no group work and does not tick the clock" {
  let ticks = projection_trace_enable_counting()
  defer projection_trace_disable()
  let (editor, attachment, model) = projection_trace_test_context()
  let next = run_projection_trace_event(
    editor,
    attachment,
    model,
    Navigation(SelectRaw),
  )

  assert_false(preview_requested(next))
  assert_eq(projection_trace_count(), 0)
  assert_eq(projection_trace_phase(0), None)
  assert_eq(projection_trace_status(0), None)
  assert_eq(projection_trace_reason(0), None)
  assert_eq(ticks.val, 0)
}

///|
test "recovery replacement invalidates active projection request" {
  let ticks = projection_trace_enable_counting()
  defer projection_trace_disable()
  let (editor, attachment, model) = projection_trace_test_context(
    split_preview_open=true,
  )
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
  assert_true(
    try! (session.val.editor.history_since() != accepted_history_before_failure),
  )
  assert_eq(projection_trace_phases(), [
    PROJECTION_TRACE_PHASE_A0,
    PROJECTION_TRACE_PHASE_C,
    PROJECTION_TRACE_PHASE_A1,
    PROJECTION_TRACE_PHASE_B,
    0,
    PROJECTION_TRACE_PHASE_B,
    PROJECTION_TRACE_PHASE_C,
    0,
  ])
  assert_eq(
    projection_trace_request_disposition(4),
    Some(PROJECTION_TRACE_REQUEST_FAILED),
  )
  assert_eq(
    projection_trace_reason(4),
    Some(PROJECTION_TRACE_REASON_GENERATION_INVALIDATED),
  )
  let seed_request_id = projection_trace_request_id(5)
  assert_true(seed_request_id != Some(0))
  for index in 5..<8 {
    assert_eq(projection_trace_request_id(index), seed_request_id)
    assert_eq(projection_trace_group_work_id(index), Some(0))
  }
  assert_eq(
    projection_trace_request_disposition(7),
    Some(PROJECTION_TRACE_REQUEST_NO_DEMAND),
  )
  assert_eq(projection_trace_reason(7), Some(PROJECTION_TRACE_REASON_NO_DEMAND))
  assert_eq(ticks.val, 8)
  projection_trace_driver_model_adopted()
  projection_trace_adopted_not_presented()
  assert_eq(projection_trace_count(), 8)
}

///|
test "trace correlation axes allocate lazily" {
  projection_trace_enable(capacity=16, clock=() => 1)
  defer projection_trace_disable()
  let event_id = projection_trace_begin_authority_event()
  projection_trace_test_progress(
    event_id~,
    request_id=0,
    group_work_id=0,
    presentation_id=0,
    group=PROJECTION_TRACE_GROUP_NONE,
    phase=PROJECTION_TRACE_PHASE_A0,
  )
  let request_id = projection_trace_test_begin_request(event_id)
  let preview_work = projection_trace_test_begin_group(
    request_id,
    PROJECTION_TRACE_GROUP_PREVIEW,
  )
  let diagnostics_work = projection_trace_test_begin_group(
    request_id,
    PROJECTION_TRACE_GROUP_DIAGNOSTICS,
  )
  let presentation_id = projection_trace_test_begin_presentation()
  projection_trace_test_present(preview_work, presentation_id)
  projection_trace_test_present(diagnostics_work, presentation_id)
  assert_eq(projection_trace_event_id(0), Some(event_id))
  assert_eq(projection_trace_request_id(0), Some(0))
  assert_eq(projection_trace_group_work_id(0), Some(0))
  assert_eq(projection_trace_presentation_id(0), Some(0))
  assert_eq(projection_trace_group_work_id(1), Some(preview_work))
  assert_eq(projection_trace_group_work_id(2), Some(diagnostics_work))
  assert_eq(projection_trace_presentation_id(1), Some(presentation_id))
  assert_eq(projection_trace_presentation_id(2), Some(presentation_id))
  assert_eq(projection_trace_event_id(1), Some(event_id))
  assert_eq(projection_trace_event_id(2), Some(event_id))
  assert_eq(projection_trace_request_id(1), Some(request_id))
  assert_eq(projection_trace_request_id(2), Some(request_id))
  assert_eq(projection_trace_group(1), Some(PROJECTION_TRACE_GROUP_PREVIEW))
  assert_eq(projection_trace_group(2), Some(PROJECTION_TRACE_GROUP_DIAGNOSTICS))
}

///|
test "NoDemand request creates no group work" {
  projection_trace_enable(capacity=8, clock=() => 1)
  defer projection_trace_disable()
  let request_id = projection_trace_test_begin_request(0)
  projection_trace_request_no_demand(request_id)
  assert_eq(
    projection_trace_request_disposition(0),
    Some(PROJECTION_TRACE_REQUEST_NO_DEMAND),
  )
  assert_eq(projection_trace_group_work_id(0), Some(0))
}

///|
test "each group work accepts exactly one terminal outcome" {
  projection_trace_enable(capacity=8, clock=() => 1)
  defer projection_trace_disable()
  let request_id = projection_trace_test_begin_request(0)
  let work_id = projection_trace_test_begin_group(
    request_id,
    PROJECTION_TRACE_GROUP_PREVIEW,
  )
  projection_trace_test_group_terminal(
    work_id,
    PROJECTION_TRACE_GROUP_OUTCOME_ADOPTED_NOT_PRESENTED,
    PROJECTION_TRACE_REASON_PRESENTATION_NOT_OBSERVED,
  )
  projection_trace_test_group_terminal(
    work_id,
    PROJECTION_TRACE_GROUP_OUTCOME_FAILED,
    PROJECTION_TRACE_REASON_FAILED,
  )
  assert_eq(projection_trace_terminal_count(work_id), 1)
}

///|
test "bounded trace reports overflow and drops without clock reads" {
  let ticks : @ref.Ref[Int] = @ref.Ref(0)
  projection_trace_enable(capacity=1, clock=() => {
    ticks.val += 1
    ticks.val
  })
  defer projection_trace_disable()
  let request_id = projection_trace_test_begin_request(0)
  projection_trace_request_no_demand(request_id)
  projection_trace_request_no_demand(request_id)
  assert_true(projection_trace_overflowed())
  assert_eq(projection_trace_dropped_count(), 1)
  assert_eq(ticks.val, 1)
}

///|
test "adoption resolves immutable group metadata by work id" {
  projection_trace_enable(capacity=8, clock=() => 1)
  defer projection_trace_disable()
  let event_id = projection_trace_begin_authority_event()
  let request_id = projection_trace_test_begin_request(event_id)
  let preview_work = projection_trace_test_begin_group(
    request_id,
    PROJECTION_TRACE_GROUP_PREVIEW,
  )
  ignore(
    projection_trace_test_begin_group(
      request_id,
      PROJECTION_TRACE_GROUP_DIAGNOSTICS,
    ),
  )
  projection_trace_test_group_adopted(preview_work)
  assert_eq(projection_trace_event_id(0), Some(event_id))
  assert_eq(projection_trace_request_id(0), Some(request_id))
  assert_eq(projection_trace_group_work_id(0), Some(preview_work))
  assert_eq(projection_trace_group(0), Some(PROJECTION_TRACE_GROUP_PREVIEW))
  assert_eq(
    projection_trace_status(0),
    Some(PROJECTION_TRACE_STATUS_ADOPTION_ACCEPTED),
  )
}

///|
test "trace ID exhaustion fails closed before wraparound" {
  projection_trace_enable(capacity=4, clock=() => 1)
  defer projection_trace_disable()
  projection_trace_test_exhaust_group_ids()
  let request_id = projection_trace_test_begin_request(0)
  assert_eq(
    projection_trace_test_begin_group(
      request_id,
      PROJECTION_TRACE_GROUP_PREVIEW,
    ),
    0,
  )
  assert_true(projection_trace_overflowed())
}

///|
test "production adoption and retirement consume every requested group" {
  projection_trace_enable(capacity=8, clock=() => 1)
  defer projection_trace_disable()
  let event_id = projection_trace_begin_authority_event()
  let request_id = projection_trace_test_begin_request(event_id)
  let preview_work = projection_trace_test_begin_group(
    request_id,
    PROJECTION_TRACE_GROUP_PREVIEW,
  )
  let diagnostics_work = projection_trace_test_begin_group(
    request_id,
    PROJECTION_TRACE_GROUP_DIAGNOSTICS,
  )
  projection_trace_driver_model_adopted()
  projection_trace_adopted_not_presented()
  assert_eq(projection_trace_count(), 4)
  assert_eq(projection_trace_group_work_id(0), Some(preview_work))
  assert_eq(projection_trace_group_work_id(1), Some(diagnostics_work))
  assert_eq(projection_trace_group_work_id(2), Some(preview_work))
  assert_eq(projection_trace_group_work_id(3), Some(diagnostics_work))
  assert_eq(projection_trace_terminal_count(preview_work), 1)
  assert_eq(projection_trace_terminal_count(diagnostics_work), 1)
}
