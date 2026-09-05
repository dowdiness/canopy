///|
const AUTOSAVE_QUIET_MS : Int = 250

///|
const AUTOSAVE_MAXIMUM_MS : Int = 2000

///|
const DELETE_WATCHDOG_MS : Int = 4000

///|
const COMPACT_MAX_WIDTH : Int = 640

///|
fn compact_viewport(width : Int) -> Bool {
  width <= COMPACT_MAX_WIDTH
}

///|
extern "js" fn observed_change_order() -> Int64 =
  #| () => BigInt(Date.now())

///|
fn preview_input(editing : EditingState) -> @preview.Input {
  @preview.Input(
    editing.activation.generation,
    editing.documents.text(editing.activation.document_id).unwrap_or(""),
  )
}

///|
fn decode_import(bytes : Bytes) -> String? {
  Some(
    @utf8.decode(bytes.view(), ignore_bom=true)
    .replace_all(old="\r\n", new="\n")
    .replace_all(old="\r", new="\n"),
  ) catch {
    _ => None
  }
}

///|
fn export_payload(editing : EditingState) -> (String, String) {
  let text = editing.documents
    .text(editing.activation.document_id)
    .unwrap_or("")
  let filename = match @document_lead.derive_name(text) {
    Ok(Some(name)) => name + ".md"
    Ok(None) | Err(_) => "untitled.md"
  }
  (filename, text)
}

///|
#warnings("-unused_async")
async fn download_export(filename : String, text : String) -> Unit noraise {
  @dom_boundary.download_text(filename, text) catch {
    _ => ()
  }
}

///|
fn deletion_blocks_document_changes(editing : EditingState) -> Bool {
  let document_id = editing.activation.document_id
  let persistence_blocks = match editing.documents.delete_status(document_id) {
    Some(Available) | Some(Failed(_, _)) | None => false
    Some(Waiting(_))
    | Some(Deleting(_))
    | Some(Probing(_))
    | Some(Unknown(_)) => true
  }
  let confirmation_blocks = match editing.deletion {
    DeleteDeferred(target) | DeleteConfirmation(target) => target == document_id
    NoDeletion => false
  }
  persistence_blocks || confirmation_blocks
}

///|
fn can_activate(editing : EditingState) -> Bool {
  editing.creation != Creating &&
  !editing.documents.is_composing(editing.activation.document_id) &&
  !deletion_blocks_document_changes(editing)
}

///|
fn can_select(editing : EditingState, document_id : String) -> Bool {
  can_activate(editing) &&
  document_id != editing.activation.document_id &&
  editing.documents.text(document_id) is Some(_) &&
  (match editing.documents.delete_status(document_id) {
    Some(Available) | Some(Failed(_, _)) => true
    _ => false
  })
}

///|
fn run_decision(
  documents : Documents,
  decision : DocumentsDecision,
  emit : @rabbita.Emit[DocumentsFeedback],
) -> @rabbita.Cmd {
  match decision {
    DocumentsArmQuiet(document_id, order) =>
      @cmd.delay(emit(QuietElapsed(document_id, order)), AUTOSAVE_QUIET_MS)
    DocumentsArmMaximum(document_id, id) =>
      @cmd.delay(emit(MaximumElapsed(document_id, id)), AUTOSAVE_MAXIMUM_MS)
    DocumentsPersist(operation) =>
      match operation.origin {
        New =>
          @source_repository.store_new(
            documents.snapshot(),
            operation.source.document_id(),
            operation.source.text(),
            operation.source.change_order(),
            result=emit.map(result => SaveCompleted(operation, result)),
          )
        Existing =>
          @source_repository.save(
            documents.snapshot(),
            operation.source.document_id(),
            operation.source.text(),
            change_order=operation.source.change_order(),
            result=emit.map(result => SaveCompleted(operation, result)),
          )
      }
    DeleteSource(operation) =>
      @source_repository.delete(
        documents.snapshot(),
        operation.document_id,
        result=emit.map(result => DeleteCompleted(operation, result)),
      )
    ArmDeleteWatchdog(operation) =>
      @cmd.delay(emit(DeleteWatchdogElapsed(operation)), DELETE_WATCHDOG_MS)
    ProbeDelete(operation) =>
      @source_repository.probe(
        documents.snapshot(),
        operation.document_id,
        result=emit.map(result => DeleteProbeCompleted(operation, result)),
      )
    ArmProbeWatchdog(operation) =>
      @cmd.delay(emit(DeleteProbeElapsed(operation)), DELETE_WATCHDOG_MS)
  }
}

///|
fn run_decisions(
  documents : Documents,
  decisions : Array[DocumentsDecision],
  emit : @rabbita.Emit[DocumentsFeedback],
) -> @rabbita.Cmd {
  @cmd.batch(decisions.map(decision => run_decision(documents, decision, emit)))
}

///|
fn activate_surface(
  activation : Activation,
  text : String,
  mode : EditorMode,
  emit : @rabbita.Emit[Msg],
  text_area : @text_area.TextArea,
  preview_engine : @preview.PreviewEngine,
) -> (@preview.State, @rabbita.Cmd) {
  let input = @preview.Input(activation.generation, text)
  let (preview, activate_command) = preview_engine.activate(input)
  let (preview, request_command) = if mode == Text {
    (preview, @cmd.none)
  } else {
    preview_engine.request(
      preview,
      input,
      emit.map(event => PreviewEvent(event)),
    )
  }
  (
    preview,
    @cmd.batch([text_area.initialize(text), activate_command, request_command]),
  )
}

///|
fn activate(
  editing : EditingState,
  document_id : String,
  emit : @rabbita.Emit[Msg],
  text_area : @text_area.TextArea,
  preview_engine : @preview.PreviewEngine,
) -> (EditingState, @rabbita.Cmd) {
  let text = editing.documents.text(document_id).unwrap_or("")
  let activation = {
    document_id,
    generation: editing.activation.generation + 1,
  }
  let (preview, surface) = activate_surface(
    activation,
    text,
    editing.mode,
    emit,
    text_area,
    preview_engine,
  )
  let remember = @source_repository.remember_editing_document(
    editing.documents.snapshot(),
    document_id,
  )
  ({ ..editing, activation, preview }, @cmd.batch([surface, remember]))
}

///|
fn reduce_documents(
  editing : EditingState,
  event : DocumentsEvent,
  emit : @rabbita.Emit[Msg],
) -> (EditingState, @rabbita.Cmd) {
  let (documents, decisions) = editing.documents.reduce(event)
  (
    { ..editing, documents, },
    run_decisions(
      documents,
      decisions,
      emit.map(feedback => DocumentsLifecycle(feedback)),
    ),
  )
}

///|
fn initial_state(
  emit : @rabbita.Emit[Msg],
  compact : Bool,
) -> (Model, @rabbita.Cmd) {
  (
    Loading(compact),
    @source_repository.open(result=emit.map(result => Opened(result))),
  )
}

///|
fn update(
  model : Model,
  msg : Msg,
  emit : @rabbita.Emit[Msg],
  text_area : @text_area.TextArea,
  preview_engine : @preview.PreviewEngine,
) -> (Model, @rabbita.Cmd) {
  match (model, msg) {
    (Loading(compact), Opened(Ready(snapshot, initial))) =>
      match initial {
        Some(source) => {
          let documents = initial_documents(snapshot)
          let activation = { document_id: source.document_id(), generation: 0 }
          let (preview, command) = activate_surface(
            activation,
            source.text(),
            Text,
            emit,
            text_area,
            preview_engine,
          )
          (
            Editing({
              activation,
              documents,
              creation: Idle,
              deletion: NoDeletion,
              mode: Text,
              compact,
              preview,
              import_failed: false,
              new_preparation_request_id: 0,
            }),
            command,
          )
        }
        None => {
          let documents = initial_documents(snapshot)
          let preparing : PreparingNewState = {
            documents,
            mode: Text,
            compact,
            request_id: 1,
            next_activation_generation: 0,
          }
          (
            PreparingNew(preparing),
            @source_repository.create(
              snapshot,
              result=emit.map(result => EmptyCreateCompleted(1, result)),
            ),
          )
        }
      }
    (Loading(compact), Opened(Failed(failure))) =>
      (Recovery(failure, compact), @cmd.none)
    (PreparingNew(preparing), EmptyCreateCompleted(request_id, result)) =>
      if preparing.request_id != request_id {
        (model, @cmd.none)
      } else {
        match result {
          Failed(failure) =>
            (
              Recovery(creation_open_failure(failure), preparing.compact),
              @cmd.none,
            )
          Created(document_id) => {
            let (documents, _) = preparing.documents.reduce(
              DocumentsNew(document_id),
            )
            let activation = {
              document_id,
              generation: preparing.next_activation_generation,
            }
            let (preview, command) = activate_surface(
              activation,
              "",
              preparing.mode,
              emit,
              text_area,
              preview_engine,
            )
            (
              Editing({
                activation,
                documents,
                creation: Idle,
                deletion: NoDeletion,
                mode: preparing.mode,
                compact: preparing.compact,
                preview,
                import_failed: false,
                new_preparation_request_id: preparing.request_id,
              }),
              command,
            )
          }
        }
      }
    (Editing(editing), ExampleSelected(owner, text)) =>
      if owner != editing.activation {
        (Editing(editing), @cmd.none)
      } else if editing.creation == Creating ||
        deletion_blocks_document_changes(editing) {
        (
          Editing(editing),
          text_area.initialize(
            editing.documents.text(owner.document_id).unwrap_or(""),
          ),
        )
      } else {
        (
          Editing(editing),
          @cmd.batch([
            text_area.initialize(text),
            emit(TextChanged(owner, @text_change.TextChange::ReplaceAll(text))),
          ]),
        )
      }
    (Editing(editing), TextChanged(owner, change)) =>
      if owner != editing.activation {
        (Editing(editing), @cmd.none)
      } else if editing.creation == Creating ||
        deletion_blocks_document_changes(editing) {
        (
          Editing(editing),
          text_area.initialize(
            editing.documents.text(owner.document_id).unwrap_or(""),
          ),
        )
      } else {
        match
          change.apply(editing.documents.text(owner.document_id).unwrap_or("")) {
          None =>
            (
              Editing(editing),
              text_area.value(text => {
                emit(
                  TextChanged(owner, @text_change.TextChange::ReplaceAll(text)),
                )
              }),
            )
          Some(text) if editing.documents.text(owner.document_id) == Some(text) =>
            (Editing(editing), @cmd.none)
          Some(text) => {
            let observed = @source_repository.ChangeOrder::from_int64(
              observed_change_order(),
            ).unwrap()
            let (editing, command) = reduce_documents(
              editing,
              DocumentsTextChanged(owner.document_id, text, observed),
              emit,
            )
            if editing.documents.text(owner.document_id) != Some(text) {
              (
                Editing(editing),
                text_area.initialize(
                  editing.documents.text(owner.document_id).unwrap_or(""),
                ),
              )
            } else {
              let (preview, preview_command) = preview_engine.document_changed(
                editing.preview,
                preview_input(editing),
                change,
                emit.map(event => PreviewEvent(event)),
              )
              (
                Editing({ ..editing, preview, }),
                @cmd.batch([command, preview_command]),
              )
            }
          }
        }
      }
    (Editing(editing), CompositionStarted(owner)) =>
      if owner != editing.activation ||
        editing.creation == Creating ||
        deletion_blocks_document_changes(editing) {
        (Editing(editing), @cmd.none)
      } else {
        let (editing, command) = reduce_documents(
          editing,
          DocumentsCompositionStarted(owner.document_id),
          emit,
        )
        (Editing(editing), command)
      }
    (Editing(editing), CompositionEnded(owner)) =>
      if owner != editing.activation {
        (Editing(editing), @cmd.none)
      } else {
        let (editing, command) = reduce_documents(
          editing,
          DocumentsCompositionEnded(owner.document_id),
          emit,
        )
        let deletion = match editing.deletion {
          DeleteDeferred(document_id) => DeleteConfirmation(document_id)
          other => other
        }
        (Editing({ ..editing, deletion, }), command)
      }
    (Editing(editing), ModeSelected(mode)) => {
      let entering_preview = editing.mode == Text && mode != Text
      let leaving_preview = editing.mode != Text && mode == Text
      let editing = { ..editing, mode, }
      if entering_preview {
        let (preview, command) = preview_engine.request(
          editing.preview,
          preview_input(editing),
          emit.map(event => PreviewEvent(event)),
        )
        (Editing({ ..editing, preview, }), command)
      } else if leaving_preview {
        let (preview, command) = preview_engine.suspend(
          editing.preview,
          preview_input(editing),
        )
        (Editing({ ..editing, preview, }), command)
      } else {
        (Editing(editing), @cmd.none)
      }
    }
    (Editing(editing), ImportFilesSelected(files)) =>
      match files.get(0) {
        None => (Editing(editing), @cmd.none)
        Some(file) =>
          (
            Editing({ ..editing, import_failed: false }),
            @cmd.attempt(result => emit(ImportReadCompleted(result)), async fn() {
              file.as_blob().bytes()
            }),
          )
      }
    (Editing(editing), ImportReadCompleted(Err(_))) =>
      (Editing({ ..editing, import_failed: true }), @cmd.none)
    (Editing(editing), ImportReadCompleted(Ok(bytes))) =>
      match decode_import(bytes) {
        None => (Editing({ ..editing, import_failed: true }), @cmd.none)
        Some(text) =>
          (
            Editing(editing),
            @source_repository.create(
              editing.documents.snapshot(),
              result=emit.map(result => ImportCreateCompleted(text, result)),
            ),
          )
      }
    (Editing(editing), ImportCreateCompleted(_, Failed(_))) =>
      (Editing({ ..editing, import_failed: true }), @cmd.none)
    (Editing(editing), ImportCreateCompleted(text, Created(document_id))) => {
      let observed = @source_repository.ChangeOrder::from_int64(
        observed_change_order(),
      ).unwrap()
      let (next, persist) = reduce_documents(
        editing,
        DocumentsImported(document_id, text, observed),
        emit,
      )
      if next.documents.text(document_id) is None {
        (Editing({ ..editing, import_failed: true }), @cmd.none)
      } else {
        let (next, surface) = activate(
          { ..next, creation: Idle, deletion: NoDeletion, import_failed: false },
          document_id,
          emit,
          text_area,
          preview_engine,
        )
        (Editing(next), @cmd.batch([persist, surface]))
      }
    }
    (Editing(editing), DismissImportFailure) =>
      (Editing({ ..editing, import_failed: false }), @cmd.none)
    (Editing(editing), ExportRequested) => {
      let (filename, text) = export_payload(editing)
      (
        Editing(editing),
        @cmd.effect(async fn() noraise { download_export(filename, text) }),
      )
    }
    (Editing(editing), PreviewEvent(event)) => {
      let (preview, command) = preview_engine.update(
        editing.preview,
        preview_input(editing),
        event,
        emit.map(event => PreviewEvent(event)),
      )
      (Editing({ ..editing, preview, }), command)
    }
    (Loading(_), ViewportChanged(width)) =>
      (Loading(compact_viewport(width)), @cmd.none)
    (model, DocumentsLifecycle(feedback)) =>
      reduce_documents_feedback(
        model, feedback, emit, text_area, preview_engine,
      )
    (PreparingNew(preparing), ViewportChanged(width)) =>
      (
        PreparingNew({ ..preparing, compact: compact_viewport(width) }),
        @cmd.none,
      )
    (Recovery(failure, _), ViewportChanged(width)) =>
      (Recovery(failure, compact_viewport(width)), @cmd.none)
    (Editing(editing), ViewportChanged(width)) =>
      (Editing({ ..editing, compact: compact_viewport(width) }), @cmd.none)
    (Editing(editing), CreateRequested) =>
      if !can_activate(editing) {
        (Editing(editing), @cmd.none)
      } else {
        let owner = editing.activation.document_id
        (
          Editing({ ..editing, creation: Creating }),
          @source_repository.create(
            editing.documents.snapshot(),
            result=emit.map(result => CreateCompleted(owner, result)),
          ),
        )
      }
    (Editing(editing), CreateCompleted(owner, Created(document_id))) =>
      if editing.creation != Creating || owner != editing.activation.document_id {
        (Editing(editing), @cmd.none)
      } else {
        let (editing, _) = reduce_documents(
          editing,
          DocumentsNew(document_id),
          emit,
        )
        let (next, command) = activate(
          { ..editing, creation: Idle },
          document_id,
          emit,
          text_area,
          preview_engine,
        )
        (Editing(next), command)
      }
    (Editing(editing), CreateCompleted(owner, Failed(failure))) =>
      if editing.creation == Creating && owner == editing.activation.document_id {
        (Editing({ ..editing, creation: CreationFailed(failure) }), @cmd.none)
      } else {
        (Editing(editing), @cmd.none)
      }
    (Editing(editing), DocumentSelected(document_id)) =>
      if !can_select(editing, document_id) {
        (Editing(editing), @cmd.none)
      } else {
        let (editing, command) = activate(
          editing, document_id, emit, text_area, preview_engine,
        )
        (Editing(editing), command)
      }
    (Editing(editing), DeleteRequested(document_id)) =>
      if editing.deletion != NoDeletion ||
        editing.documents.text(document_id) is None {
        (Editing(editing), @cmd.none)
      } else {
        match editing.documents.delete_status(document_id) {
          Some(Available) | Some(Failed(_, _)) => {
            let deferred = editing.documents.is_composing(
              editing.activation.document_id,
            )
            (
              Editing({
                ..editing,
                deletion: if deferred {
                  DeleteDeferred(document_id)
                } else {
                  DeleteConfirmation(document_id)
                },
              }),
              @cmd.none,
            )
          }
          _ => (Editing(editing), @cmd.none)
        }
      }
    (Editing(editing), DeleteCancelled) =>
      match editing.deletion {
        DeleteDeferred(_) | DeleteConfirmation(_) =>
          (Editing({ ..editing, deletion: NoDeletion }), @cmd.none)
        _ => (Editing(editing), @cmd.none)
      }
    (Editing(editing), DeleteConfirmed(document_id)) =>
      if editing.deletion != DeleteConfirmation(document_id) {
        (Editing(editing), @cmd.none)
      } else {
        let (next, command) = reduce_documents(
          editing,
          DeleteConfirmed(document_id),
          emit,
        )
        reconcile_active(
          { ..next, deletion: NoDeletion },
          emit,
          text_area,
          preview_engine,
          command,
        )
      }
    (Editing(editing), RetryDelete(document_id)) => {
      let (next, command) = reduce_documents(
        editing,
        RetryDelete(document_id),
        emit,
      )
      (Editing(next), command)
    }
    (Editing(editing), VisibilityChanged(true)) => {
      let (editing, command) = reduce_documents(
        editing,
        DocumentsVisibilityFlush(editing.activation.document_id),
        emit,
      )
      (Editing(editing), command)
    }
    (Editing(editing), RetrySave) => {
      let (editing, command) = reduce_documents(
        editing,
        DocumentsRetrySave(editing.activation.document_id),
        emit,
      )
      (Editing(editing), command)
    }
    (Editing(editing), DismissDeleteFailure(document_id)) => {
      let (editing, command) = reduce_documents(
        editing,
        DismissDeleteFailure(document_id),
        emit,
      )
      (Editing(editing), command)
    }
    _ => (model, @cmd.none)
  }
}

///|
fn reduce_documents_feedback(
  model : Model,
  feedback : DocumentsFeedback,
  emit : @rabbita.Emit[Msg],
  text_area : @text_area.TextArea,
  preview_engine : @preview.PreviewEngine,
) -> (Model, @rabbita.Cmd) {
  let event = DocumentsFeedbackReceived(feedback)
  match model {
    Editing(editing) => {
      let (editing, command) = reduce_documents(editing, event, emit)
      reconcile_active(editing, emit, text_area, preview_engine, command)
    }
    PreparingNew(preparing) => {
      let (documents, decisions) = preparing.documents.reduce(event)
      (
        PreparingNew({ ..preparing, documents, }),
        run_decisions(
          documents,
          decisions,
          emit.map(feedback => DocumentsLifecycle(feedback)),
        ),
      )
    }
    Loading(_) | Recovery(_, _) => (model, @cmd.none)
  }
}

///|
fn reconcile_active(
  editing : EditingState,
  emit : @rabbita.Emit[Msg],
  text_area : @text_area.TextArea,
  preview_engine : @preview.PreviewEngine,
  prior : @rabbita.Cmd,
) -> (Model, @rabbita.Cmd) {
  let active_id = editing.activation.document_id
  let active_unknown = editing.documents.delete_status(active_id)
    is Some(Unknown(_))
  if !active_unknown && editing.documents.text(active_id) is Some(_) {
    (Editing(editing), prior)
  } else {
    match editing.documents.fallback_document(active_id) {
      Some(document_id) => {
        let (editing, command) = activate(
          editing, document_id, emit, text_area, preview_engine,
        )
        (Editing(editing), @cmd.batch([prior, command]))
      }
      None => {
        let request_id = editing.new_preparation_request_id + 1
        (
          PreparingNew({
            documents: editing.documents,
            mode: editing.mode,
            compact: editing.compact,
            request_id,
            next_activation_generation: editing.activation.generation + 1,
          }),
          @cmd.batch([
            prior,
            @source_repository.create(
              editing.documents.snapshot(),
              result=emit.map(result => EmptyCreateCompleted(request_id, result)),
            ),
          ]),
        )
      }
    }
  }
}

///|
fn creation_open_failure(
  failure : @source_repository.CreateFailure,
) -> @source_repository.OpenFailure {
  match failure {
    DocumentIdentityUnavailable => DocumentIdentityUnavailable
    StorageUnavailable => StorageUnavailable
    QuotaExceeded => QuotaExceeded
    WriteFailed => WriteFailed
  }
}
