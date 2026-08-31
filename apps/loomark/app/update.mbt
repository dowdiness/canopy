///|
const AUTOSAVE_QUIET_MS : Int = 250

///|
const AUTOSAVE_MAXIMUM_MS : Int = 2000

///|
const COMPACT_MAX_WIDTH : Int = 640

///|
fn compact_viewport(width : Int) -> Bool {
  width <= COMPACT_MAX_WIDTH
}

///|
fn preview_input(editing : EditingState) -> @preview.Input {
  @preview.Input(editing.activation.generation, editing.text)
}

///|
fn select_mode(
  editing : EditingState,
  mode : EditorMode,
  emit : @rabbita.Emit[Msg],
  preview_engine : @preview.PreviewEngine,
) -> (EditingState, @rabbita.Cmd) {
  let entering_preview = editing.mode == Text && mode != Text
  let editing = { ..editing, mode, }
  if entering_preview {
    let (preview, command) = preview_engine.request(
      editing.preview,
      preview_input(editing),
      emit.map(event => PreviewEvent(event)),
    )
    ({ ..editing, preview, }, command)
  } else {
    (editing, @cmd.none)
  }
}

///|
fn deletion_blocks_document_changes(editing : EditingState) -> Bool {
  match editing.deletion {
    DeleteConfirmation(_) | Deleting(_, _) => true
    NoDeletion | DeleteFailed(_, _) => false
  }
}

///|
fn can_activate(editing : EditingState) -> Bool {
  editing.save == Saved &&
  !editing.composing &&
  editing.creation != Creating &&
  !deletion_blocks_document_changes(editing)
}

///|
fn save_effect_command(
  editing : EditingState,
  effect : SaveEffect,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Cmd {
  let owner = editing.activation
  match effect {
    NoSaveEffect => @cmd.none
    ArmQuiet(epoch, quiet_revision) =>
      @cmd.delay(
        emit(QuietElapsed(owner, epoch, quiet_revision)),
        AUTOSAVE_QUIET_MS,
      )
    ArmQuietAndMaximum(epoch, quiet_revision) =>
      @cmd.batch([
        @cmd.delay(
          emit(QuietElapsed(owner, epoch, quiet_revision)),
          AUTOSAVE_QUIET_MS,
        ),
        @cmd.delay(emit(MaximumElapsed(owner, epoch)), AUTOSAVE_MAXIMUM_MS),
      ])
    Persist(candidate) =>
      @source_repository.save(
        editing.repository,
        owner.document_id,
        candidate,
        result=emit.map(result => SaveCompleted(owner, candidate, result)),
      )
  }
}

///|
fn activate_document(
  editing : EditingState,
  source : @source_repository.SourceRecord,
  emit : @rabbita.Emit[Msg],
  text_area : @text_area.TextArea,
  preview_engine : @preview.PreviewEngine,
) -> (EditingState, @rabbita.Cmd) {
  let activation : Activation = {
    document_id: source.document_id(),
    generation: editing.activation.generation + 1,
  }
  let input = @preview.Input(activation.generation, source.text())
  let (preview, activate_command) = preview_engine.activate(input)
  let (preview, request_command) = if editing.mode == Text {
    (preview, @cmd.none)
  } else {
    preview_engine.request(
      preview,
      input,
      emit.map(event => PreviewEvent(event)),
    )
  }
  (
    {
      ..editing,
      activation,
      text: source.text(),
      composing: false,
      save: Saved,
      last_checkpoint_epoch: 0,
      creation: Idle,
      preview,
    },
    @cmd.batch([
      text_area.initialize(source.text()),
      activate_command,
      request_command,
    ]),
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
    (Loading(compact), Opened(result)) =>
      match result {
        @source_repository.OpenResult::Ready(snapshot) =>
          match snapshot.selected() {
            Some(source) => {
              let text = source.text()
              let (preview, preview_command) = preview_engine.activate(
                @preview.Input(0, text),
              )
              (
                Editing({
                  activation: {
                    document_id: source.document_id(),
                    generation: 0,
                  },
                  text,
                  composing: false,
                  save: Saved,
                  last_checkpoint_epoch: 0,
                  creation: Idle,
                  deletion: NoDeletion,
                  last_delete_request: 0,
                  mode: Text,
                  compact,
                  preview,
                  repository: snapshot,
                }),
                @cmd.batch([text_area.initialize(text), preview_command]),
              )
            }
            None =>
              (
                Recovery(@source_repository.OpenFailure::ReadFailed, compact),
                @cmd.none,
              )
          }
        @source_repository.OpenResult::Failed(failure) =>
          (Recovery(failure, compact), @cmd.none)
      }
    (Editing(editing), ExampleSelected(owner, text)) =>
      if owner != editing.activation {
        (model, @cmd.none)
      } else if editing.creation == Creating ||
        deletion_blocks_document_changes(editing) {
        (model, text_area.initialize(editing.text))
      } else {
        (
          model,
          @cmd.batch([
            text_area.initialize(text),
            emit(
              TextChanged(
                editing.activation,
                @text_change.TextChange::ReplaceAll(text),
              ),
            ),
          ]),
        )
      }
    (Editing(editing), TextChanged(owner, change)) =>
      if owner != editing.activation {
        (model, @cmd.none)
      } else if editing.creation == Creating ||
        deletion_blocks_document_changes(editing) {
        (model, text_area.initialize(editing.text))
      } else {
        match change.apply(editing.text) {
          None =>
            (
              model,
              text_area.value(text => {
                emit(
                  TextChanged(owner, @text_change.TextChange::ReplaceAll(text)),
                )
              }),
            )
          Some(text) if text == editing.text => (model, @cmd.none)
          Some(text) => {
            let (editing, save_effect) = save_after_text_changed(editing, text)
            let save_command = save_effect_command(editing, save_effect, emit)
            let (preview, preview_command) = preview_engine.document_changed(
              editing.preview,
              preview_input(editing),
              change,
              emit.map(event => PreviewEvent(event)),
            )
            (
              Editing({ ..editing, preview, }),
              @cmd.batch([save_command, preview_command]),
            )
          }
        }
      }
    (Editing(editing), CompositionStarted(owner)) =>
      if owner != editing.activation ||
        editing.creation == Creating ||
        deletion_blocks_document_changes(editing) {
        (model, @cmd.none)
      } else {
        (Editing({ ..editing, composing: true }), @cmd.none)
      }
    (Editing(editing), CompositionEnded(owner)) =>
      if owner != editing.activation {
        (model, @cmd.none)
      } else if editing.creation == Creating ||
        deletion_blocks_document_changes(editing) {
        (model, text_area.initialize(editing.text))
      } else {
        let (editing, save_effect) = save_after_composition_ended(editing)
        (Editing(editing), save_effect_command(editing, save_effect, emit))
      }
    (Editing(editing), ModeSelected(mode)) => {
      let (editing, command) = select_mode(editing, mode, emit, preview_engine)
      (Editing(editing), command)
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
    (Editing(editing), CreateRequested) =>
      if !can_activate(editing) {
        (model, @cmd.none)
      } else {
        let owner = editing.activation
        (
          Editing({ ..editing, creation: Creating }),
          @source_repository.create(
            editing.repository,
            result=emit.map(result => CreateCompleted(owner, result)),
          ),
        )
      }
    (Editing(editing), CreateCompleted(owner, result)) =>
      if owner != editing.activation || editing.creation != Creating {
        (model, @cmd.none)
      } else {
        match result {
          @source_repository.CreateResult::Failed(failure) =>
            (
              Editing({ ..editing, creation: CreationFailed(failure) }),
              @cmd.none,
            )
          @source_repository.CreateResult::Created(snapshot, document_id) =>
            match snapshot.source(document_id) {
              None =>
                (
                  Editing({
                    ..editing,
                    creation: CreationFailed(
                      @source_repository.CreateFailure::WriteFailed,
                    ),
                  }),
                  @cmd.none,
                )
              Some(source) => {
                let prepared = { ..editing, repository: snapshot }
                let (editing, command) = activate_document(
                  prepared, source, emit, text_area, preview_engine,
                )
                (Editing(editing), command)
              }
            }
        }
      }
    (Editing(editing), DocumentSelected(document_id)) =>
      if document_id == editing.activation.document_id {
        (model, @cmd.none)
      } else if !can_activate(editing) {
        (model, @cmd.none)
      } else {
        match editing.repository.source(document_id) {
          None => (model, @cmd.none)
          Some(source) => {
            let (editing, command) = activate_document(
              editing, source, emit, text_area, preview_engine,
            )
            (Editing(editing), command)
          }
        }
      }
    (Editing(editing), DeleteRequested(document_id)) =>
      if !can_activate(editing) ||
        editing.repository.source(document_id) is None ||
        editing.repository.sources().length() <= 1 {
        (model, @cmd.none)
      } else {
        (
          Editing({ ..editing, deletion: DeleteConfirmation(document_id) }),
          @cmd.none,
        )
      }
    (Editing(editing), DeleteCancelled) =>
      match editing.deletion {
        DeleteConfirmation(_) =>
          (Editing({ ..editing, deletion: NoDeletion }), @cmd.none)
        NoDeletion | Deleting(_, _) | DeleteFailed(_, _) => (model, @cmd.none)
      }
    (Editing(editing), DeleteConfirmed(document_id)) =>
      if editing.deletion != DeleteConfirmation(document_id) ||
        editing.save != Saved ||
        editing.composing ||
        editing.creation == Creating ||
        editing.repository.source(document_id) is None ||
        editing.repository.sources().length() <= 1 {
        (model, @cmd.none)
      } else {
        let request = editing.last_delete_request + 1
        (
          Editing({
            ..editing,
            deletion: Deleting(request, document_id),
            last_delete_request: request,
          }),
          @source_repository.delete(
            editing.repository,
            document_id,
            result=emit.map(result => DeleteCompleted(request, result)),
          ),
        )
      }
    (Editing(editing), DeleteCompleted(request, result)) =>
      match editing.deletion {
        Deleting(active_request, document_id) if active_request == request =>
          match result {
            @source_repository.DeleteResult::Failed(failure) =>
              (
                Editing({
                  ..editing,
                  deletion: DeleteFailed(document_id, failure),
                }),
                @cmd.none,
              )
            @source_repository.DeleteResult::Deleted(repository) =>
              if document_id != editing.activation.document_id {
                (
                  Editing({ ..editing, repository, deletion: NoDeletion }),
                  @cmd.none,
                )
              } else {
                let source = repository.selected().unwrap()
                let prepared = { ..editing, repository, deletion: NoDeletion }
                let (editing, command) = activate_document(
                  prepared, source, emit, text_area, preview_engine,
                )
                (Editing(editing), command)
              }
          }
        NoDeletion
        | DeleteConfirmation(_)
        | DeleteFailed(_, _)
        | Deleting(_, _) => (model, @cmd.none)
      }
    (Editing(editing), DismissDeleteFailure) =>
      match editing.deletion {
        DeleteFailed(_, _) =>
          (Editing({ ..editing, deletion: NoDeletion }), @cmd.none)
        NoDeletion | DeleteConfirmation(_) | Deleting(_, _) =>
          (model, @cmd.none)
      }
    (Editing(editing), ViewportChanged(width)) =>
      (Editing({ ..editing, compact: compact_viewport(width) }), @cmd.none)
    (Recovery(failure, _), ViewportChanged(width)) =>
      (Recovery(failure, compact_viewport(width)), @cmd.none)
    (Editing(editing), QuietElapsed(owner, epoch, quiet_revision)) =>
      if owner != editing.activation {
        (model, @cmd.none)
      } else {
        match editing.save.pending_checkpoint() {
          Some(checkpoint) if checkpoint.epoch == epoch &&
            checkpoint.quiet_revision == quiet_revision => {
            let (editing, save_effect) = save_after_eligible(editing, epoch)
            (Editing(editing), save_effect_command(editing, save_effect, emit))
          }
          _ => (model, @cmd.none)
        }
      }
    (Editing(editing), MaximumElapsed(owner, epoch)) =>
      if owner != editing.activation {
        (model, @cmd.none)
      } else {
        let (editing, save_effect) = save_after_eligible(editing, epoch)
        (Editing(editing), save_effect_command(editing, save_effect, emit))
      }
    (Editing(editing), VisibilityChanged(hidden)) =>
      if !hidden {
        (model, @cmd.none)
      } else {
        match editing.save.pending_checkpoint() {
          None => (model, @cmd.none)
          Some(checkpoint) => {
            let (editing, save_effect) = save_after_eligible(
              editing,
              checkpoint.epoch,
            )
            (Editing(editing), save_effect_command(editing, save_effect, emit))
          }
        }
      }
    (Editing(editing), SaveCompleted(owner, candidate, result)) =>
      if owner != editing.activation {
        (model, @cmd.none)
      } else {
        match editing.save {
          Saving(active_candidate, pending) if active_candidate == candidate =>
            match result {
              @source_repository.SaveResult::Stored(repository) => {
                let (editing, save_effect) = save_after_success(
                  editing, candidate, pending, repository,
                )
                (
                  Editing(editing),
                  save_effect_command(editing, save_effect, emit),
                )
              }
              @source_repository.SaveResult::Failed(failure) =>
                (Editing(save_after_failure(editing, failure)), @cmd.none)
            }
          Saved | Waiting(_) | Saving(_, _) | Failed(_, _) => (model, @cmd.none)
        }
      }
    (Editing(editing), RetrySave) => {
      let (editing, save_effect) = save_after_retry(editing)
      (Editing(editing), save_effect_command(editing, save_effect, emit))
    }
    _ => (model, @cmd.none)
  }
}
