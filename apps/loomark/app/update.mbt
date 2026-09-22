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
fn EditingState::deletion_blocks_document_changes(self : Self) -> Bool {
  let key = self.activation.key
  let persistence_blocks = match self.documents.delete_status(key) {
    Some(NotDeletable)
    | Some(Deletable)
    | Some(DeleteFailed(_))
    | Some(DeletePersistenceFailed(_))
    | None => false
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
  !(self.creation is Creating(_)) &&
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
    Some(NotDeletable)
    | Some(Deletable)
    | Some(DeleteFailed(_))
    | Some(DeletePersistenceFailed(_)) => true
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
fn run_action(
  documents : @documents.State,
  action : @documents.Action,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Cmd {
  match action {
    @documents.Action::ArmMaximum(id) =>
      @cmd.delay(
        emit(DocumentsLifecycle(@documents.Feedback::MaximumElapsed(id))),
        AUTOSAVE_MAXIMUM_MS,
      )
    @documents.Action::PersistSource(operation) =>
      @source_repository.save(
        documents.snapshot(),
        operation.document,
        emit.map(result => {
          DocumentsLifecycle(
            @documents.Feedback::SaveCompleted(operation, result),
          )
        }),
      )
    @documents.Action::StoreReplica(_)
    | @documents.Action::SaveReplica(_)
    | @documents.Action::DeleteReplica(_)
    | @documents.Action::RetryReplica(_, _) =>
      abort("Replica actions must be consumed synchronously by the root")
    @documents.Action::DeleteSource(operation) =>
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
fn run_actions(
  documents : @documents.State,
  actions : Array[@documents.Action],
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Cmd {
  @cmd.batch(actions.map(action => run_action(documents, action, emit)))
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
fn activate_open(
  model : Model,
  command : @rabbita.Cmd,
  emit : @rabbita.Emit[Msg],
  text_area : @text_area.TextArea,
  preview_engine : @preview.PreviewEngine,
) -> (Model, @rabbita.Cmd) {
  guard model.page is Editing(editing) &&
    editing.can_activate() &&
    model.page.saved_documents() is Some(saved) else {
    return (model, command)
  }
  let (replication, opened) = model.replication.take_open(saved)
  guard opened is Some(opened) else { return (model, command) }
  let replica = opened.replica()
  let opened = match editing.documents.open_replica(replica) {
    @documents.RemoteOpen::Opened(opened) => opened
    Superseded => return ({ ..model, replication, }, command)
  }
  let documents = opened.documents()
  let target : ActivationTarget = {
    key: opened.key(),
    document: opened.document(),
    resume_hint: None,
  }
  let (editing, activation_command) = editing.activate(
    target, emit, text_area, preview_engine,
  )
  (
    { page: Editing({ ..editing, documents, }), replication, },
    @cmd.batch([command, activation_command]),
  )
}

///|
fn reduce_documents(
  editing : EditingState,
  event : @documents.Msg,
  emit : @rabbita.Emit[Msg],
) -> (EditingState, @rabbita.Cmd) {
  let (documents, actions) = editing.documents.reduce(event)
  ({ ..editing, documents, }, run_actions(documents, actions, emit))
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
      } else if editing.creation is Creating(_) ||
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
            emit(
              TextChanged(
                owner.generation,
                @text_change.TextChange::ReplaceAll(text),
              ),
            ),
          ]),
        )
      }
    (Editing(editing), TextChanged(generation, change)) =>
      if generation != editing.activation.generation {
        (Editing(editing), @cmd.none)
      } else if editing.creation is Creating(_) ||
        editing.deletion_blocks_document_changes() {
        (
          Editing(editing),
          text_area.initialize(
            editing.documents.text(editing.activation.key).unwrap_or(""),
          ),
        )
      } else {
        let key = editing.activation.key
        match change.apply(editing.documents.text(key).unwrap_or("")) {
          None =>
            (
              Editing(editing),
              text_area.value(text => {
                emit(
                  TextChanged(
                    generation,
                    @text_change.TextChange::ReplaceAll(text),
                  ),
                )
              }),
            )
          Some(text) if editing.documents.text(key) == Some(text) =>
            (Editing(editing), @cmd.none)
          Some(text) => {
            let (editing, command) = reduce_documents(
              editing,
              @documents.Msg::TextChanged(key, text),
              emit,
            )
            if editing.documents.text(key) != Some(text) {
              (
                Editing(editing),
                text_area.initialize(editing.documents.text(key).unwrap_or("")),
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
    (Editing(editing), CompositionStarted(generation)) =>
      if generation != editing.activation.generation ||
        editing.creation is Creating(_) ||
        editing.deletion_blocks_document_changes() {
        (Editing(editing), @cmd.none)
      } else {
        let (editing, command) = reduce_documents(
          editing,
          @documents.Msg::CompositionStarted(editing.activation.key),
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
            @browser.read(file, emit.map(result => ImportReadCompleted(result))),
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
      (Editing(editing), @browser.download(filename, text))
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
        let generation = editing.activation.generation
        (
          Editing({ ..editing, creation: Creating(generation), }),
          @source_repository.create(
            editing.documents.snapshot(),
            emit.map(result => CreateCompleted(generation, result)),
          ),
        )
      }
    (Editing(editing), CreateCompleted(generation, Created(document_id))) =>
      if !(editing.creation is Creating(current) && current == generation) {
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
    (Editing(editing), CreateCompleted(generation, CreateFailed(failure))) =>
      if editing.creation is Creating(current) && current == generation {
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
      if editing.creation is Creating(_) ||
        editing.deletion != NoDeletion ||
        editing.documents.text(document_id) is None {
        (Editing(editing), @cmd.none)
      } else {
        match editing.documents.delete_status(document_id) {
          Some(Deletable)
          | Some(DeleteFailed(_))
          | Some(DeletePersistenceFailed(_)) =>
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
fn Page::documents_state(self : Self) -> @documents.State? {
  match self {
    Editing(editing) => Some(editing.documents)
    PreparingNew(preparing) => Some(preparing.documents)
    Loading(_) | Recovery(_, _) => None
  }
}

///|
fn Page::begin_fork(
  self : Self,
  write : @source_repository.ReplicaWrite,
) -> Page? {
  guard write is @source_repository.ReplicaWrite::Fork(replica, recovery) else {
    return None
  }
  match self {
    Editing(editing) => {
      let documents = editing.documents.begin_fork(write) catch {
        _ => return None
      }
      let original = @documents.Key::replica(
        replica.account(),
        replica.document_id(),
      )
      let activation = if editing.activation.key == original {
        { ..editing.activation, key: @documents.Key::source(recovery.id()), }
      } else {
        editing.activation
      }
      Some(Editing({ ..editing, documents, activation, }))
    }
    PreparingNew(preparing) => {
      let documents = preparing.documents.begin_fork(write) catch {
        _ => return None
      }
      Some(PreparingNew({ ..preparing, documents, }))
    }
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
fn persist_replica(
  saved : @source_repository.SavedDocuments,
  attempt : @replica_persistence.Attempt,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Cmd {
  @source_repository.persist_replica_write(
    saved,
    attempt.write(),
    emit.map(result => Sync(ReplicaWriteCompleted(attempt, result))),
  )
}

///|
fn submit_replica(
  model : Model,
  write : @source_repository.ReplicaWrite,
  emit : @rabbita.Emit[Msg],
) -> (Model, @rabbita.Cmd) {
  guard model.page.saved_documents() is Some(saved) else {
    return (model, @cmd.none)
  }
  let (replication, effect) = model.replication.submit(write)
  let model = { ..model, replication, }
  (
    model,
    effect
    .map(value => run_replication_effect(saved, value, emit))
    .unwrap_or(@cmd.none),
  )
}

///|
/// Apply child actions before returning from the current root update. Only
/// browser work becomes a Cmd; Documents-to-Replication handoffs stay atomic.
fn apply_document_actions(
  model : Model,
  actions : Array[@documents.Action],
  emit : @rabbita.Emit[Msg],
) -> (Model, @rabbita.Cmd) {
  let (model, commands) = actions.fold(init=(model, []), (state, action) => {
    let (model, commands) = state
    match action {
      @documents.Action::SaveReplica(edit) => {
        let durable = edit.durable()
        let base = model.replication.editing_base(durable)
        let (sync, write) = model.sync().save(base, edit.document().text())
        let model = model.with_sync(sync)
        match write {
          Some(write) => {
            let (model, command) = submit_replica(model, write, emit)
            (model, commands + [command])
          }
          None => (model, commands)
        }
      }
      @documents.Action::DeleteReplica(edit) => {
        let durable = edit.durable()
        let base = model.replication.editing_base(durable)
        let (sync, write) = model.sync().delete(base, edit.document().text())
        let (model, command) = submit_replica(
          model.with_sync(sync),
          write,
          emit,
        )
        (model, commands + [command])
      }
      @documents.Action::StoreReplica(write) => {
        let (model, command) = submit_replica(model, write, emit)
        (model, commands + [command])
      }
      @documents.Action::RetryReplica(account, document_id) => {
        let saved = match model.page.saved_documents() {
          Some(saved) => saved
          None => return (model, commands)
        }
        let (replication, effect) = model.replication.retry_document(
          account, document_id,
        )
        let command = effect
          .map(value => run_replication_effect(saved, value, emit))
          .unwrap_or(@cmd.none)
        ({ ..model, replication, }, commands + [command])
      }
      ArmMaximum(_) | PersistSource(_) | DeleteSource(_) => {
        let documents = match model.page.documents_state() {
          Some(documents) => documents
          None => abort("Document actions require an open repository")
        }
        (model, commands + [run_action(documents, action, emit)])
      }
    }
  })
  (model, @cmd.batch(commands))
}

///|
fn submit_sync_replica(
  model : Model,
  sync : @sync.State,
  write : @source_repository.ReplicaWrite?,
  emit : @rabbita.Emit[Msg],
) -> (Model, @rabbita.Cmd) {
  let model = model.with_sync(sync)
  match write {
    Some(write) => submit_replica(model, write, emit)
    None => (model, @cmd.none)
  }
}

///|
fn run_sync_action(
  action : @sync.Action,
  saved : @source_repository.SavedDocuments,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Cmd {
  match action {
    CreateOperation(plan, account, document_id) =>
      @source_repository.operation_id(
        emit.map(result => {
          Sync(OperationPrepared(plan, account, document_id, result))
        }),
      )
    Deliver(effect, account, document_id, operation) =>
      @document_http.deliver(
        account,
        document_id,
        operation,
        emit.map(result => {
          Sync(
            DeliveryCompleted(
              effect,
              account,
              document_id,
              operation.operation_id(),
              result,
            ),
          )
        }),
      )
    GetRemote(effect, account, document_id, read) =>
      @document_http.get(
        account,
        document_id,
        emit.map(result => {
          Sync(RemoteCompleted(effect, account, document_id, read, result))
        }),
      )
    CreateRecovery(effect, account, document_id) =>
      @source_repository.create(
        saved,
        emit.map(result => {
          Sync(RecoveryCreated(effect, account, document_id, result))
        }),
      )
  }
}

///|
fn run_replication_effect(
  saved : @source_repository.SavedDocuments,
  effect : @replication.Effect,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Cmd {
  match effect {
    Persist(attempt) => persist_replica(saved, attempt, emit)
    Network(action) => run_sync_action(action, saved, emit)
  }
}

///|
fn run_replication_effects(
  saved : @source_repository.SavedDocuments,
  effects : Array[@replication.Effect],
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Cmd {
  @cmd.batch(effects.map(effect => run_replication_effect(saved, effect, emit)))
}

///|
fn discover(
  sync : @sync.State,
  account : @source_repository.AccountId,
  emit : @rabbita.Emit[Msg],
) -> (@sync.State, @rabbita.Cmd) {
  let (sync, discovery) = sync.begin_discovery()
  match discovery {
    Some(id) =>
      (
        sync,
        @document_http.discover(
          account,
          emit.map(result => Sync(DiscoveryCompleted(account, id, result))),
        ),
      )
    None => (sync, @cmd.none)
  }
}

///|
fn settle_replica(
  model : Model,
  replica : @source_repository.DocumentReplica,
  emit : @rabbita.Emit[Msg],
) -> (Model, @rabbita.Cmd) {
  guard model.page.saved_documents() is Some(saved) else {
    return (model, @cmd.none)
  }
  let (replication, effect) = model.replication.settle_replica(replica)
  let model = { ..model, replication, }
  (
    model,
    effect
    .map(value => run_replication_effect(saved, value, emit))
    .unwrap_or(@cmd.none),
  )
}

///|
fn resume_account(
  model : Model,
  account : @source_repository.AccountId,
  emit : @rabbita.Emit[Msg],
) -> (Model, @rabbita.Cmd) {
  guard model.page.saved_documents() is Some(saved) else {
    return (model, @cmd.none)
  }
  let (replication, effects) = model.replication.resume_account(saved, account)
  let model = { ..model, replication, }
  (model, run_replication_effects(saved, effects, emit))
}

///|
fn settle_account(
  model : Model,
  account : @source_repository.AccountId,
  emit : @rabbita.Emit[Msg],
) -> (Model, @rabbita.Cmd) {
  guard model.page.saved_documents() is Some(saved) else {
    return (model, @cmd.none)
  }
  let (replication, effects) = model.replication.settle_account(saved, account)
  let model = { ..model, replication, }
  (model, run_replication_effects(saved, effects, emit))
}

///|
fn resolve_changed_account(
  sync : @sync.State,
  account : @source_repository.AccountId,
  emit : @rabbita.Emit[Msg],
) -> (@sync.State, @rabbita.Cmd) {
  guard sync.session() is @sync.Session::Current(current, _) &&
    current == account else {
    return (sync, @cmd.none)
  }
  let (sync, lookup_id) = sync.begin_lookup()
  (
    sync,
    @account_http.resolve(
      emit.map(value => Sync(AccountResolved(lookup_id, value))),
    ),
  )
}

///|
fn initial_state(
  emit : @rabbita.Emit[Msg],
  compact : Bool,
) -> (Model, @rabbita.Cmd) {
  let (page, page_command) = initial_page(emit, compact)
  ({ page, replication: @replication.State(), }, page_command)
}

///|
fn update_documents(
  model : Model,
  event : @documents.Msg,
  emit : @rabbita.Emit[Msg],
  text_area : @text_area.TextArea,
  preview_engine : @preview.PreviewEngine,
) -> (Model, @rabbita.Cmd) {
  let (page, actions, page_command) = reduce_page_documents(
    model.page,
    event,
    emit,
    text_area,
    preview_engine,
  )
  let (model, action_command) = apply_document_actions(
    model.with_page(page),
    actions,
    emit,
  )
  (model, @cmd.batch([page_command, action_command]))
}

///|
fn reduce(
  model : Model,
  msg : Msg,
  emit : @rabbita.Emit[Msg],
  text_area : @text_area.TextArea,
  preview_engine : @preview.PreviewEngine,
) -> (Model, @rabbita.Cmd) {
  match msg {
    ApplyPendingEdit(document_id, revision) =>
      update_documents(
        model,
        @documents.Msg::ApplyPendingEdit(document_id, revision),
        emit,
        text_area,
        preview_engine,
      )
    DocumentsLifecycle(feedback) =>
      update_documents(
        model,
        @documents.Msg::FeedbackReceived(feedback),
        emit,
        text_area,
        preview_engine,
      )
    CompositionEnded(generation) =>
      match model.page {
        Editing(editing) if generation == editing.activation.generation =>
          update_documents(
            model,
            @documents.Msg::CompositionEnded(editing.activation.key),
            emit,
            text_area,
            preview_engine,
          )
        _ => (model, @cmd.none)
      }
    DeleteConfirmed(document_id) =>
      match model.page {
        Editing(editing) if editing.deletion == DeleteConfirmation(document_id) =>
          update_documents(
            { ..model, page: Editing({ ..editing, deletion: NoDeletion, }), },
            @documents.Msg::DeleteConfirmed(document_id),
            emit,
            text_area,
            preview_engine,
          )
        _ => (model, @cmd.none)
      }
    RetryDelete(document_id) =>
      update_documents(
        model,
        @documents.Msg::RetryDelete(document_id),
        emit,
        text_area,
        preview_engine,
      )
    VisibilityChanged(true) =>
      match model.page {
        Editing(editing) =>
          update_documents(
            model,
            @documents.Msg::VisibilityFlush(editing.activation.key),
            emit,
            text_area,
            preview_engine,
          )
        _ => (model, @cmd.none)
      }
    RetrySave =>
      match model.page {
        Editing(editing) =>
          update_documents(
            model,
            @documents.Msg::RetrySave(editing.activation.key),
            emit,
            text_area,
            preview_engine,
          )
        _ => (model, @cmd.none)
      }
    RetryAccount => {
      let (sync, lookup_id) = model.sync().begin_lookup()
      (
        model.with_sync(sync),
        @account_http.resolve(
          emit.map(result => Sync(AccountResolved(lookup_id, result))),
        ),
      )
    }
    StartSync(action) => {
      guard model.sync().session() is @sync.Session::Current(current, _) &&
        current == action.account() &&
        model.page is Editing(editing) else {
        return (model, @cmd.none)
      }
      let (documents, effects) = editing.documents.start_sync(action) catch {
        _ => return (model, @cmd.none)
      }
      let editing = { ..editing, documents, }
      apply_document_actions(
        { ..model, page: Editing(editing), },
        effects,
        emit,
      )
    }
    AcceptRemote(action) => {
      guard model.page is Editing(editing) &&
        editing.activation.key is @documents.Key::Replica(account, document_id) &&
        model.sync().session() is @sync.Session::Current(current, _) &&
        current == account &&
        model.replication.status(account, document_id)
        is @replica_persistence.Status::Current &&
        editing.documents.snapshot().replica(account, document_id)
        is Some(replica) else {
        return (model, @cmd.none)
      }
      let accepted = Some(editing.documents.accept_remote(replica, action)) catch {
        _ => None
      }
      guard accepted is Some(accepted) else { return (model, @cmd.none) }
      match accepted {
        @documents.RemoteAcceptance::Opened(documents, document, write) => {
          let target : ActivationTarget = {
            key: editing.activation.key,
            document,
            resume_hint: None,
          }
          let (editing, activate) = { ..editing, documents, }.activate(
            target, emit, text_area, preview_engine,
          )
          let (model, persist) = submit_replica(
            { ..model, page: Editing(editing), },
            write,
            emit,
          )
          (model, @cmd.batch([activate, persist]))
        }
        Removed(documents, write) => {
          let (page, activate) = reconcile_active(
            { ..editing, documents, },
            emit,
            text_area,
            preview_engine,
            @cmd.none,
          )
          let (model, persist) = submit_replica({ ..model, page, }, write, emit)
          (model, @cmd.batch([activate, persist]))
        }
      }
    }
    RetrySync(action) =>
      match action {
        RetryPersistence(retry) => {
          guard model.page.saved_documents() is Some(saved) else {
            return (model, @cmd.none)
          }
          let result = Some(model.replication.retry(retry)) catch { _ => None }
          guard result is Some((replication, effect)) else {
            return (model, @cmd.none)
          }
          let model = { ..model, replication, }
          (model, run_replication_effect(saved, effect, emit))
        }
        RetryNetwork(action) => {
          let replica = action.replica()
          let account = replica.account()
          let document_id = replica.document_id()
          guard model.page.saved_documents() is Some(saved) &&
            saved.replica(account, document_id) == Some(replica) &&
            model.sync().progress(replica) is @sync.Progress::Retryable(current) &&
            current == action else {
            return (model, @cmd.none)
          }
          settle_replica(model, replica, emit)
        }
      }
    Sync(AccountResolved(lookup_id, result)) => {
      let (sync, selection) = model.sync().resolved(lookup_id, result)
      let (page, sync, command) = match selection {
        Some(@sync.AccountSelection::AccountSelected(account)) => {
          let page = model.page.project_account(account)
          let model = model.with_sync(sync)
          let model = { ..model, page, }
          let (model, schedule) = resume_account(model, account, emit)
          let (sync, discovery) = discover(model.sync(), account, emit)
          return (model.with_sync(sync), @cmd.batch([schedule, discovery]))
        }
        Some(@sync.AccountSelection::NoAccountSelected) =>
          (model.page.hide_accounts(), sync, @cmd.none)
        None => (model.page, sync, @cmd.none)
      }
      (model.with_sync(sync).with_page(page), command)
    }
    Sync(DiscoveryCompleted(account, id, result)) => {
      let entries = match result {
        @document_http.DiscoveryResult::Discovered(entries) => Some(entries)
        AccountChanged | Unavailable => None
      }
      let (sync, accepted) = model.sync().discovered(account, id, entries)
      guard accepted else { return (model, @cmd.none) }
      match result {
        @document_http.DiscoveryResult::Discovered(_) =>
          settle_account(model.with_sync(sync), account, emit)
        AccountChanged => {
          let (sync, command) = resolve_changed_account(sync, account, emit)
          (model.with_sync(sync), command)
        }
        Unavailable => (model.with_sync(sync), @cmd.none)
      }
    }
    Sync(ReplicaWriteCompleted(attempt, result)) => {
      guard model.page.saved_documents() is Some(saved) else {
        return (model, @cmd.none)
      }
      let transition = Some(model.replication.complete(attempt, result)) catch {
        _ => None
      }
      guard transition is Some((replication, completion)) else {
        return (model, @cmd.none)
      }
      let active_write = attempt.write()
      let (completed, feedback_result, next, current) = match completion {
        @replica_persistence.Completion::Current(write) =>
          (write, Ok(()), None, true)
        Superseded(write, next) => (write, Ok(()), Some(next), false)
        Retryable(retained, _, failure) => (retained, Err(failure), None, false)
        Failed(write, failure) => (write, Err(failure), None, false)
      }
      let replica = completed.replica()
      let feedback = if active_write
        is @source_repository.ReplicaWrite::PromoteSource(_) {
        Some(
          @documents.Feedback::PromotionCompleted(completed, feedback_result),
        )
      } else {
        match feedback_result {
          Ok(_) =>
            Some(
              if current {
                @documents.Feedback::ReplicaSettled(
                  completed,
                  match model.page {
                    Editing(editing) => Some(editing.activation.key)
                    Loading(_) | PreparingNew(_) | Recovery(_, _) => None
                  },
                )
              } else {
                @documents.Feedback::ReplicaAdvanced(completed)
              },
            )
          Err(failure) =>
            if completed is @source_repository.ReplicaWrite::Remove(_) ||
              completed.replica().is_deleting() ||
              completed.replica().is_deleted() {
              Some(
                @documents.Feedback::ReplicaDeletionFailed(completed, failure),
              )
            } else {
              None
            }
        }
      }
      let (page, page_actions, page_command) = match feedback {
        Some(feedback) =>
          reduce_page_documents(
            model.page,
            @documents.Msg::FeedbackReceived(feedback),
            emit,
            text_area,
            preview_engine,
          )
        None => (model.page, [], @cmd.none)
      }
      let next_command = next
        .map(attempt => persist_replica(saved, attempt, emit))
        .unwrap_or(@cmd.none)
      let (model, page_actions_command) = apply_document_actions(
        { page, replication, },
        page_actions,
        emit,
      )
      let (model, sync_command) = if current {
        match model.page.saved_documents() {
          Some(saved) =>
            match saved.replica(replica.account(), replica.document_id()) {
              Some(durable) => settle_replica(model, durable, emit)
              None => (model, @cmd.none)
            }
          None => (model, @cmd.none)
        }
      } else {
        (model, @cmd.none)
      }
      (
        model,
        @cmd.batch([
          page_command, page_actions_command, next_command, sync_command,
        ]),
      )
    }
    Sync(OperationPrepared(plan, account, document_id, result)) => {
      guard model.page.saved_documents() is Some(saved) &&
        saved.replica(account, document_id) is Some(durable) &&
        model.replication.status(account, document_id)
        is @replica_persistence.Status::Current else {
        return (
          model.with_sync(
            model.sync().planning_failed(plan, account, document_id),
          ),
          @cmd.none,
        )
      }
      match result {
        None =>
          (
            model.with_sync(
              model.sync().planning_failed(plan, account, document_id),
            ),
            @cmd.none,
          )
        Some(operation_id) => {
          let transition = Some(
            model.sync().prepared(plan, durable, operation_id),
          ) catch {
            _ => None
          }
          guard transition is Some((sync, attempt)) else {
            return (
              model.with_sync(
                model.sync().planning_failed(plan, account, document_id),
              ),
              @cmd.none,
            )
          }
          submit_sync_replica(model, sync, attempt, emit)
        }
      }
    }
    Sync(DeliveryCompleted(effect, account, document_id, operation_id, result)) => {
      guard model.page.saved_documents() is Some(saved) &&
        saved.replica(account, document_id) is Some(durable) else {
        return (model, @cmd.none)
      }
      match result {
        @document_http.DeliveryResult::Acknowledged(revision) => {
          let base = model.replication.protocol_base(durable)
          let transition = Some(
            model.sync().acknowledged(base, effect, operation_id, revision),
          ) catch {
            // A delayed response cannot complete a different durable operation.
            _ => None
          }
          guard transition is Some((sync, attempt)) else {
            return (model, @cmd.none)
          }
          submit_sync_replica(model, sync, attempt, emit)
        }
        RevisionConflict => {
          let base = model.replication.protocol_base(durable)
          let sync = model.sync().revision_conflict(base, effect, operation_id) catch {
              _ => return (model, @cmd.none)
            }
          settle_replica(model.with_sync(sync), durable, emit)
        }
        DocumentTooLarge => {
          let base = model.replication.protocol_base(durable)
          let transition = Some(
            model.sync().delivery_too_large(base, effect, operation_id),
          ) catch {
            _ => None
          }
          guard transition is Some((sync, attempt)) else {
            return (model, @cmd.none)
          }
          submit_sync_replica(model, sync, attempt, emit)
        }
        OperationRejected => {
          let base = model.replication.protocol_base(durable)
          let transition = Some(
            model.sync().operation_rejected(base, effect, operation_id),
          ) catch {
            _ => None
          }
          guard transition is Some((sync, attempt)) else {
            return (model, @cmd.none)
          }
          submit_sync_replica(model, sync, attempt, emit)
        }
        AccountChanged | Unavailable => {
          let base = model.replication.protocol_base(durable)
          let sync = model.sync().delivery_failed(base, effect, operation_id) catch {
              _ => return (model, @cmd.none)
            }
          if result is AccountChanged {
            let (sync, command) = resolve_changed_account(sync, account, emit)
            (model.with_sync(sync), command)
          } else {
            (model.with_sync(sync), @cmd.none)
          }
        }
      }
    }
    Sync(RemoteCompleted(effect, account, document_id, read, result)) => {
      if read is @sync.RemoteRead::Open(intent, expected) {
        let durable = match model.page.saved_documents() {
          Some(saved) => saved.replica(account, document_id)
          None => None
        }
        let replica = match durable {
          Some(value) => Some(model.replication.protocol_base(value))
          None => model.replication.pending(account, document_id)
        }
        let transition = match result {
          @document_http.RemoteResult::Found(remote) =>
            Some(
              model
              .sync()
              .opened(
                effect, account, document_id, intent, expected, replica, remote,
              ),
            ) catch {
              _ => None
            }
          AccountChanged | Unavailable =>
            Some(
              (
                model
                .sync()
                .open_failed(effect, account, document_id, intent, expected),
                @source_repository.OpenOutcome::Unavailable,
              ),
            ) catch {
              _ => None
            }
        }
        guard transition is Some((sync, outcome)) else {
          return (model, @cmd.none)
        }
        let write = match outcome {
          @source_repository.OpenOutcome::PersistAndOpen(write)
          | PersistOnly(write) => Some(write)
          Ready | Unavailable => None
        }
        let (model, store) = submit_sync_replica(model, sync, write, emit)
        if result is @document_http.RemoteResult::AccountChanged {
          let (sync, lookup) = resolve_changed_account(
            model.sync(),
            account,
            emit,
          )
          return (model.with_sync(sync), @cmd.batch([store, lookup]))
        }
        return (model, store)
      }
      guard model.page.saved_documents() is Some(saved) &&
        saved.replica(account, document_id) is Some(durable) else {
        return (model, @cmd.none)
      }
      match result {
        @document_http.RemoteResult::Found(remote) => {
          let base = model.replication.protocol_base(durable)
          let transition = Some(
            model.sync().received(base, effect, read, remote),
          ) catch {
            _ => None
          }
          guard transition is Some((sync, write)) else {
            return (model, @cmd.none)
          }
          let (model, store) = submit_sync_replica(model, sync, write, emit)
          let (model, advance) = if write is None {
            settle_replica(model, durable, emit)
          } else {
            (model, @cmd.none)
          }
          (model, @cmd.batch([store, advance]))
        }
        AccountChanged | Unavailable => {
          let base = model.replication.protocol_base(durable)
          let sync = model.sync().remote_failed(base, effect, read) catch {
              _ => return (model, @cmd.none)
            }
          if result is AccountChanged {
            let (sync, command) = resolve_changed_account(sync, account, emit)
            (model.with_sync(sync), command)
          } else {
            (model.with_sync(sync), @cmd.none)
          }
        }
      }
    }
    Sync(RecoveryCreated(effect, account, document_id, result)) => {
      guard model.page.saved_documents() is Some(saved) &&
        saved.replica(account, document_id) is Some(durable) else {
        return (model, @cmd.none)
      }
      guard result is @source_repository.CreateResult::Created(recovery_id) else {
        return (
          model.with_sync(
            model.sync().recovery_failed(account, document_id, effect),
          ),
          @cmd.none,
        )
      }
      let base = model.replication.protocol_base(durable)
      let transition = Some(model.sync().recover(base, effect, recovery_id)) catch {
        _ => None
      }
      guard transition is Some((sync, write)) else { return (model, @cmd.none) }
      let page = match write {
        Some(fork) =>
          match model.page.begin_fork(fork) {
            Some(page) => page
            None => return (model, @cmd.none)
          }
        None => model.page
      }
      submit_sync_replica({ ..model, page, }, sync, write, emit)
    }
    DocumentSelected(@documents.Key::Replica(account, document_id)) if model.page
      is Editing(editing) &&
      editing.documents.text(@documents.Key::replica(account, document_id))
      is None &&
      model.sync().session() is @sync.Session::Current(current, _) &&
      current == account => {
      guard model.sync().remote_entry(document_id) is Some(entry) &&
        entry is @source_repository.RemoteEntry::Present(_, _, _) &&
        editing.can_activate() &&
        model.page.saved_documents() is Some(saved) else {
        return (model, @cmd.none)
      }
      let durable = saved.replica(account, document_id)
      let (replication, effect) = model.replication.select(document_id, durable)
      let command = effect
        .map(value => run_replication_effect(saved, value, emit))
        .unwrap_or(@cmd.none)
      ({ ..model, replication, }, command)
    }
    message => {
      let sync = match message {
        DocumentSelected(_) | CreateRequested | ImportFilesSelected(_) =>
          model.sync().cancel_open()
        _ => model.sync()
      }
      let (page, command) = update_page(
        model.page,
        message,
        emit,
        text_area,
        preview_engine,
      )
      match message {
        Opened(_) => {
          let (sync, lookup_id) = sync.begin_lookup()
          let account_command = @account_http.resolve(
            emit.map(result => Sync(AccountResolved(lookup_id, result))),
          )
          (
            model.with_sync(sync).with_page(page),
            @cmd.batch([command, account_command]),
          )
        }
        VisibilityChanged(false) => {
          let (sync, lookup_id) = sync.begin_lookup()
          let account_command = @account_http.resolve(
            emit.map(result => Sync(AccountResolved(lookup_id, result))),
          )
          (
            model.with_sync(sync).with_page(page),
            @cmd.batch([command, account_command]),
          )
        }
        _ => (model.with_sync(sync).with_page(page), command)
      }
    }
  }
}

///|
fn update(
  model : Model,
  msg : Msg,
  emit : @rabbita.Emit[Msg],
  text_area : @text_area.TextArea,
  preview_engine : @preview.PreviewEngine,
) -> (Model, @rabbita.Cmd) {
  let (model, command) = reduce(model, msg, emit, text_area, preview_engine)
  activate_open(model, command, emit, text_area, preview_engine)
}

///|
fn reduce_page_documents(
  model : Page,
  event : @documents.Msg,
  emit : @rabbita.Emit[Msg],
  text_area : @text_area.TextArea,
  preview_engine : @preview.PreviewEngine,
) -> (Page, Array[@documents.Action], @rabbita.Cmd) {
  match model {
    Editing(editing) => {
      let active = editing.activation
      let (documents, actions) = editing.documents.reduce(event)
      let editing = { ..editing, documents, }
      let editing = match event {
        @documents.Msg::FeedbackReceived(
          @documents.Feedback::PromotionCompleted(write, Ok(_))
        ) if active.key == @documents.Key::source(write.replica().document_id()) => {
          let replica = write.replica()
          let key = @documents.Key::replica(
            replica.account(),
            replica.document_id(),
          )
          if editing.documents.text(active.key) is None &&
            editing.documents.text(key) is Some(_) {
            { ..editing, activation: { ..active, key, }, }
          } else {
            editing
          }
        }
        _ => editing
      }
      let (page, command) = reconcile_active(
        editing, emit, text_area, preview_engine, @cmd.none,
      )
      (page, actions, command)
    }
    PreparingNew(preparing) => {
      let (documents, actions) = preparing.documents.reduce(event)
      (PreparingNew({ ..preparing, documents, }), actions, @cmd.none)
    }
    Loading(_) | Recovery(_, _) => (model, [], @cmd.none)
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
