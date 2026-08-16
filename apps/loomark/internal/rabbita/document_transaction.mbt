///|
/// Keep editor failures categorized without exposing the editor error value.
fn editor_error_detail(error : @markdown.MarkdownEditorError) -> String {
  match error {
    @markdown.InvalidAgentId => "invalid-agent-id"
    @markdown.InitializationFailed(detail~) => detail
    @markdown.ProjectionUnavailable => "projection-unavailable"
    @markdown.InvalidTextRange(..) => "invalid text range"
    @markdown.EditFailed(detail~) => detail
    @markdown.Committed(..) => "edit-committed"
  }
}

///|
/// Record a preparation/export failure as the latest completed repository
/// request so an older acknowledgment cannot clear the warning.
fn record_local_persistence_failure(model : DriverModel) -> DriverModel {
  guard model.archive_persistence_enabled else { return model }
  let (tracker, request_id) = model.archive_tracker.request()
  let tracker = tracker.complete_failure(request_id)
  { ..model, archive_tracker: tracker, local_storage_warning: true }
}

///|
fn apply_projection_authority(
  projection_session : @ref.Ref[ProjectionSession?],
  model : DriverModel,
  accepted : Bool,
  changed : Bool,
) -> DriverModel {
  guard accepted else { return model }
  match projection_session.val {
    None => model
    Some(session) => {
      let effect = if changed {
        ReplaceProjectionSource(model.document.source())
      } else {
        ProjectionSourceUnchanged
      }
      session.advance(effect) catch {
        error => {
          session.dispose()
          return projection_failed_model(model, error.to_string())
        }
      }
      model
    }
  }
}

///|
/// Map archive-package milestones into the fixed application trace.
fn observe_archive_preparation_phase(
  phase : @archive.LoomarkArchivePreparationPhase,
) -> Unit {
  let trace_phase = match phase {
    @archive.LoomarkArchivePreparationPhase::PortableMarkdownCaptured =>
      PROJECTION_TRACE_PHASE_H4
    @archive.LoomarkArchivePreparationPhase::CompleteHistoryCaptured =>
      PROJECTION_TRACE_PHASE_H5
    @archive.LoomarkArchivePreparationPhase::HistoryJsonEncoded =>
      PROJECTION_TRACE_PHASE_H6_HISTORY_JSON
    @archive.LoomarkArchivePreparationPhase::ArchiveEnvelopeEncoded =>
      PROJECTION_TRACE_PHASE_H6_ARCHIVE_ENVELOPE
  }
  projection_trace_persistence_phase(trace_phase)
}

///|
/// Select the observer-free production path unless tracing is active.
fn prepare_traced_local_archive(
  editor : @markdown.MarkdownEditor,
  model : DriverModel,
) -> @repository.PreparedLocalArchive raise {
  if projection_trace_enabled() {
    projection_trace_persistence_phase(PROJECTION_TRACE_PHASE_H3)
    @repository.prepare_local_archive_observing(
      document_id=model.document_id,
      editor~,
      observe_archive_preparation_phase,
    )
  } else {
    @repository.prepare_local_archive(document_id=model.document_id, editor~)
  }
}

///|
/// Schedule one complete replacement without putting a command in the model.
fn archive_replacement(
  editor : @markdown.MarkdownEditor,
  model : DriverModel,
  emit : @cmd.Emit[DriverEvent],
) -> (DriverModel, @cmd.Cmd) raise {
  guard model.archive_persistence_enabled else {
    return (model, @rabbita_runtime.none)
  }
  let prepared = prepare_traced_local_archive(editor, model) catch {
    Failure::Failure(_) as failure => raise failure
    @repository.LocalArchivePreparationError::HistoryUnavailable(_) =>
      return (record_local_persistence_failure(model), @rabbita_runtime.none)
    error => raise error
  }
  let (archive_tracker, request_id) = model.archive_tracker.request()
  let command = @archive_storage.replace(request_id, prepared.encoded(), completed=completion => {
    emit(Archive(completion))
  })
  projection_trace_persistence_phase(PROJECTION_TRACE_PHASE_H7)
  ({ ..model, archive_tracker, }, command)
}

///|
/// Archive failures happen after the local CRDT operation may already have
/// landed. They are storage errors, not parser failures, and use a healthy
/// snapshot plus the explicit version frontier for their accepted counters.
fn accept_after_archive_error(
  editor : @markdown.MarkdownEditor,
  model : DriverModel,
  projection_session? : @ref.Ref[ProjectionSession?],
) -> (DriverModel, Bool, Bool) raise {
  let document = editor.snapshot()
  let (classified, changed) = classify_recovered_frontier(
    model,
    document,
    editor.version(),
  )
  let accepted = classified.document_version != model.document_version
  let next = match projection_session {
    Some(session) =>
      apply_projection_authority(session, classified, accepted, changed)
    None => classified
  }
  (record_local_persistence_failure(next), accepted, changed)
}

///|
/// Handle the typed archive errors raised while cutting a receipt. Unknown
fn commit_archive_error(
  editor : @markdown.MarkdownEditor,
  model : DriverModel,
  error : @markdown.MarkdownArchiveError,
  projection_session? : @ref.Ref[ProjectionSession?],
) -> (DriverModel, Bool, Bool) raise {
  match error {
    @markdown.MarkdownArchiveError::ExportFailed(..)
    | @markdown.MarkdownArchiveError::HistoryAdmissionFailed(..)
    | @markdown.MarkdownArchiveError::IncompleteHistory
    | @markdown.MarkdownArchiveError::InvalidAgentId
    | @markdown.MarkdownArchiveError::WriterCreationFailed(..)
    | @markdown.MarkdownArchiveError::LimitExceeded(..) =>
      accept_after_archive_error(editor, model, projection_session?)
  }
}

///|
/// Shared atomic-commit shell: failure injection, editor commit, receipt
/// classification, and persistence dispatch. Mode-specific concerns
/// (selection extraction, preview demand, application state) stay with the
/// caller. The outer update wrapper owns the only parser-Failure recovery.
fn commit_edit_request(
  editor : @markdown.MarkdownEditor,
  model : DriverModel,
  request : @markdown.MarkdownEditRequest,
  operation : String,
  emit : @cmd.Emit[DriverEvent],
  projection_session? : @ref.Ref[ProjectionSession?],
) -> (DriverModel, @markdown.MarkdownCommitResult?, Bool, Bool, @cmd.Cmd) raise {
  let fail_commit = model.fail_next_editor_commit
  let inject_parser_failure = model.force_parser_failure
  let next = {
    ..model,
    fail_next_editor_commit: false,
    force_parser_failure: false,
  }
  let request = if fail_commit {
    @markdown.MarkdownEditRequest::ReplaceText(
      start=-1,
      delete_len=0,
      inserted="",
    )
  } else {
    request
  }
  let trace_request_id = if projection_trace_enabled() {
    projection_trace_begin_request()
  } else {
    0
  }
  let receipt = try {
    if trace_request_id == 0 {
      editor.commit_with_receipt(request)
    } else {
      editor.commit_with_receipt_observing(request, phase => {
        projection_trace_observe_authority(trace_request_id, phase)
      })
    }
  } catch {
    Failure::Failure(_) as failure => {
      projection_trace_event_omitted(
        trace_request_id,
        PROJECTION_TRACE_REASON_NOT_ACCEPTED,
      )
      raise failure
    }
    @markdown.MarkdownArchiveError::ExportFailed(..) => {
      let (accepted, frontier_advanced, changed) = accept_after_archive_error(
        editor,
        next,
        projection_session?,
      )
      return (accepted, None, frontier_advanced, changed, @rabbita_runtime.none)
    }
    @markdown.MarkdownArchiveError::HistoryAdmissionFailed(..) as error => {
      let (accepted, frontier_advanced, changed) = commit_archive_error(
        editor,
        next,
        error,
        projection_session?,
      )
      return (accepted, None, frontier_advanced, changed, @rabbita_runtime.none)
    }
    @markdown.MarkdownArchiveError::IncompleteHistory as error => {
      let (accepted, frontier_advanced, changed) = commit_archive_error(
        editor,
        next,
        error,
        projection_session?,
      )
      return (accepted, None, frontier_advanced, changed, @rabbita_runtime.none)
    }
    @markdown.MarkdownArchiveError::InvalidAgentId as error => {
      let (accepted, frontier_advanced, changed) = commit_archive_error(
        editor,
        next,
        error,
        projection_session?,
      )
      return (accepted, None, frontier_advanced, changed, @rabbita_runtime.none)
    }
    @markdown.MarkdownArchiveError::WriterCreationFailed(..) as error => {
      let (accepted, frontier_advanced, changed) = commit_archive_error(
        editor,
        next,
        error,
        projection_session?,
      )
      return (accepted, None, frontier_advanced, changed, @rabbita_runtime.none)
    }
    @markdown.MarkdownArchiveError::LimitExceeded(..) as error => {
      let (accepted, frontier_advanced, changed) = commit_archive_error(
        editor,
        next,
        error,
        projection_session?,
      )
      return (accepted, None, frontier_advanced, changed, @rabbita_runtime.none)
    }
    error => {
      projection_trace_clear_request(trace_request_id)
      raise error
    }
  }
  if inject_parser_failure && receipt is Ok(_) {
    projection_trace_generation_invalidated()
    raise Failure::Failure("dev-host injected parser publication failure")
  }
  match receipt {
    Err(@markdown.MarkdownEditorError::Committed(..) as committed) => {
      projection_trace_generation_invalidated()
      raise committed
    }
    Err(error) => {
      projection_trace_event_omitted(
        trace_request_id,
        PROJECTION_TRACE_REASON_NOT_ACCEPTED,
      )
      let failed = record_error(
        next,
        "editor-commit-failed",
        operation,
        "editor commit failed: " + editor_error_detail(error),
      )
      (failed, None, false, false, @rabbita_runtime.none)
    }
    Ok(receipt) => {
      projection_trace_persistence_phase(PROJECTION_TRACE_PHASE_H1)
      let result = receipt.result()
      let (committed, accepted, changed) = classify_commit(next, receipt)
      let committed = match projection_session {
        Some(session) =>
          apply_projection_authority(session, committed, accepted, changed)
        None => committed
      }
      let persistence_decision = @repository.history_trigger(receipt)
      projection_trace_persistence_phase(PROJECTION_TRACE_PHASE_H2)
      match persistence_decision {
        @repository.LocalArchivePersistenceDecision::Replace => {
          let (persisted, command) = archive_replacement(
            editor, committed, emit,
          )
          (persisted, Some(result), accepted, changed, command)
        }
        @repository.LocalArchivePersistenceDecision::Skip =>
          (committed, Some(result), accepted, changed, @rabbita_runtime.none)
      }
    }
  }
}

///|
/// Commit one canonical source request and install state only after success.
fn commit_source(
  editor : @markdown.MarkdownEditor,
  model : DriverModel,
  state : @core.ApplicationState,
  source : String,
  operation : String,
  emit : @cmd.Emit[DriverEvent],
  projection_session? : @ref.Ref[ProjectionSession?],
) -> (DriverModel, Bool, Bool, @cmd.Cmd) raise {
  let (committed, _, accepted, changed, command) = commit_edit_request(
    editor,
    model,
    @markdown.MarkdownEditRequest::ReplaceSource(source),
    operation,
    emit,
    projection_session?,
  )
  let committed = if accepted { { ..committed, state, } } else { committed }
  (committed, accepted, changed, command)
}

///|
fn commit_block_request(
  editor : @markdown.MarkdownEditor,
  attachment : @md_markdown.MarkdownSemanticAttachment,
  model : DriverModel,
  request : @markdown.MarkdownEditRequest,
  operation : String,
  emit : @cmd.Emit[DriverEvent],
  projection_session? : @ref.Ref[ProjectionSession?],
) -> (DriverModel, @markdown.MarkdownBlockSelection?, Bool, @cmd.Cmd) raise {
  let (committed, result, accepted, changed, persistence_command) = commit_edit_request(
    editor,
    model,
    request,
    operation,
    emit,
    projection_session?,
  )
  let selection = result.bind(result => {
    match result {
      @markdown.Applied(_, selection) => selection
      @markdown.Unchanged(_) => None
    }
  })
  if accepted && changed {
    projection_trace_block_materialized()
  }
  let committed = match projection_session {
    Some(session) =>
      update_preview_document_with_projection(
        attachment,
        session,
        committed,
        preview_requested(model),
        accepted~,
        changed~,
      )
    None =>
      update_preview_after_authority(
        attachment,
        committed,
        preview_requested(model),
        accepted~,
        changed~,
      )
  }
  (committed, selection, accepted, persistence_command)
}

///|
/// Reconcile one toolbar commit with the immutable block view and schedule
/// the typed selection only after Rabbita renders that committed document.
fn commit_block_toolbar_request(
  editor : @markdown.MarkdownEditor,
  attachment : @md_markdown.MarkdownSemanticAttachment,
  model : DriverModel,
  latest_model : @ref.Ref[DriverModel?],
  request : @markdown.MarkdownEditRequest,
  originating_selection : BlockSelection?,
  control_id : String,
  emit : @cmd.Emit[DriverEvent],
  projection_session? : @ref.Ref[ProjectionSession?],
) -> (DriverModel, Bool, @cmd.Cmd) raise {
  let (committed, committed_selection, _, persistence_command) = commit_block_request(
    editor,
    attachment,
    model,
    request,
    "editor-dispatch",
    emit,
    projection_session?,
  )
  let selection = committed_selection.bind(selection => {
    block_selection_from_commit(committed.document, selection)
  })
  let applied = committed.source_revision != model.source_revision
  let next = {
    ..committed,
    active_block_key: match selection {
      Some(selection) => Some(selection.key)
      None => if applied { None } else { model.active_block_key }
    },
    selection: match selection {
      Some(selection) => Some(block_selection_label(selection))
      None => if applied { None } else { committed.selection }
    },
  }
  match selection {
    Some(selection) =>
      (
        next,
        applied,
        @cmd.batch([
          persistence_command,
          block_selection_after_render(
            latest_model,
            selection,
            next.source_revision,
            report_superseded=false,
            emit,
          ),
        ]),
      )
    None =>
      if applied {
        (next, applied, persistence_command)
      } else {
        match originating_selection {
          Some(selection) =>
            (
              next,
              applied,
              @cmd.batch([
                persistence_command,
                block_selection_after_render(
                  latest_model,
                  selection,
                  next.source_revision,
                  report_superseded=true,
                  emit,
                ),
              ]),
            )
          None =>
            (
              next,
              applied,
              @cmd.batch([
                persistence_command,
                after_render(
                  scheduler => {
                    ignore(scheduler)
                    @dom_boundary.focus_id(control_id)
                  },
                  emit,
                ),
              ]),
            )
        }
      }
  }
}
