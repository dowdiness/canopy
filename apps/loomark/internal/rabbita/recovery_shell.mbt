///|
/// Enter terminal recovery without reading the failed editor again.
fn terminal_raw_recovery(
  model : DriverModel,
  source : String,
  message : String,
) -> (DriverModel, @cmd.Cmd) {
  let next = {
    ..model,
    runtime_state: EditorRuntimeState::RawRecovery(source),
    state: @core.ApplicationState::ApplicationState(@core.Raw),
    semantic_document: None,
    preview_artifact: None,
    split_preview_open: false,
    active_block_key: None,
    selection: None,
    fatal: true,
    force_parser_failure: false,
    force_reconstruction_failure: false,
    error: Some(message),
    error_code: Some("editor-recovery-failed"),
    error_operation: Some("editor-recovery"),
    rejection: None,
  }
  (next, @rabbita_runtime.none)
}

///|
/// Persist through the fresh healthy editor after reconstruction. Failure to
/// prepare storage does not roll back the accepted in-memory document.
fn persist_recovered_editor(
  editor : @markdown.MarkdownEditor,
  model : DriverModel,
  emit : @cmd.Emit[DriverEvent],
) -> (DriverModel, @cmd.Cmd) {
  archive_replacement(editor, model, emit) catch {
    _ => (record_local_persistence_failure(model), @rabbita_runtime.none)
  }
}

///|
fn dispose_projection_session(
  projection_session : @ref.Ref[ProjectionSession?],
) -> Unit {
  match projection_session.val {
    Some(session) => {
      session.dispose()
      projection_session.val = None
    }
    None => ()
  }
}

///|
fn dispose_optional_projection_session(
  projection_session : @ref.Ref[ProjectionSession?]?,
) -> Unit {
  match projection_session {
    Some(session) => dispose_projection_session(session)
    None => ()
  }
}

///|
fn next_projection_generation(
  projection_session : @ref.Ref[ProjectionSession?],
) -> Int {
  match projection_session.val {
    Some(session) => session.generation + 1
    None => 1
  }
}

///|
fn replace_projection_session(
  projection_session : @ref.Ref[ProjectionSession?],
  source : String,
  model : DriverModel,
  generation : Int,
) -> DriverModel {
  dispose_projection_session(projection_session)
  let session = ProjectionSession::ProjectionSession(
    agent_id="loomark-comparison-",
    source~,
    generation~,
    demand=projection_demand_for_model(model),
  ) catch {
    error => return projection_failed_model(model, error.to_string())
  }
  projection_session.val = Some(session)
  model
}

///|
/// Rebuild once from the accepted archive. This is the only shell that may
/// recover after parser Failure or a typed committed-receipt interruption; the
/// old session is never retried or reset.
fn recover_after_parser_failure(
  session_ref : @ref.Ref[EditorSession],
  model : DriverModel,
  failure : Error,
  emit : @cmd.Emit[DriverEvent],
  projection_session? : @ref.Ref[ProjectionSession?],
) -> (DriverModel, @cmd.Cmd) {
  ignore(failure)
  let projection_generation = match projection_session {
    Some(session) => next_projection_generation(session)
    None => 1
  }
  let (state, decision) = reduce_editor_runtime(
    model.runtime_state,
    EditorRecoveryEvent::Failure,
  )
  dispose_optional_projection_session(projection_session)
  match decision {
    EditorRecoveryDecision::Reject => {
      session_ref.val.attachment.dispose()
      terminal_raw_recovery(
        model,
        runtime_source(model),
        "Editing is paused. Copy your Markdown and reload to continue.",
      )
    }
    EditorRecoveryDecision::Continue => {
      let editor = session_ref.val.editor
      let source = editor.portable_markdown()
      let advanced = classify_recovered_source(model, source, editor.version())
      session_ref.val.attachment.dispose()
      terminal_raw_recovery(
        { ..advanced, runtime_state: state },
        source,
        "Editing is paused. Copy your Markdown and reload to continue.",
      )
    }
    EditorRecoveryDecision::Reconstruct => {
      let model = {
        ..model,
        reconstruction_attempt_count: model.reconstruction_attempt_count + 1,
      }
      let old_session = session_ref.val
      let recovery_source = old_session.editor.portable_markdown()
      let recovery_version = old_session.editor.version()
      let recovery = capture_recovery_document(
        model.document_id,
        old_session.editor,
      ) catch {
        _ => {
          old_session.attachment.dispose()
          let (failed_state, _) = reduce_editor_runtime(
            state,
            EditorRecoveryEvent::ReconstructionFailed(recovery_source),
          )
          let advanced = classify_recovered_source(
            model, recovery_source, recovery_version,
          )
          return terminal_raw_recovery(
            { ..advanced, runtime_state: failed_state },
            recovery_source,
            "Your document could not be reopened. Copy it and reload to try again.",
          )
        }
      }
      if model.force_reconstruction_failure {
        old_session.attachment.dispose()
        let (failed_state, _) = reduce_editor_runtime(
          state,
          EditorRecoveryEvent::ReconstructionFailed(recovery.source),
        )
        let advanced = classify_recovered_source(
          model,
          recovery.source,
          recovery.version,
        )
        return terminal_raw_recovery(
          { ..advanced, runtime_state: failed_state },
          recovery.source,
          "Your document could not be reopened. Copy it and reload to try again.",
        )
      }
      let (fresh_editor, fresh_attachment) = reopen_recovery_document(
        recovery, "loomark-recovery-writer-",
      ) catch {
        _ => {
          old_session.attachment.dispose()
          let (failed_state, _) = reduce_editor_runtime(
            state,
            EditorRecoveryEvent::ReconstructionFailed(recovery.source),
          )
          let advanced = classify_recovered_source(
            model,
            recovery.source,
            recovery.version,
          )
          let (terminal, _) = terminal_raw_recovery(
            { ..advanced, runtime_state: failed_state },
            recovery.source,
            "Your document could not be reopened. Copy it and reload to try again.",
          )
          return (terminal, @rabbita_runtime.none)
        }
      }
      let fresh_document = fresh_editor.snapshot() catch {
        _ => {
          old_session.attachment.dispose()
          fresh_attachment.dispose()
          let (failed_state, _) = reduce_editor_runtime(
            state,
            EditorRecoveryEvent::ReconstructionFailed(recovery.source),
          )
          let advanced = classify_recovered_source(
            model,
            recovery.source,
            recovery.version,
          )
          let (terminal, _) = terminal_raw_recovery(
            { ..advanced, runtime_state: failed_state },
            recovery.source,
            "Your document could not be reopened. Copy it and reload to try again.",
          )
          return (terminal, @rabbita_runtime.none)
        }
      }
      let (healthy_state, healthy_decision) = reduce_editor_runtime(
        state,
        EditorRecoveryEvent::ReconstructionSucceeded,
      )
      guard healthy_decision is EditorRecoveryDecision::Continue else {
        return terminal_raw_recovery(
          { ..model, runtime_state: healthy_state },
          recovery.source,
          "Editing is paused. Copy your Markdown and reload to continue.",
        )
      }
      old_session.attachment.dispose()
      session_ref.val = { editor: fresh_editor, attachment: fresh_attachment }
      let (advanced, _) = classify_recovered_frontier(
        model,
        fresh_document,
        fresh_editor.version(),
      )
      let next = {
        ..advanced,
        runtime_state: EditorRuntimeState::Healthy,
        state: @core.ApplicationState::ApplicationState(@core.Raw),
        semantic_document: None,
        preview_artifact: None,
        split_preview_open: false,
        active_block_key: None,
        selection: None,
        fatal: false,
        force_parser_failure: false,
        force_reconstruction_failure: false,
        error: Some("Your document was recovered and editing can continue."),
        error_code: Some("editor-recovered"),
        error_operation: Some("editor-recovery"),
        rejection: None,
      }
      let next = match projection_session {
        Some(session) =>
          replace_projection_session(
            session,
            recovery.source,
            next,
            projection_generation,
          )
        None => next
      }
      projection_trace_recovery_seed_materialized()
      persist_recovered_editor(fresh_editor, next, emit)
    }
  }
}

///|
/// Quarantine an unexpected outer-shell error without calling it a parser
/// failure. This branch is intentionally outside document transactions.
fn quarantine_outer_error(
  session_ref : @ref.Ref[EditorSession],
  model : DriverModel,
  _error : Error,
  projection_session? : @ref.Ref[ProjectionSession?],
) -> (DriverModel, @cmd.Cmd) {
  let editor = session_ref.val.editor
  let source = editor.portable_markdown()
  let advanced = classify_recovered_source(model, source, editor.version())
  session_ref.val.attachment.dispose()
  dispose_optional_projection_session(projection_session)
  terminal_raw_recovery(
    advanced, source, "Editing is paused. Copy your Markdown and reload to continue.",
  )
}
