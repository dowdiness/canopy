///|
/// Keep editor failures categorized without exposing the editor error value.
fn editor_error_detail(error : @markdown.MarkdownEditorError) -> String {
  match error {
    @markdown.InvalidAgentId => "invalid-agent-id"
    @markdown.InitializationFailed(detail~) => detail
    @markdown.ProjectionUnavailable => "projection-unavailable"
    @markdown.InvalidTextRange(..) => "invalid text range"
    @markdown.EditFailed(detail~) => detail
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
) -> (DriverModel, @cmd.Cmd) {
  guard model.archive_persistence_enabled else {
    return (model, @rabbita_runtime.none)
  }
  let prepared = @repository.prepare_local_archive(
    document_id=model.document_id,
    editor~,
  ) catch {
    _ => return (record_local_persistence_failure(model), @rabbita_runtime.none)
  }
  let (archive_tracker, request_id) = model.archive_tracker.request()
  let command = @archive_storage.replace(request_id, prepared.encoded(), completed=completion => {
    emit(ArchiveWriteCompleted(completion))
  })
  ({ ..model, archive_tracker, }, command)
}

///|
/// Shared atomic-commit shell: failure injection, editor commit, receipt
/// classification, and persistence dispatch. Mode-specific concerns
/// (selection extraction, preview demand, application state) stay with the
/// caller. Returns (model, result?, accepted, changed, command) — `result`
/// is present only on a successful Ok receipt so block callers can extract
/// the deep selection outcome without reading SyncEditor cursor state.
fn commit_edit_request(
  editor : @markdown.MarkdownEditor,
  model : DriverModel,
  request : @markdown.MarkdownEditRequest,
  operation : String,
  emit : @cmd.Emit[DriverEvent],
) -> (DriverModel, @markdown.MarkdownCommitResult?, Bool, Bool, @cmd.Cmd) {
  let fail_commit = model.fail_next_editor_commit
  let next = { ..model, fail_next_editor_commit: false }
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
    _ => {
      let document = editor.snapshot()
      let changed = document.source() != model.document.source()
      let accepted = {
        ..next,
        document,
        source_revision: if changed {
          model.source_revision + 1
        } else {
          model.source_revision
        },
        committed_change_count: if changed {
          model.committed_change_count + 1
        } else {
          model.committed_change_count
        },
      }
      return (
        record_local_persistence_failure(accepted),
        None,
        true,
        changed,
        @rabbita_runtime.none,
      )
    }
  }
  match receipt {
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
      let (committed, changed) = classify_commit(next, result)
      match @repository.history_trigger(receipt) {
        @repository.LocalArchivePersistenceDecision::Replace => {
          let (persisted, command) = archive_replacement(
            editor, committed, emit,
          )
          (persisted, Some(result), true, changed, command)
        }
        @repository.LocalArchivePersistenceDecision::Skip =>
          (committed, Some(result), true, changed, @rabbita_runtime.none)
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
) -> (DriverModel, Bool, Bool, @cmd.Cmd) {
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
/// Structural callers receive the deep selection outcome without reading
/// SyncEditor cursor state in this shell.
fn commit_block_request(
  editor : @markdown.MarkdownEditor,
  attachment : @md_markdown.MarkdownSemanticAttachment,
  model : DriverModel,
  request : @markdown.MarkdownEditRequest,
  operation : String,
  emit : @cmd.Emit[DriverEvent],
) -> (DriverModel, @markdown.MarkdownBlockSelection?, Bool, @cmd.Cmd) {
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
  request : @markdown.MarkdownEditRequest,
  originating_selection : BlockSelection?,
  control_id : String,
  emit : @cmd.Emit[DriverEvent],
) -> (DriverModel, @cmd.Cmd) {
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
  publish(next)
  match selection {
    Some(selection) =>
      (
        next,
        @cmd.batch([
          persistence_command,
          block_selection_after_render(
            selection,
            next.source_revision,
            report_superseded=false,
            emit,
          ),
        ]),
      )
    None =>
      if applied {
        (next, persistence_command)
      } else {
        match originating_selection {
          Some(selection) =>
            (
              next,
              @cmd.batch([
                persistence_command,
                block_selection_after_render(
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
