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
/// Schedule one complete replacement without putting a command in the model.
fn archive_replacement(
  editor : @markdown.MarkdownEditor,
  model : DriverModel,
  emit : @cmd.Emit[DriverEvent],
) -> (DriverModel, @cmd.Cmd) raise {
  guard model.archive_persistence_enabled else {
    return (model, @rabbita_runtime.none)
  }
  let prepared = @repository.prepare_local_archive(
    document_id=model.document_id,
    editor~,
  ) catch {
    Failure::Failure(_) as failure => raise failure
    @repository.LocalArchivePreparationError::HistoryUnavailable(_) =>
      return (record_local_persistence_failure(model), @rabbita_runtime.none)
    error => raise error
  }
  let (archive_tracker, request_id) = model.archive_tracker.request()
  let command = @archive_storage.replace(request_id, prepared.encoded(), completed=completion => {
    emit(Archive(completion))
  })
  ({ ..model, archive_tracker, }, command)
}

///|
/// Archive failures happen after the local CRDT operation may already have
/// landed. They are storage errors, not parser failures, and use a healthy
/// snapshot plus the explicit version frontier for their accepted counters.
fn accept_after_archive_error(
  editor : @markdown.MarkdownEditor,
  model : DriverModel,
) -> (DriverModel, Bool, Bool) raise {
  let document = editor.snapshot()
  let (accepted, changed) = classify_recovered_frontier(
    model,
    document,
    editor.version(),
  )
  (
    record_local_persistence_failure(accepted),
    accepted.document_version != model.document_version,
    changed,
  )
}

///|
/// Handle the typed archive errors raised while cutting a receipt. Unknown
/// errors and Loom Failure are deliberately not converted here.
fn commit_archive_error(
  editor : @markdown.MarkdownEditor,
  model : DriverModel,
  error : @markdown.MarkdownArchiveError,
) -> (DriverModel, Bool, Bool) raise {
  match error {
    @markdown.MarkdownArchiveError::ExportFailed(..)
    | @markdown.MarkdownArchiveError::HistoryAdmissionFailed(..)
    | @markdown.MarkdownArchiveError::IncompleteHistory
    | @markdown.MarkdownArchiveError::InvalidAgentId
    | @markdown.MarkdownArchiveError::WriterCreationFailed(..)
    | @markdown.MarkdownArchiveError::LimitExceeded(..) =>
      accept_after_archive_error(editor, model)
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
  let receipt = editor.commit_with_receipt(request) catch {
    Failure::Failure(_) as failure => raise failure
    @markdown.MarkdownArchiveError::ExportFailed(..) => {
      let (accepted, frontier_advanced, changed) = accept_after_archive_error(
        editor, next,
      )
      return (accepted, None, frontier_advanced, changed, @rabbita_runtime.none)
    }
    @markdown.MarkdownArchiveError::HistoryAdmissionFailed(..) as error => {
      let (accepted, frontier_advanced, changed) = commit_archive_error(
        editor, next, error,
      )
      return (accepted, None, frontier_advanced, changed, @rabbita_runtime.none)
    }
    @markdown.MarkdownArchiveError::IncompleteHistory as error => {
      let (accepted, frontier_advanced, changed) = commit_archive_error(
        editor, next, error,
      )
      return (accepted, None, frontier_advanced, changed, @rabbita_runtime.none)
    }
    @markdown.MarkdownArchiveError::InvalidAgentId as error => {
      let (accepted, frontier_advanced, changed) = commit_archive_error(
        editor, next, error,
      )
      return (accepted, None, frontier_advanced, changed, @rabbita_runtime.none)
    }
    @markdown.MarkdownArchiveError::WriterCreationFailed(..) as error => {
      let (accepted, frontier_advanced, changed) = commit_archive_error(
        editor, next, error,
      )
      return (accepted, None, frontier_advanced, changed, @rabbita_runtime.none)
    }
    @markdown.MarkdownArchiveError::LimitExceeded(..) as error => {
      let (accepted, frontier_advanced, changed) = commit_archive_error(
        editor, next, error,
      )
      return (accepted, None, frontier_advanced, changed, @rabbita_runtime.none)
    }
    error => raise error
  }
  if inject_parser_failure && receipt is Ok(_) {
    raise Failure::Failure("dev-host injected parser publication failure")
  }
  match receipt {
    Err(@markdown.MarkdownEditorError::Committed(..) as committed) =>
      raise committed
    Err(error) => {
      let failed = record_error(
        next,
        "editor-commit-failed",
        operation,
        "editor commit failed: " + editor_error_detail(error),
      )
      (failed, None, false, false, @rabbita_runtime.none)
    }
    Ok(receipt) => {
      let result = receipt.result()
      let (committed, accepted, changed) = classify_commit(next, receipt)
      match @repository.history_trigger(receipt) {
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
) -> (DriverModel, Bool, Bool, @cmd.Cmd) raise {
  let (committed, _, accepted, changed, command) = commit_edit_request(
    editor,
    model,
    @markdown.MarkdownEditRequest::ReplaceSource(source),
    operation,
    emit,
  )
  let committed = if accepted { { ..committed, state, } } else { committed }
  (committed, accepted, changed, command)
}

///|
/// Commit one typed block request through the atomic façade boundary.
fn commit_block_request(
  editor : @markdown.MarkdownEditor,
  attachment : @md_markdown.MarkdownSemanticAttachment,
  model : DriverModel,
  request : @markdown.MarkdownEditRequest,
  operation : String,
  emit : @cmd.Emit[DriverEvent],
) -> (DriverModel, @markdown.MarkdownBlockSelection?, Bool, @cmd.Cmd) raise {
  let (committed, result, accepted, changed, persistence_command) = commit_edit_request(
    editor, model, request, operation, emit,
  )
  let selection = result.bind(result => {
    match result {
      @markdown.Applied(_, selection) => selection
      @markdown.Unchanged(_) => None
    }
  })
  let committed = update_preview_document(
    attachment,
    committed,
    preview_requested(model),
    accepted~,
    changed~,
  )
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
) -> (DriverModel, Bool, @cmd.Cmd) raise {
  let (committed, committed_selection, _, persistence_command) = commit_block_request(
    editor, attachment, model, request, "editor-dispatch", emit,
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
