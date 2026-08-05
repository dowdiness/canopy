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
/// Commit one canonical source request and install state only after success.
fn commit_source(
  editor : @markdown.MarkdownEditor,
  model : DriverModel,
  state : @core.ApplicationState,
  source : String,
  operation : String,
) -> (DriverModel, Bool, Bool) {
  let fail_commit = model.fail_next_editor_commit
  let next = { ..model, fail_next_editor_commit: false }
  let request = if fail_commit {
    @markdown.MarkdownEditRequest::ReplaceText(
      start=-1,
      delete_len=0,
      inserted="",
    )
  } else {
    @markdown.MarkdownEditRequest::ReplaceSource(source)
  }
  match editor.commit(request) {
    Ok(@markdown.Applied(document, _)) =>
      (
        {
          ..next,
          state,
          document,
          source_revision: model.source_revision + 1,
          committed_change_count: model.committed_change_count + 1,
        },
        true,
        true,
      )
    Ok(@markdown.Unchanged(document)) =>
      ({ ..next, state, document }, true, false)
    Err(error) => {
      let failed = record_error(
        next,
        "editor-commit-failed",
        operation,
        "editor commit failed: " + editor_error_detail(error),
      )
      (failed, false, false)
    }
  }
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
) -> (DriverModel, @markdown.MarkdownBlockSelection?, Bool) {
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
  match editor.commit(request) {
    Ok(@markdown.Applied(document, selection)) => {
      let committed = {
        ..next,
        document,
        source_revision: model.source_revision + 1,
        committed_change_count: model.committed_change_count + 1,
      }
      (
        update_preview_document(
          attachment,
          committed,
          preview_requested(model),
          accepted=true,
          changed=true,
        ),
        selection,
        true,
      )
    }
    Ok(@markdown.Unchanged(document)) =>
      (
        update_preview_document(
          attachment,
          { ..next, document, },
          preview_requested(model),
          accepted=true,
          changed=false,
        ),
        None,
        true,
      )
    Err(error) => {
      let failed = record_error(
        next,
        "editor-commit-failed",
        operation,
        "editor commit failed: " + editor_error_detail(error),
      )
      (
        update_preview_document(
          attachment,
          failed,
          preview_requested(model),
          accepted=false,
          changed=false,
        ),
        None,
        false,
      )
    }
  }
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
  let (committed, committed_selection, _) = commit_block_request(
    editor, attachment, model, request, "editor-dispatch",
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
        block_selection_after_render(
          selection,
          next.source_revision,
          report_superseded=false,
          emit,
        ),
      )
    None =>
      if applied {
        (next, @rabbita_runtime.none)
      } else {
        match originating_selection {
          Some(selection) =>
            (
              next,
              block_selection_after_render(
                selection,
                next.source_revision,
                report_superseded=true,
                emit,
              ),
            )
          None =>
            (
              next,
              after_render(
                scheduler => {
                  ignore(scheduler)
                  @dom_boundary.focus_id(control_id)
                },
                emit,
              ),
            )
        }
      }
  }
}
