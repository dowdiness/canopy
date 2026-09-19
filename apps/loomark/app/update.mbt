///|
const AUTOSAVE_MAXIMUM_MS : Int = 2000

///|
const COMPACT_MAX_WIDTH : Double = 640.0

///|
fn compact_viewport(width : Double) -> Bool {
  width <= COMPACT_MAX_WIDTH
}

///|
fn preview_input(editing : EditingState) -> @preview.Input {
  @preview.Input(
    editing.activation.generation,
    editing.documents.text(editing.activation.key).unwrap_or(""),
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
  let text = editing.documents.text(editing.activation.key).unwrap_or("")
  let name = @document_lead.derive_name(text).text()
  let filename = if !name.is_empty() { name + ".md" } else { "untitled.md" }
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
fn EditingState::deletion_blocks_document_changes(self : Self) -> Bool {
  let key = self.activation.key
  let persistence_blocks = match self.documents.delete_status(key) {
    Some(NotDeletable) | Some(Deletable) | Some(DeleteFailed(_)) | None => false
    Some(DeletePending) => true
  }
  let confirmation_blocks = match self.deletion {
    DeleteConfirmation(target) => target == key
    NoDeletion => false
  }
  persistence_blocks || confirmation_blocks
}

///|
fn EditingState::can_activate(self : Self) -> Bool {
  self.creation != Creating &&
  !self.documents.is_composing(self.activation.key) &&
  !self.deletion_blocks_document_changes()
}

///|
fn EditingState::selectable_activation(
  self : Self,
  key : @documents.Key,
) -> ActivationTarget? {
  guard self.can_activate() && key != self.activation.key else { return None }
  guard (match self.documents.delete_status(key) {
    Some(NotDeletable) | Some(Deletable) | Some(DeleteFailed(_)) => true
    _ => false
  }) else {
    return None
  }
  activation_target(self.documents, key)
}

///|
fn activation_target(
  documents : @documents.State,
  key : @documents.Key,
) -> ActivationTarget? {
  documents
  .document(key)
  .map(document => { key, document, resume_hint: documents.resume_hint(key), })
}

///|
fn EditingState::can_select(self : Self, key : @documents.Key) -> Bool {
  self.selectable_activation(key) is Some(_)
}

///|
fn run_effect(
  documents : @documents.State,
  effect : @documents.Effect,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Cmd {
  match effect {
    @documents.Effect::ArmMaximum(document_id, id) =>
      @cmd.delay(
        emit(
          DocumentsLifecycle(
            @documents.Feedback::MaximumElapsed(document_id, id),
          ),
        ),
        AUTOSAVE_MAXIMUM_MS,
      )
    @documents.Effect::PersistSource(operation) =>
      @source_repository.save(
        documents.snapshot(),
        operation.document,
        emit.map(result => {
          DocumentsLifecycle(
            @documents.Feedback::SaveCompleted(operation, result),
          )
        }),
      )
    @documents.Effect::PersistCheckpoint(write) =>
      emit(Msg::PersistCheckpoint(write))
    @documents.Effect::DeleteSource(operation) =>
      @source_repository.delete(
        documents.snapshot(),
        operation.document_id,
        emit.map(result => {
          DocumentsLifecycle(
            @documents.Feedback::DeleteCompleted(operation, result),
          )
        }),
      )
  }
}

///|
fn run_effects(
  documents : @documents.State,
  effects : Array[@documents.Effect],
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Cmd {
  @cmd.batch(effects.map(effect => run_effect(documents, effect, emit)))
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
fn EditingState::activate(
  self : Self,
  target : ActivationTarget,
  emit : @rabbita.Emit[Msg],
  text_area : @text_area.TextArea,
  preview_engine : @preview.PreviewEngine,
) -> (EditingState, @rabbita.Cmd) {
  let document = target.document
  let activation = {
    key: target.key,
    generation: self.activation.generation + 1,
  }
  let (preview, surface) = activate_surface(
    activation,
    document.text(),
    self.mode,
    emit,
    text_area,
    preview_engine,
  )
  let remember = match target.resume_hint {
    Some(hint) => hint.remember()
    None => @cmd.none
  }
  ({ ..self, activation, preview, }, @cmd.batch([surface, remember]))
}

///|
fn reduce_documents(
  editing : EditingState,
  event : @documents.Msg,
  emit : @rabbita.Emit[Msg],
) -> (EditingState, @rabbita.Cmd) {
  let (documents, effects) = editing.documents.reduce(event)
  ({ ..editing, documents, }, run_effects(documents, effects, emit))
}

///|
fn initial_page(
  emit : @rabbita.Emit[Msg],
  compact : Bool,
) -> (Page, @rabbita.Cmd) {
  (
    Loading(compact),
    @source_repository.open(emit.map(result => Opened(result))),
  )
}

///|
fn update_page(
  model : Page,
  msg : Msg,
  emit : @rabbita.Emit[Msg],
  text_area : @text_area.TextArea,
  preview_engine : @preview.PreviewEngine,
) -> (Page, @rabbita.Cmd) {
  match (model, msg) {
    (Loading(compact), Opened(Ready(saved, initial))) =>
      match initial {
        Some(document) => {
          let documents = @documents.State::State(saved)
          let activation = {
            key: @documents.Key::source(document.id()),
            generation: 0,
          }
          let (preview, command) = activate_surface(
            activation,
            document.text(),
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
          let documents = @documents.State::State(saved)
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
              saved,
              emit.map(result => EmptyCreateCompleted(1, result)),
            ),
          )
        }
      }
    (Loading(compact), Opened(OpenFailed(failure))) =>
      (Recovery(failure, compact), @cmd.none)
    (PreparingNew(preparing), EmptyCreateCompleted(request_id, result)) =>
      if preparing.request_id != request_id {
        (model, @cmd.none)
      } else {
        match result {
          CreateFailed(failure) =>
            (
              Recovery(creation_open_failure(failure), preparing.compact),
              @cmd.none,
            )
          Created(document_id) => {
            let (documents, _) = preparing.documents.reduce(
              @documents.Msg::New(document_id),
            )
            let activation = {
              key: @documents.Key::source(document_id),
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
        editing.deletion_blocks_document_changes() {
        (
          Editing(editing),
          text_area.initialize(editing.documents.text(owner.key).unwrap_or("")),
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
        editing.deletion_blocks_document_changes() {
        (
          Editing(editing),
          text_area.initialize(editing.documents.text(owner.key).unwrap_or("")),
        )
      } else {
        match change.apply(editing.documents.text(owner.key).unwrap_or("")) {
          None =>
            (
              Editing(editing),
              text_area.value(text => {
                emit(
                  TextChanged(owner, @text_change.TextChange::ReplaceAll(text)),
                )
              }),
            )
          Some(text) if editing.documents.text(owner.key) == Some(text) =>
            (Editing(editing), @cmd.none)
          Some(text) => {
            let (editing, command) = reduce_documents(
              editing,
              @documents.Msg::TextChanged(owner.key, text),
              emit,
            )
            if editing.documents.text(owner.key) != Some(text) {
              (
                Editing(editing),
                text_area.initialize(
                  editing.documents.text(owner.key).unwrap_or(""),
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
        editing.deletion_blocks_document_changes() {
        (Editing(editing), @cmd.none)
      } else {
        let (editing, command) = reduce_documents(
          editing,
          @documents.Msg::CompositionStarted(owner.key),
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
          @documents.Msg::CompositionEnded(owner.key),
          emit,
        )
        (Editing(editing), command)
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
            Editing({ ..editing, import_failed: false, }),
            @cmd.attempt(result => emit(ImportReadCompleted(result)), async fn() {
              file.as_blob().bytes()
            }),
          )
      }
    (Editing(editing), ImportReadCompleted(Err(_))) =>
      (Editing({ ..editing, import_failed: true, }), @cmd.none)
    (Editing(editing), ImportReadCompleted(Ok(bytes))) =>
      match decode_import(bytes) {
        None => (Editing({ ..editing, import_failed: true, }), @cmd.none)
        Some(text) =>
          (
            Editing(editing),
            @source_repository.create(
              editing.documents.snapshot(),
              emit.map(result => ImportCreateCompleted(text, result)),
            ),
          )
      }
    (Editing(editing), ImportCreateCompleted(_, CreateFailed(_))) =>
      (Editing({ ..editing, import_failed: true, }), @cmd.none)
    (Editing(editing), ImportCreateCompleted(text, Created(document_id))) => {
      let (next, persist) = reduce_documents(
        editing,
        @documents.Msg::Imported(document_id, text),
        emit,
      )
      match
        activation_target(next.documents, @documents.Key::source(document_id)) {
        None => (Editing({ ..editing, import_failed: true, }), @cmd.none)
        Some(target) => {
          let ready = {
            ..next,
            creation: Idle,
            deletion: NoDeletion,
            import_failed: false,
          }
          let (next, surface) = ready.activate(
            target, emit, text_area, preview_engine,
          )
          (Editing(next), @cmd.batch([persist, surface]))
        }
      }
    }
    (Editing(editing), DismissImportFailure) =>
      (Editing({ ..editing, import_failed: false, }), @cmd.none)
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
    (Editing(editing), ApplyPendingEdit(document_id, revision)) => {
      let (editing, command) = reduce_documents(
        editing,
        @documents.Msg::ApplyPendingEdit(document_id, revision),
        emit,
      )
      reconcile_active(editing, emit, text_area, preview_engine, command)
    }
    (PreparingNew(preparing), ApplyPendingEdit(document_id, revision)) => {
      let (documents, effects) = preparing.documents.reduce(
        @documents.Msg::ApplyPendingEdit(document_id, revision),
      )
      (
        PreparingNew({ ..preparing, documents, }),
        run_effects(documents, effects, emit),
      )
    }
    (model, DocumentsLifecycle(feedback)) =>
      reduce_documents_feedback(
        model, feedback, emit, text_area, preview_engine,
      )
    (PreparingNew(preparing), ViewportChanged(width)) =>
      (
        PreparingNew({ ..preparing, compact: compact_viewport(width), }),
        @cmd.none,
      )
    (Recovery(failure, _), ViewportChanged(width)) =>
      (Recovery(failure, compact_viewport(width)), @cmd.none)
    (Editing(editing), ViewportChanged(width)) =>
      (Editing({ ..editing, compact: compact_viewport(width), }), @cmd.none)
    (Editing(editing), CreateRequested) =>
      if !editing.can_activate() {
        (Editing(editing), @cmd.none)
      } else {
        let owner = editing.activation.key
        (
          Editing({ ..editing, creation: Creating, }),
          @source_repository.create(
            editing.documents.snapshot(),
            emit.map(result => CreateCompleted(owner, result)),
          ),
        )
      }
    (Editing(editing), CreateCompleted(owner, Created(document_id))) =>
      if editing.creation != Creating || owner != editing.activation.key {
        (Editing(editing), @cmd.none)
      } else {
        let (editing, _) = reduce_documents(
          editing,
          @documents.Msg::New(document_id),
          emit,
        )
        match
          activation_target(
            editing.documents,
            @documents.Key::source(document_id),
          ) {
          None => (Editing(editing), @cmd.none)
          Some(target) => {
            let ready = { ..editing, creation: Idle, }
            let (next, command) = ready.activate(
              target, emit, text_area, preview_engine,
            )
            (Editing(next), command)
          }
        }
      }
    (Editing(editing), CreateCompleted(owner, CreateFailed(failure))) =>
      if editing.creation == Creating && owner == editing.activation.key {
        (Editing({ ..editing, creation: CreationFailed(failure), }), @cmd.none)
      } else {
        (Editing(editing), @cmd.none)
      }
    (Editing(editing), DocumentSelected(document_id)) =>
      match editing.selectable_activation(document_id) {
        None => (Editing(editing), @cmd.none)
        Some(target) => {
          let (editing, command) = editing.activate(
            target, emit, text_area, preview_engine,
          )
          (Editing(editing), command)
        }
      }
    (Editing(editing), DeleteRequested(document_id)) =>
      if editing.creation == Creating ||
        editing.deletion != NoDeletion ||
        editing.documents.text(document_id) is None {
        (Editing(editing), @cmd.none)
      } else {
        match editing.documents.delete_status(document_id) {
          Some(Deletable) | Some(DeleteFailed(_)) =>
            (
              Editing({ ..editing, deletion: DeleteConfirmation(document_id), }),
              @cmd.none,
            )
          _ => (Editing(editing), @cmd.none)
        }
      }
    (Editing(editing), DeleteCancelled) =>
      match editing.deletion {
        DeleteConfirmation(_) =>
          (Editing({ ..editing, deletion: NoDeletion, }), @cmd.none)
        NoDeletion => (Editing(editing), @cmd.none)
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
          { ..next, deletion: NoDeletion, },
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
        @documents.Msg::VisibilityFlush(editing.activation.key),
        emit,
      )
      (Editing(editing), command)
    }
    (Editing(editing), RetrySave) => {
      let (editing, command) = reduce_documents(
        editing,
        @documents.Msg::RetrySave(editing.activation.key),
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
fn Page::saved_documents(self : Self) -> @source_repository.SavedDocuments? {
  match self {
    Editing(editing) => Some(editing.documents.snapshot())
    PreparingNew(preparing) => Some(preparing.documents.snapshot())
    Loading(_) | Recovery(_, _) => None
  }
}

///|
fn Page::project_account(
  self : Self,
  account : @source_repository.AccountId,
) -> Self {
  match self {
    Editing(editing) =>
      Editing({
        ..editing,
        documents: editing.documents.project_account(account),
      })
    PreparingNew(preparing) =>
      PreparingNew({
        ..preparing,
        documents: preparing.documents.project_account(account),
      })
    Loading(_) | Recovery(_, _) => self
  }
}

///|
fn Page::hide_accounts(self : Self) -> Self {
  match self {
    Editing(editing) =>
      Editing({ ..editing, documents: editing.documents.hide_accounts(), })
    PreparingNew(preparing) =>
      PreparingNew({
        ..preparing,
        documents: preparing.documents.hide_accounts(),
      })
    Loading(_) | Recovery(_, _) => self
  }
}

///|
fn persist_checkpoint(
  page : Page,
  attempt : @sync.Attempt,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Cmd {
  match page.saved_documents() {
    Some(saved) =>
      @source_repository.persist_checkpoint_write(
        saved,
        attempt.write(),
        emit.map(result => {
          Sync(CheckpointCompleted(attempt.request_id(), result))
        }),
      )
    None => @cmd.none
  }
}

///|
fn initial_state(
  emit : @rabbita.Emit[Msg],
  compact : Bool,
) -> (Model, @rabbita.Cmd) {
  let (page, page_command) = initial_page(emit, compact)
  ({ page, sync: @sync.State(), }, page_command)
}

///|
fn update(
  model : Model,
  msg : Msg,
  emit : @rabbita.Emit[Msg],
  text_area : @text_area.TextArea,
  preview_engine : @preview.PreviewEngine,
) -> (Model, @rabbita.Cmd) {
  match msg {
    Sync(AccountResolved(lookup_id, result)) => {
      let (sync, selection) = model.sync.resolved(lookup_id, result)
      let page = match selection {
        Some(@sync.AccountSelection::AccountSelected(account)) =>
          model.page.project_account(account)
        Some(@sync.AccountSelection::NoAccountSelected) =>
          model.page.hide_accounts()
        None => model.page
      }
      ({ page, sync, }, @cmd.none)
    }
    PersistCheckpoint(write) => {
      let (sync, start) = model.sync.persist(write)
      let command = start
        .map(attempt => persist_checkpoint(model.page, attempt, emit))
        .unwrap_or(@cmd.none)
      ({ ..model, sync, }, command)
    }
    Sync(CheckpointCompleted(request_id, result)) => {
      let transition = match result {
        @source_repository.CheckpointResult::CheckpointStored(checkpoint) =>
          Some(model.sync.stored(request_id, checkpoint)) catch {
            _ => None
          }
        CheckpointFailed(checkpoint, _) =>
          Some((model.sync.failed(request_id, checkpoint), None)) catch {
            _ => None
          }
      }
      guard transition is Some((sync, next)) else { return (model, @cmd.none) }
      let (page, page_command) = update_page(
        model.page,
        DocumentsLifecycle(CheckpointCompleted(result)),
        emit,
        text_area,
        preview_engine,
      )
      let next_command = next
        .map(attempt => persist_checkpoint(page, attempt, emit))
        .unwrap_or(@cmd.none)
      ({ page, sync, }, @cmd.batch([page_command, next_command]))
    }
    message => {
      let (page, command) = update_page(
        model.page,
        message,
        emit,
        text_area,
        preview_engine,
      )
      match message {
        Opened(_) => {
          let (sync, lookup_id) = model.sync.begin_lookup()
          let account_command = @account_http.resolve(
            emit.map(result => Sync(AccountResolved(lookup_id, result))),
          )
          ({ page, sync, }, @cmd.batch([command, account_command]))
        }
        _ => ({ ..model, page, }, command)
      }
    }
  }
}

///|
fn reduce_documents_feedback(
  model : Page,
  feedback : @documents.Feedback,
  emit : @rabbita.Emit[Msg],
  text_area : @text_area.TextArea,
  preview_engine : @preview.PreviewEngine,
) -> (Page, @rabbita.Cmd) {
  let event = @documents.Msg::FeedbackReceived(feedback)
  match model {
    Editing(editing) => {
      let (editing, command) = reduce_documents(editing, event, emit)
      reconcile_active(editing, emit, text_area, preview_engine, command)
    }
    PreparingNew(preparing) => {
      let (documents, effects) = preparing.documents.reduce(event)
      (
        PreparingNew({ ..preparing, documents, }),
        run_effects(documents, effects, emit),
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
) -> (Page, @rabbita.Cmd) {
  let active_id = editing.activation.key
  if editing.documents.text(active_id) is Some(_) {
    (Editing(editing), prior)
  } else {
    match editing.documents.fallback_document(active_id) {
      Some(document_id) =>
        match activation_target(editing.documents, document_id) {
          None => (Editing(editing), prior)
          Some(target) => {
            let (editing, command) = editing.activate(
              target, emit, text_area, preview_engine,
            )
            (Editing(editing), @cmd.batch([prior, command]))
          }
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
              emit.map(result => EmptyCreateCompleted(request_id, result)),
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
    DocumentIdentityUnavailable => StorageUnavailable
  }
}
