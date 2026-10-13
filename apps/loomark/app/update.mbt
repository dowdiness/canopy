///|
const AUTOSAVE_MAXIMUM_MS : Int = 2000

///|
const COMPACT_MAX_WIDTH : Double = 720.0

///|
fn compact_viewport(width : Double) -> Bool {
  width <= COMPACT_MAX_WIDTH
}

///|
const EDITOR_TEXT_ID : String = "loomark-text"

///|
fn editor_focus_id(mode : EditorMode) -> String {
  match mode {
    Text | Split => EDITOR_TEXT_ID
    Preview => mode_dom_id(Preview)
  }
}

///|
fn editor_mode(mode : EditorMode) -> @editor.Mode {
  match mode {
    Text => @editor.Text
    Preview => @editor.Preview
    Split => @editor.Split
  }
}

///|
fn decode_import(bytes : Bytes) -> String? {
  Some(
    @utf8.decode(bytes.exact_view(), ignore_bom=true)
    .replace_all(old="\r\n", new="\n")
    .replace_all(old="\r", new="\n"),
  ) catch {
    _ => None
  }
}

///|
fn export_payload(editing : EditingDocument) -> (String, String) {
  let text = editing.documents.text(editing.activation.key).unwrap_or("")
  let name = @document_lead.derive_name(text).text()
  let filename = if !name.is_empty() { name + ".md" } else { "untitled.md" }
  (filename, text)
}

///|
fn creation_in_progress(creation : Creation?) -> Bool {
  match creation {
    Some({ status: InProgress, .. }) => true
    _ => false
  }
}

///|
fn creation_request_is_current(creation : Creation?, request_id : Int) -> Bool {
  match creation {
    Some(current) => current.request_id == request_id && current.status is InProgress
    None => false
  }
}

///|
fn creation_failure(error : @source_repository.CreateFailure) -> String {
  match error {
    _ => "Document creation failed. Try again."
  }
}

///|
fn EditingDocument::deletion_blocks_document_changes(self : Self) -> Bool {
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
fn EditingDocument::can_activate(self : Self) -> Bool {
  !(creation_in_progress(self.creation)) &&
  !self.documents.is_composing(self.activation.key) &&
  !self.deletion_blocks_document_changes()
}

///|
fn EditingDocument::selectable_activation(
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
  documents : @documents.Model,
  key : @documents.Key,
) -> ActivationTarget? {
  documents
  .document(key)
  .map(document => { key, document, resume_hint: documents.resume_hint(key), })
}

///|
fn EditingDocument::can_select(self : Self, key : @documents.Key) -> Bool {
  self.selectable_activation(key) is Some(_)
}

///|
fn activate_surface(
  activation : Activation,
  text : String,
  mode : EditorMode,
  emit : @rabbita.Emit[Msg],
  editor : @editor.MarkdownEditor,
) -> (@editor.EditorState, @rabbita.Cmd) {
  let (preview, command) = editor.activate(
    activation.generation,
    text,
    editor_mode(mode),
    emit.map(event => PreviewEvent(event)),
  )
  (preview, @cmd.batch([command, focus_after_render(editor_focus_id(mode))]))
}

///|
fn EditingDocument::activate(
  self : Self,
  target : ActivationTarget,
  emit : @rabbita.Emit[Msg],
  editor : @editor.MarkdownEditor,
) -> (EditingDocument, @rabbita.Cmd) {
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
    editor,
  )
  let remember = match target.resume_hint {
    Some(hint) => hint.remember()
    None => @cmd.none
  }
  (
    { ..self, activation, preview, menu_open: false, },
    @cmd.batch([surface, remember]),
  )
}

///|
fn activate_open(
  model : Model,
  command : @rabbita.Cmd,
  emit : @rabbita.Emit[Msg],
  editor : @editor.MarkdownEditor,
) -> (Model, @rabbita.Cmd) {
  guard model.page is Editing(editing) &&
    !model.sign_in.blocks_editing() &&
    editing.can_activate() &&
    model.page.saved_documents() is Some(saved) else {
    return (model, command)
  }
  let (replication, opened, effect) = model.replication.take_selection(saved)
  let command = @cmd.batch([
    command,
    effect
    .map(value => run_replication_effect(saved, value, emit))
    .unwrap_or(@cmd.none),
  ])
  guard opened is Some(opened) else {
    return ({ ..model, replication, }, command)
  }
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
  let (editing, activation_command) = editing.activate(target, emit, editor)
  (
    { ..model, page: Editing({ ..editing, documents, }), replication, },
    @cmd.batch([command, activation_command]),
  )
}

///|
fn install_document_transition(
  editing : EditingDocument,
  transition : @documents.Transition,
  actions : Array[@documents.Action],
) -> EditingDocument {
  for action in transition.effects { actions.push(action) }
  { ..editing, documents: transition.model, lifecycle_error: None, }
}

///|
fn document_update(
  editing : EditingDocument,
  event : @documents.Msg,
  actions : Array[@documents.Action],
) -> (EditingDocument, DocumentUpdateResult) {
  match editing.documents.update(event) {
    Applied(transition) => {
      let next = install_document_transition(editing, transition, actions)
      (next, Updated(transition))
    }
    Superseded => (editing, Obsolete)
  } catch {
    @documents.UpdateError::DocumentMismatch(_) =>
      let text = "Document acknowledgment did not match the current document. The current document was retained."
      ({ ..editing, lifecycle_error: Some(text), }, Fault(text))
    @documents.UpdateError::DocumentAlreadyExists(_) =>
      let text = "This document already exists. Reopen the current document to recover."
      ({ ..editing, lifecycle_error: Some(text), }, Fault(text))
    @documents.UpdateError::InvalidAcknowledgment(_) =>
      let text = "Document storage returned an invalid acknowledgment. The current document was retained."
      ({ ..editing, lifecycle_error: Some(text), }, Fault(text))
  }
}

///|
fn reduce_documents(
  editing : EditingDocument,
  event : @documents.Msg,
  actions : Array[@documents.Action],
) -> EditingDocument {
  document_update(editing, event, actions).0
}

///|
fn edit_document(
  editing : EditingDocument,
  key : @documents.Key,
  text : String,
  actions : Array[@documents.Action],
) -> EditingDocument {
  match editing.documents.edit(key, text) {
    Changed(transition) => install_document_transition(editing, transition, actions)
    SameText => { ..editing, lifecycle_error: None, }
  } catch {
    @documents.EditError::DocumentMissing(_) =>
      { ..editing, lifecycle_error: Some("The document is no longer available. Reopen it to continue."), }
    @documents.EditError::PendingDeletion(_) =>
      { ..editing, lifecycle_error: Some("This document is being deleted and can no longer be edited."), }
  }
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
  editor : @editor.MarkdownEditor,
  actions : Array[@documents.Action],
) -> (Page, @rabbita.Cmd) {
  let (next, command) = match (model, msg) {
    (OpeningNew(opening, creation), RetryOpeningNewCreation) =>
      match creation.status {
        Failed(_) => {
          let request_id = creation.request_id + 1
          let retry = { ..creation, request_id, status: InProgress, }
          (OpeningNew({ ..opening, lifecycle_error: None, }, retry), @source_repository.create(
            opening.documents.snapshot(), emit.map(result => EmptyCreateCompleted(request_id, result)),
          ))
        }
        InProgress | Fault(_) => (model, @cmd.none)
      }
    (Loading(compact), Opened(Ready(saved, initial))) =>
      match initial {
        Some(document) => {
          let documents = @documents.Model(saved)
          let activation = {
            key: @documents.Key::source(document.id()),
            generation: 0,
          }
          let (preview, command) = activate_surface(
            activation,
            document.text(),
            Text,
            emit,
            editor,
          )
          (
            Editing({
              activation,
              documents,
              creation: None,
              deletion: NoDeletion,
              mode: Text,
              menu_open: false,
              compact,
              preview,
              import_failed: false,
              imports_pending: 0,
                    }),
            command,
          )
        }
        None => {
          let documents = @documents.Model(saved)
          let opening : OpeningNewContext = {
            documents, mode: Text, compact, next_activation_generation: 0, lifecycle_error: None,
          }
          let creation : Creation = { request_id: 1, intent: NewDocument, status: InProgress, }
          (OpeningNew(opening, creation), @source_repository.create(
            saved, emit.map(result => EmptyCreateCompleted(1, result)),
          ))
        }
      }
    (Loading(compact), Opened(OpenFailed(failure))) =>
      (Recovery(failure, compact), @cmd.none)
    (OpeningNew(opening, creation), EmptyCreateCompleted(request_id, result)) =>
      if !creation_request_is_current(Some(creation), request_id) {
        (model, @cmd.none)
      } else {
        match result {
          CreateFailed(failure) =>
            (OpeningNew(opening, { ..creation, status: Failed(failure), }), @cmd.none)
          Created(document_id) => {
            let documents = match opening.documents.update(@documents.Msg::New(document_id)) {
              Applied(transition) => transition.model
              Superseded => opening.documents
            } catch {
              _ => opening.documents
            }
            let activation = {
              key: @documents.Key::source(document_id),
              generation: opening.next_activation_generation,
            }
            let (preview, command) = activate_surface(activation, "", opening.mode, emit, editor)
            (Editing({
              activation, documents, creation: None, lifecycle_error: None,
              deletion: NoDeletion, mode: opening.mode, menu_open: false,
              compact: opening.compact, preview, import_failed: false, imports_pending: 0, next_creation_request_id: creation.request_id + 1,
            }), command)
          }
        }
      }
    (Editing(editing), ExampleSelected(owner, text)) =>
      if owner != editing.activation {
        (Editing(editing), @cmd.none)
      } else if !editing.can_activate() {
        (Editing(editing), @cmd.none)
      } else {
        (
          Editing({ ..editing, creation: Some({ request_id: editing.next_creation_request_id, intent: Example(text), status: InProgress, }), next_creation_request_id: editing.next_creation_request_id + 1, }),
          @source_repository.create(
            editing.documents.snapshot(),
            emit.map(result => {
              ExampleCreateCompleted(editing.next_creation_request_id, text, result)
            }),
          ),
        )
      }
    (
      Editing(editing),
      ExampleCreateCompleted(generation, text, Created(document_id)),
    ) =>
      if !(creation_request_is_current(editing.creation, generation)) {
        (Editing(editing), @cmd.none)
      } else {
        let key = @documents.Key::source(document_id)
        let editing = reduce_documents(
          editing,
          @documents.Msg::New(document_id),
          actions,
        )
        let editing = edit_document(editing, key, text, actions)
        match activation_target(editing.documents, key) {
          None => (Editing({ ..editing, creation: None, }), @cmd.none)
          Some(target) => {
            let ready = { ..editing, creation: None, }
            let (next, surface) = ready.activate(target, emit, editor)
            (Editing(next), surface)
          }
        }
      }
    (
      Editing(editing),
      ExampleCreateCompleted(generation, text, CreateFailed(failure)),
    ) =>
      if creation_request_is_current(editing.creation, generation) {
        (
          Editing({ ..editing, creation: Some({ request_id: generation, intent: Example(text), status: Failed(failure), }), }),
          @cmd.none,
        )
      } else {
        (Editing(editing), @cmd.none)
      }
    (Editing(editing), InputChanged(generation, input)) =>
      match editor.admit(input) {
        None => (Editing(editing), @cmd.none)
        Some(change) =>
          update_page(
            Editing(editing),
            TextChanged(generation, change),
            emit,
            editor,
            actions,
          )
      }
    (Editing(editing), TextChanged(generation, change)) =>
      if generation != editing.activation.generation {
        (Editing(editing), @cmd.none)
      } else if creation_in_progress(editing.creation) ||
        editing.deletion_blocks_document_changes() {
        (
          Editing(editing),
          editor.restore(
            editing.documents.text(editing.activation.key).unwrap_or(""),
          ),
        )
      } else {
        let key = editing.activation.key
        match change.apply(editing.documents.text(key).unwrap_or("")) {
          None =>
            (
              Editing(editing),
              editor.restore(editing.documents.text(key).unwrap_or("")),
            )
          Some(text) if editing.documents.text(key) == Some(text) =>
            (Editing(editing), @cmd.none)
          Some(text) => {
            let editing = edit_document(editing, key, text, actions)
            if editing.documents.text(key) != Some(text) {
              (
                Editing(editing),
                editor.restore(editing.documents.text(key).unwrap_or("")),
              )
            } else {
              let (preview, preview_command) = editor.accepted(
                editing.preview,
                editing.activation.generation,
                text,
                change,
                emit.map(event => PreviewEvent(event)),
              )
              (Editing({ ..editing, preview, }), preview_command)
            }
          }
        }
      }
    (Editing(editing), CompositionStarted(generation)) =>
      if generation != editing.activation.generation ||
        creation_in_progress(editing.creation) ||
        editing.deletion_blocks_document_changes() {
        (Editing(editing), @cmd.none)
      } else {
        let editing = reduce_documents(
          editing,
          @documents.Msg::CompositionStarted(editing.activation.key),
          actions,
        )
        (Editing(editing), @cmd.none)
      }
    (Editing(editing), ModeSelected(mode)) => {
      let previous = editing.mode
      let editing = { ..editing, mode, }
      let (preview, command) = editor.mode_changed(
        editing.preview,
        editing.activation.generation,
        editing.documents.text(editing.activation.key).unwrap_or(""),
        editor_mode(previous),
        editor_mode(mode),
        emit.map(event => PreviewEvent(event)),
      )
      (Editing({ ..editing, preview, }), command)
    }
    (Editing(editing), MenuToggled) =>
      (Editing({ ..editing, menu_open: !editing.menu_open, }), @cmd.none)
    (Editing(editing), EscapePressed) =>
      (
        Editing({ ..editing, menu_open: false, }),
        if editing.menu_open {
          focus_after_render("loomark-more-actions")
        } else {
          @cmd.none
        },
      )
    (Editing(editing), ImportFilesSelected(files)) =>
      match files.get(0) {
        None => (Editing(editing), @cmd.none)
        Some(file) =>
          (
            Editing({
              ..editing,
              import_failed: false,
              imports_pending: editing.imports_pending + 1,
            }),
            @browser.read(file, emit.map(result => ImportReadCompleted(result))),
          )
      }
    (Editing(editing), ImportReadCompleted(Err(_))) =>
      (
        Editing({
          ..editing,
          import_failed: true,
          imports_pending: (editing.imports_pending - 1).max(0),
        }),
        @cmd.none,
      )
    (Editing(editing), ImportReadCompleted(Ok(bytes))) =>
      match decode_import(bytes) {
        None =>
          (
            Editing({
              ..editing,
              import_failed: true,
              imports_pending: (editing.imports_pending - 1).max(0),
            }),
            @cmd.none,
          )
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
      (
        Editing({
          ..editing,
          import_failed: true,
          imports_pending: (editing.imports_pending - 1).max(0),
        }),
        @cmd.none,
      )
    (Editing(editing), ImportCreateCompleted(text, Created(document_id))) => {
      let editing = {
        ..editing,
        imports_pending: (editing.imports_pending - 1).max(0),
      }
      let next = reduce_documents(
        editing,
        @documents.Msg::Imported(document_id, text),
        actions,
      )
      // Keep successful imports without replacing the composing textarea.
      // No delayed activation is queued: the user can open it from Documents.
      if next.documents.is_composing(next.activation.key) {
        (Editing({ ..next, import_failed: false, }), @cmd.none)
      } else {
        match
          activation_target(next.documents, @documents.Key::source(document_id)) {
          None => (Editing({ ..editing, import_failed: true, }), @cmd.none)
          Some(target) => {
            let ready = {
              ..next,
              creation: None,
              deletion: NoDeletion,
              import_failed: false,
            }
            let (next, surface) = ready.activate(target, emit, editor)
            (Editing(next), surface)
          }
        }
      }
    }
    (Editing(editing), DismissImportFailure) =>
      (
        Editing({ ..editing, import_failed: false, }),
        focus_after_render(editor_focus_id(editing.mode)),
      )
    (Editing(editing), ExportRequested) => {
      let (filename, text) = export_payload(editing)
      (Editing(editing), @browser.download(filename, text))
    }
    (Editing(editing), PreviewEvent(event)) => {
      let (preview, command) = editor.update(
        editing.preview,
        editing.activation.generation,
        editing.documents.text(editing.activation.key).unwrap_or(""),
        event,
        emit.map(event => PreviewEvent(event)),
      )
      (Editing({ ..editing, preview, }), command)
    }
    (Loading(_), ViewportChanged(width)) =>
      (Loading(compact_viewport(width)), @cmd.none)
    (OpeningNew(opening, creation), ViewportChanged(width)) =>
      (OpeningNew({ ..opening, compact: compact_viewport(width), }, creation), @cmd.none)
    (Recovery(failure, _), ViewportChanged(width)) =>
      (Recovery(failure, compact_viewport(width)), @cmd.none)
    (Editing(editing), ViewportChanged(width)) => {
      let compact = compact_viewport(width)
      (
        Editing({ ..editing, compact, }),
        if compact {
          @sidebar.sidebar_focus("loomark-document-sidebar")
        } else {
          @cmd.none
        },
      )
    }
    (Editing(editing), CreateRequested) =>
      if !editing.can_activate() {
        (Editing(editing), @cmd.none)
      } else {
        let generation = editing.next_creation_request_id
        (
          Editing({ ..editing, creation: Some({ request_id: generation, intent: NewDocument, status: InProgress, }), next_creation_request_id: generation + 1, }),
          @source_repository.create(
            editing.documents.snapshot(),
            emit.map(result => CreateCompleted(generation, result)),
          ),
        )
      }
    (Editing(editing), CreateCompleted(generation, Created(document_id))) =>
      if !(creation_request_is_current(editing.creation, generation)) {
        (Editing(editing), @cmd.none)
      } else {
        let editing = reduce_documents(
          editing,
          @documents.Msg::New(document_id),
          actions,
        )
        match
          activation_target(
            editing.documents,
            @documents.Key::source(document_id),
          ) {
          None => (Editing(editing), @cmd.none)
          Some(target) => {
            let ready = { ..editing, creation: None, }
            let (next, command) = ready.activate(target, emit, editor)
            (Editing(next), command)
          }
        }
      }
    (Editing(editing), CreateCompleted(generation, CreateFailed(failure))) =>
      if creation_request_is_current(editing.creation, generation) {
        (Editing({ ..editing, creation: Some({ request_id: generation, intent: NewDocument, status: Failed(failure), }), }), @cmd.none)
      } else {
        (Editing(editing), @cmd.none)
      }
    (Editing(editing), DocumentSelected(document_id)) =>
      match editing.selectable_activation(document_id) {
        None => (Editing(editing), @cmd.none)
        Some(target) => {
          let (editing, command) = editing.activate(target, emit, editor)
          (Editing(editing), command)
        }
      }
    (Editing(editing), DeleteRequested(document_id)) =>
      if creation_in_progress(editing.creation) ||
        editing.deletion != NoDeletion ||
        editing.documents.text(document_id) is None {
        (Editing(editing), @cmd.none)
      } else {
        match editing.documents.delete_status(document_id) {
          Some(Deletable)
          | Some(DeleteFailed(_))
          | Some(DeletePersistenceFailed(_)) =>
            (
              Editing({
                ..editing,
                deletion: DeleteConfirmation(document_id),
                menu_open: false,
              }),
              @cmd.none,
            )
          _ => (Editing(editing), @cmd.none)
        }
      }
    (Editing(editing), DeleteCancelled) =>
      match editing.deletion {
        DeleteConfirmation(target) =>
          (
            Editing({ ..editing, deletion: NoDeletion, }),
            focus_after_render("loomark-delete-\{target.lifecycle_key()}"),
          )
        NoDeletion => (Editing(editing), @cmd.none)
      }
    (Editing(editing), DismissDeleteFailure(document_id)) => {
      let editing = reduce_documents(
        editing,
        DismissDeleteFailure(document_id),
        actions,
      )
      (Editing(editing), @cmd.none)
    }
    _ => (model, @cmd.none)
  }
  (next, command)
}

///|
fn Page::saved_documents(self : Self) -> @source_repository.SavedDocuments? {
  match self {
    Editing(editing) => Some(editing.documents.snapshot())
    OpeningNew(preparing, _) =>
      Some(preparing.documents.snapshot())
    Loading(_) | Recovery(_, _) => None
  }
}

///|
fn Page::begin_fork(
  self : Self,
  write : @source_repository.ReplicaWrite,
) -> Page? {
  guard write is @source_repository.ReplicaWrite::Fork(replica, recovery) else { return None }
  match self {
    Editing(editing) => {
      let documents = editing.documents.begin_fork(write) catch { _ => return None }
      let original = @documents.Key::replica(replica.account(), replica.document_id())
      let activation = if editing.activation.key == original { { ..editing.activation, key: @documents.Key::source(recovery.id()), } } else { editing.activation }
      Some(Editing({ ..editing, documents, activation, }))
    }
    OpeningNew(opening, creation) => {
      let documents = opening.documents.begin_fork(write) catch { _ => return None }
      Some(OpeningNew({ ..opening, documents, }, creation))
    }
    Loading(_) | Recovery(_, _) => None
  }
}

///|
fn Page::project_account(self : Self, account : @source_repository.AccountId) -> Self {
  match self {
    Editing(editing) => Editing({ ..editing, documents: editing.documents.project_account(account), })
    OpeningNew(opening, creation) => OpeningNew({ ..opening, documents: opening.documents.project_account(account), }, creation)
    Loading(_) | Recovery(_, _) => self
  }
}

///|
fn Page::hide_accounts(self : Self) -> Self {
  match self {
    Editing(editing) => Editing({ ..editing, documents: editing.documents.hide_accounts(), })
    OpeningNew(opening, creation) => OpeningNew({ ..opening, documents: opening.documents.hide_accounts(), }, creation)
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
        guard model.page.saved_documents() is Some(saved) else {
          return (model, commands)
        }
        let (replication, effect) = model.replication.save_local(
          edit.durable(),
          edit.document().text(),
        )
        let model = { ..model, replication, }
        match effect {
          Some(effect) =>
            (model, commands + [run_replication_effect(saved, effect, emit)])
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
      ArmMaximum(id) =>
        (
          model,
          commands +
          [
            @cmd.delay(
              emit(DocumentMaximumElapsed(id)),
              AUTOSAVE_MAXIMUM_MS,
            ),
          ],
        )
      PersistSource(operation) => {
        let saved = model.page.saved_documents().unwrap()
        (
          model,
          commands +
          [
            @source_repository.save(
              saved,
              operation.document,
              emit.map(result => {
                match result {
                  @source_repository.SaveResult::Stored(document) => DocumentSaved(operation, document)
                  SaveFailed(failure) => DocumentSaveFailed(operation, failure)
                }
              }),
            ),
          ],
        )
      }
      DeleteSource(operation) => {
        let saved = model.page.saved_documents().unwrap()
        (
          model,
          commands +
          [
            @source_repository.delete(
              saved,
              operation.document_id,
              emit.map(result => {
                match result {
                  @source_repository.DeleteResult::Deleted(document_id) => DocumentDeleted(operation, document_id)
                  DeleteFailed(failure) => DocumentDeleteFailed(operation, failure)
                }
              }),
            ),
          ],
        )
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
    CreateOperation(attempt) =>
      @source_repository.operation_id(
        emit.map(result => Sync(OperationPrepared(attempt, result))),
      )
    Deliver(attempt, operation) =>
      @document_http.deliver(
        attempt.account(),
        attempt.document_id(),
        operation,
        emit.map(result => Sync(DeliveryCompleted(attempt, result))),
      )
    GetRemote(attempt) =>
      @document_http.get(
        attempt.account(),
        attempt.document_id(),
        emit.map(result => Sync(RemoteCompleted(attempt, result))),
      )
    OpenRemote(attempt) =>
      @document_http.get(
        attempt.account(),
        attempt.document_id(),
        emit.map(result => Sync(OpenCompleted(attempt, result))),
      )
    CreateRecovery(attempt) =>
      @source_repository.create(
        saved,
        emit.map(result => Sync(RecoveryCreated(attempt, result))),
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
  let result = Some(sync.begin_lookup()) catch { _ => None }
  match result {
    None => (sync, @cmd.none)
    Some((sync, lookup_id)) =>
      (
        sync,
        @account_http.resolve(
          emit.map(value => Sync(AccountResolved(lookup_id, value))),
        ),
      )
  }
}

///|
fn initial_state(
  emit : @rabbita.Emit[Msg],
  compact : Bool,
) -> (Model, @rabbita.Cmd) {
  let (page, page_command) = initial_page(emit, compact)
  (
    {
      page,
      replication: @replication.State(),
      sign_in: @sign_in.SignIn(),
      scroll_owner: TextPane,
    },
    @cmd.batch([
      page_command,
      @cmd.perform(failed => emit(AuthenticationReturned(failed)), () => {
        consume_authentication_error()
      }),
    ]),
  )
}

///|
fn update_delete(model : Model, key : @documents.Key, emit : @rabbita.Emit[Msg]) -> (Model, @rabbita.Cmd) {
  match model.page {
    Editing(editing) =>
      match editing.documents.delete(key) {
        Accepted(transition) => {
          let actions : Array[@documents.Action] = []
          let editing = install_document_transition(editing, transition, actions)
          let (model, command) = apply_document_actions({ ..model, page: Editing(editing), }, actions, emit)
          (model, command)
        }
        AlreadyPending => (model, @cmd.none)
      } catch {
        @documents.DeleteError::DocumentMissing(_) =>
          ({ ..model, page: Editing({ ..editing, lifecycle_error: Some("The document is no longer available. Refresh the document list and try again."), }), }, @cmd.none)
        @documents.DeleteError::OwnershipTransferInProgress(_) =>
          ({ ..model, page: Editing({ ..editing, lifecycle_error: Some("This document is being transferred and cannot be deleted yet."), }), }, @cmd.none)
        @documents.DeleteError::ReplicaMissing(_) =>
          ({ ..model, page: Editing({ ..editing, lifecycle_error: Some("The synchronized document is unavailable. Retry after synchronization recovers."), }), }, @cmd.none)
      }
    _ => (model, @cmd.none)
  }
}

///|
fn update_documents(
  model : Model,
  event : @documents.Msg,
  emit : @rabbita.Emit[Msg],
  editor : @editor.MarkdownEditor,
) -> (Model, @rabbita.Cmd) {
  let (page, actions, page_command) = reduce_page_documents(
    model.page,
    event,
    emit,
    editor,
  )
  let (model, action_command) = apply_document_actions(
    model.with_page(page),
    actions,
    emit,
  )
  (model, @cmd.batch([page_command, action_command]))
}

///|
fn begin_logout(
  model : Model,
  emit : @rabbita.Emit[Msg],
) -> (Model, @rabbita.Cmd) {
  let result = Some(model.sync().begin_logout()) catch { _ => None }
  guard result is Some((sync, attempt)) else { return (model, @cmd.none) }
  let model = model.with_sync(sync)
  (
    model,
    @account_http.sign_out(emit.map(result => LogoutCompleted(attempt, result))),
  )
}

///|
fn begin_account_lookup(
  model : Model,
  emit : @rabbita.Emit[Msg],
) -> (Model, @rabbita.Cmd) {
  let result = Some(model.sync().begin_lookup()) catch { _ => None }
  guard result is Some((sync, lookup_id)) else { return (model, @cmd.none) }
  (
    model.with_sync(sync),
    @account_http.resolve(
      emit.map(result => Sync(AccountResolved(lookup_id, result))),
    ),
  )
}

///|
fn is_user_mutating(msg : Msg) -> Bool {
  match msg {
    InputChanged(_, _)
    | TextChanged(_, _)
    | CompositionStarted(_)
    | ExampleSelected(_, _)
    | ImportFilesSelected(_)
    | CreateRequested
    | DeleteRequested(_)
    | DeleteConfirmed(_)
    | DeleteCancelled
    | DocumentSelected(_)
    | StartSync(_)
    | AcceptRemote(_)
    | LogoutRequested => true
    Opened(_)
    | EmptyCreateCompleted(_, _)
    | CompositionEnded(_)
    | ModeSelected(_)
    | MenuToggled
    | EscapePressed
    | ImportReadCompleted(_)
    | ImportCreateCompleted(_, _)
    | DismissImportFailure
    | ExportRequested
    | PreviewEvent(_)
    | ScrollClaimed(_)
    | ViewportChanged(_)
    | DocumentMaximumElapsed(_) | DocumentSaved(_, _) | DocumentSaveFailed(_, _) | DocumentDeleted(_, _) | DocumentDeleteFailed(_, _) | DocumentReplicaAdvanced(_) | DocumentReplicaSettled(_, _) | DocumentReplicaDeletionFailed(_, _) | DocumentPromoted(_) | DocumentPromotionFailed(_, _)
    | ApplyPendingEdit(_, _)
    | VisibilityChanged(_)
    | PageRestored
    | RetrySave
    | RetryAccount
    | RetrySaving(_)
    | RetrySync(_)
    | RetrySelection(_)
    | CreateCompleted(_, _)
    | ExampleCreateCompleted(_, _, _)
    | RetryDelete(_)
    | DismissDeleteFailure(_)
    | SignIn(_)
    | LogoutCompleted(_, _)
    | AuthenticationReturned(_)
    | Sync(_) => false
  }
}

///|
fn Msg::supersedes_remote_selection(self : Self) -> Bool {
  match self {
    DocumentSelected(_)
    | CreateRequested
    | ImportFilesSelected(_)
    | ExampleSelected(_, _) => true
    _ => false
  }
}

///|
fn reduce(
  model : Model,
  msg : Msg,
  emit : @rabbita.Emit[Msg],
  editor : @editor.MarkdownEditor,
) -> (Model, @rabbita.Cmd) {
  let model = match msg {
    ModeSelected(Text) => { ..model, scroll_owner: TextPane, }
    ModeSelected(Preview) => { ..model, scroll_owner: PreviewPane, }
    _ => model
  }
  let model = interrupt_sign_in(model, msg)
  match msg {
    ScrollClaimed(pane) => ({ ..model, scroll_owner: pane, }, @cmd.none)
    AuthenticationReturned(_) | PageRestored | SignIn(_) =>
      update_sign_in(model, msg, emit)
    LogoutRequested => begin_logout(model, emit)
    LogoutCompleted(attempt, result) => {
      let confirmed = match result {
        @account_http.LogoutResult::SignedOut => true
        Unconfirmed => false
      }
      let transition = Some(model.sync().logged_out(attempt, confirmed)) catch {
        _ => None
      }
      guard transition is Some((sync, selection)) else {
        return (model, @cmd.none)
      }
      let page = match selection {
        Some(@sync.AccountSelection::NoAccountSelected) =>
          model.page.hide_accounts()
        _ => model.page
      }
      (model.with_sync(sync).with_page(page), @cmd.none)
    }
    ApplyPendingEdit(document_id, revision) =>
      update_documents(
        model,
        @documents.Msg::ApplyPendingEdit(document_id, revision),
        emit,
        editor,
      )
    DocumentMaximumElapsed(id) => update_documents(model, @documents.Msg::MaximumElapsed(id), emit, editor)
    DocumentSaved(operation, document) => update_documents(model, @documents.Msg::Saved(operation, document), emit, editor)
    DocumentSaveFailed(operation, failure) => update_documents(model, @documents.Msg::SaveFailed(operation, failure), emit, editor)
    DocumentDeleted(operation, document_id) => update_documents(model, @documents.Msg::Deleted(operation, document_id), emit, editor)
    DocumentDeleteFailed(operation, failure) => update_documents(model, @documents.Msg::DeleteFailed(operation, failure), emit, editor)
    DocumentReplicaAdvanced(write) => update_documents(model, @documents.Msg::ReplicaAdvanced(write), emit, editor)
    DocumentReplicaSettled(write, key) => update_documents(model, @documents.Msg::ReplicaSettled(write, key), emit, editor)
    DocumentReplicaDeletionFailed(write, failure) => update_documents(model, @documents.Msg::ReplicaDeletionFailed(write, failure), emit, editor)
    DocumentPromoted(write) => update_documents(model, @documents.Msg::Promoted(write), emit, editor)
    DocumentPromotionFailed(write, failure) => update_documents(model, @documents.Msg::PromotionFailed(write, failure), emit, editor)
    CompositionEnded(generation) =>
      match model.page {
        Editing(editing) if generation == editing.activation.generation =>
          update_documents(
            model,
            @documents.Msg::CompositionEnded(editing.activation.key),
            emit,
            editor,
          )
        _ => (model, @cmd.none)
      }
    DeleteConfirmed(document_id) =>
      match model.page {
        Editing(editing) if editing.deletion == DeleteConfirmation(document_id) =>
          update_delete({ ..model, page: Editing({ ..editing, deletion: NoDeletion, lifecycle_error: None, }), }, document_id, emit)
        _ => (model, @cmd.none)
      }
    RetryDelete(document_id) => update_delete(model, document_id, emit)
    VisibilityChanged(true) =>
      match model.page {
        Editing(_) =>
          update_documents(
            model,
            @documents.Msg::VisibilityFlushAll,
            emit,
            editor,
          )
        _ => (model, @cmd.none)
      }
    RetrySave =>
      match model.page {
        Editing(editing) => {
          let (model, command) = update_documents(
            model,
            @documents.Msg::RetrySave(editing.activation.key),
            emit,
            editor,
          )
          (
            model,
            @cmd.batch([
              command,
              focus_after_render(editor_focus_id(editing.mode)),
            ]),
          )
        }
        _ => (model, @cmd.none)
      }
    RetryAccount => begin_account_lookup(model, emit)
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
      let known_remote = model.sync().remote_head(document_id)
      let accepted = Some(
        editing.documents.accept_remote(replica, known_remote, action),
      ) catch {
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
            target, emit, editor,
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
            editor,
            @cmd.none,
          )
          let (model, persist) = submit_replica({ ..model, page, }, write, emit)
          (model, @cmd.batch([activate, persist]))
        }
      }
    }
    RetrySaving(action) => {
      guard model.page.saved_documents() is Some(saved) else {
        return (model, @cmd.none)
      }
      let result = Some(model.replication.retry_save(action)) catch {
        _ => None
      }
      guard result is Some((replication, effect)) else {
        return (model, @cmd.none)
      }
      let model = { ..model, replication, }
      (model, run_replication_effect(saved, effect, emit))
    }
    RetrySync(action) => {
      guard model.page.saved_documents() is Some(saved) else {
        return (model, @cmd.none)
      }
      let result = Some(model.replication.retry_sync(saved, action)) catch {
        _ => None
      }
      guard result is Some((replication, effect)) else {
        return (model, @cmd.none)
      }
      let model = { ..model, replication, }
      (model, run_replication_effect(saved, effect, emit))
    }
    RetrySelection(action) => {
      guard model.page.saved_documents() is Some(saved) else {
        return (model, @cmd.none)
      }
      let result = Some(model.replication.retry_selection(saved, action)) catch {
        _ => None
      }
      guard result is Some((replication, effect)) else {
        return (model, @cmd.none)
      }
      ({ ..model, replication, }, run_replication_effect(saved, effect, emit))
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
      let mounted = match model.page {
        Editing(editing) => Some(editing.activation.key)
        Loading(_)
        | OpeningNew(_, _)
        | OpeningNew(_, _)
        | Recovery(_, _) => None
      }
      let document_message = @documents.Msg::from_replica_completion(
        attempt.write(),
        completion,
        mounted,
      )
      let (page, page_actions, page_command) = match document_message {
        Some(event) =>
          reduce_page_documents(
            model.page,
            event,
            emit,
            editor,
          )
        None => (model.page, [], @cmd.none)
      }
      let (model, page_actions_command) = apply_document_actions(
        { ..model, page, replication, },
        page_actions,
        emit,
      )
      let (model, continuation) = match completion {
        @replica_persistence.Completion::Current(write) => {
          let replica = write.replica()
          match model.page.saved_documents() {
            Some(saved) =>
              match saved.replica(replica.account(), replica.document_id()) {
                Some(durable) => settle_replica(model, durable, emit)
                None => (model, @cmd.none)
              }
            None => (model, @cmd.none)
          }
        }
        Superseded(_, next) => (model, persist_replica(saved, next, emit))
        Retryable(_, _, _) | Failed(_, _) => (model, @cmd.none)
      }
      (model, @cmd.batch([page_command, page_actions_command, continuation]))
    }
    Sync(OperationPrepared(attempt, result)) =>
      match result {
        None => {
          let sync = model.sync().planning_failed(attempt) catch {
              _ => return (model, @cmd.none)
            }
          (model.with_sync(sync), @cmd.none)
        }
        Some(operation_id) => {
          guard model.page.saved_documents() is Some(saved) &&
            saved.replica(attempt.account(), attempt.document_id())
            is Some(durable) &&
            model.replication.status(attempt.account(), attempt.document_id())
            is @replica_persistence.Status::Current else {
            let sync = model.sync().planning_failed(attempt) catch {
                _ => return (model, @cmd.none)
              }
            return (model.with_sync(sync), @cmd.none)
          }
          let transition = Some(
            model.sync().prepared(attempt, durable, operation_id),
          ) catch {
            _ => None
          }
          guard transition is Some((sync, write)) else {
            return (model, @cmd.none)
          }
          submit_sync_replica(model, sync, write, emit)
        }
      }
    Sync(DeliveryCompleted(attempt, result)) => {
      let account = attempt.account()
      guard model.page.saved_documents() is Some(saved) else {
        return (model, @cmd.none)
      }
      let transition = Some(
        model.replication.finish_delivery(saved, attempt, result),
      ) catch {
        // A delayed response cannot complete a different durable operation.
        _ => None
      }
      guard transition is Some((replication, effect)) else {
        return (model, @cmd.none)
      }
      let model = { ..model, replication, }
      let command = effect
        .map(value => run_replication_effect(saved, value, emit))
        .unwrap_or(@cmd.none)
      if result is @replication.DeliveryResult::AccountChanged {
        let (sync, lookup) = resolve_changed_account(
          model.sync(),
          account,
          emit,
        )
        (model.with_sync(sync), lookup)
      } else {
        (model, command)
      }
    }
    Sync(OpenCompleted(attempt, result)) => {
      let account = attempt.account()
      match result {
        @document_http.RemoteResult::Found(remote) => {
          guard model.page.saved_documents() is Some(saved) else {
            return (model, @cmd.none)
          }
          let transition = Some(
            model.replication.opened(saved, attempt, remote),
          ) catch {
            _ => None
          }
          guard transition is Some((replication, effect)) else {
            return (model, @cmd.none)
          }
          (
            { ..model, replication, },
            effect
            .map(value => run_replication_effect(saved, value, emit))
            .unwrap_or(@cmd.none),
          )
        }
        AccountChanged | Unavailable => {
          let sync = model.sync().open_failed(attempt) catch {
              _ => return (model, @cmd.none)
            }
          if result is AccountChanged {
            let (sync, lookup) = resolve_changed_account(sync, account, emit)
            (model.with_sync(sync), lookup)
          } else {
            (model.with_sync(sync), @cmd.none)
          }
        }
      }
    }
    Sync(RemoteCompleted(attempt, result)) => {
      let account = attempt.account()
      let document_id = attempt.document_id()
      guard model.page.saved_documents() is Some(saved) &&
        saved.replica(account, document_id) is Some(durable) else {
        return (model, @cmd.none)
      }
      match result {
        @document_http.RemoteResult::Found(remote) => {
          let transition = Some(
            model.replication.receive_remote(durable, attempt, remote),
          ) catch {
            _ => None
          }
          guard transition is Some((replication, effect)) else {
            return (model, @cmd.none)
          }
          let model = { ..model, replication, }
          (
            model,
            effect
            .map(value => run_replication_effect(saved, value, emit))
            .unwrap_or(@cmd.none),
          )
        }
        AccountChanged | Unavailable => {
          let base = model.replication.protocol_base(durable)
          let sync = model.sync().remote_failed(base, attempt) catch {
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
    Sync(RecoveryCreated(attempt, result)) => {
      guard result is @source_repository.CreateResult::Created(recovery_id) else {
        let sync = model.sync().recovery_failed(attempt) catch {
            _ => return (model, @cmd.none)
          }
        return (model.with_sync(sync), @cmd.none)
      }
      guard model.page.saved_documents() is Some(saved) &&
        saved.replica(attempt.account(), attempt.document_id()) is Some(durable) else {
        let sync = model.sync().recovery_failed(attempt) catch {
            _ => return (model, @cmd.none)
          }
        return (model.with_sync(sync), @cmd.none)
      }
      let base = model.replication.protocol_base(durable)
      let transition = Some(model.sync().recover(base, attempt, recovery_id)) catch {
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
      let (replication, effects) = model.replication.select(saved, document_id)
      let command = run_replication_effects(saved, effects, emit)
      ({ ..model, replication, }, command)
    }
    message => {
      let model = if message.supersedes_remote_selection() {
        { ..model, replication: model.replication.cancel_selection(), }
      } else {
        model
      }
      let actions : Array[@documents.Action] = []
      let (page, page_command) = update_page(
        model.page,
        message,
        emit,
        editor,
        actions,
      )
      let (model, action_command) = apply_document_actions(
        model.with_page(page),
        actions,
        emit,
      )
      let command = @cmd.batch([page_command, action_command])
      match message {
        Opened(_) | VisibilityChanged(false) => {
          let (model, account_command) = begin_account_lookup(model, emit)
          (model, @cmd.batch([command, account_command]))
        }
        _ => (model, command)
      }
    }
  }
}

///|
fn update(
  model : Model,
  msg : Msg,
  emit : @rabbita.Emit[Msg],
  editor : @editor.MarkdownEditor,
) -> (Model, @rabbita.Cmd) {
  let (model, command) = reduce(model, msg, emit, editor)
  let (model, command) = activate_open(model, command, emit, editor)
  let (model, sign_in_command) = update_sign_in(
    model,
    SignIn(@sign_in.Refresh),
    emit,
  )
  (model, @cmd.batch([command, sign_in_command]))
}

///|
fn reduce_page_documents(
  model : Page,
  event : @documents.Msg,
  emit : @rabbita.Emit[Msg],
  editor : @editor.MarkdownEditor,
) -> (Page, Array[@documents.Action], @rabbita.Cmd) {
  match model {
    Editing(editing) => {
      let active = editing.activation
      let actions : Array[@documents.Action] = []
      let (updated, _) = document_update(editing, event, actions)
      let updated = match event {
        @documents.Msg::Promoted(write) if active.key is @documents.Key::Source(id) && id == write.replica().document_id() => {
          let replica = write.replica()
          let key = @documents.Key::replica(replica.account(), replica.document_id())
          if updated.documents.text(active.key) is None && updated.documents.text(key) is Some(_) {
            { ..updated, activation: { ..active, key, }, }
          } else { updated }
        }
        _ => updated
      }
      let (page, command) = reconcile_active(updated, emit, editor, @cmd.none)
      (page, actions, command)
    }
    OpeningNew(opening, creation) =>
      match opening.documents.update(event) {
        Applied(transition) => {
          let actions : Array[@documents.Action] = []
          for action in transition.effects { actions.push(action) }
          (OpeningNew({ ..opening, documents: transition.model, lifecycle_error: None, }, creation), actions, @cmd.none)
        }
        Superseded => (model, [], @cmd.none)
      } catch {
        @documents.UpdateError::DocumentMismatch(_) =>
          (OpeningNew({ ..opening, lifecycle_error: Some("Document acknowledgment did not match the current document. The current document was retained."), }, creation), [], @cmd.none)
        @documents.UpdateError::DocumentAlreadyExists(_) =>
          (OpeningNew({ ..opening, lifecycle_error: Some("This document already exists. Reopen it to recover."), }, creation), [], @cmd.none)
        @documents.UpdateError::InvalidAcknowledgment(_) =>
          (OpeningNew({ ..opening, lifecycle_error: Some("Document storage returned an invalid acknowledgment. The current document was retained."), }, creation), [], @cmd.none)
      }
    Loading(_) | Recovery(_, _) => (model, [], @cmd.none)
  }
}

///|
fn reconcile_active(
  editing : EditingDocument,
  emit : @rabbita.Emit[Msg],
  editor : @editor.MarkdownEditor,
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
            let (editing, command) = editing.activate(target, emit, editor)
            (Editing(editing), @cmd.batch([prior, command]))
          }
        }
      None => {
        let request_id = editing.activation.generation + 1
        let opening : OpeningNewContext = {
          documents: editing.documents, mode: editing.mode, compact: editing.compact,
          next_activation_generation: request_id, lifecycle_error: None,
        }
        let creation : Creation = { request_id, intent: NewDocument, status: InProgress, }
        (OpeningNew(opening, creation), @cmd.batch([
          prior,
          @source_repository.create(
            editing.documents.snapshot(),
            emit.map(result => EmptyCreateCompleted(request_id, result)),
          ),
        ]))
      }
    }
  }
}

