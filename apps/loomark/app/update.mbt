///|
const AUTOSAVE_QUIET_MS : Int = 250

///|
const PREVIEW_QUIET_MS : Int = 24

///|
const COMPACT_MAX_WIDTH : Int = 640

///|
fn compact_viewport(width : Int) -> Bool {
  width <= COMPACT_MAX_WIDTH
}

///|
fn preview_last(state : PreviewState) -> PreviewResult? {
  match state {
    Ready(result) => Some(result)
    Failed(result) => result
    Unrequested | Preparing => None
  }
}

///|
fn completed_preview(
  text : String,
  output : @preview.PreviewOutput,
) -> PreviewResult {
  { text, html: output.html, empty: output.empty }
}

///|
fn select_mode(
  editing : EditingState,
  mode : EditorMode,
  emit : @rabbita.Emit[Msg],
  preview_engine : @preview.PreviewEngine,
) -> (EditingState, @rabbita.Cmd) {
  let entering_preview = editing.mode == Text && mode != Text
  match editing.preview {
    Unrequested if mode != Text =>
      (
        { ..editing, mode, preview: Preparing },
        @preview.after_paint(emit(BeginPreviewPreparation(editing.activation))),
      )
    Failed(_) if entering_preview =>
      (
        { ..editing, mode, },
        @preview.refresh_cmd(
          preview_engine,
          editing.activation.generation,
          editing.text,
          result=emit.map(result => {
            PreviewRefreshed(editing.activation, editing.text, result)
          }),
        ),
      )
    Unrequested | Preparing | Ready(_) | Failed(_) =>
      ({ ..editing, mode, }, @cmd.none)
  }
}

///|
fn can_activate(editing : EditingState) -> Bool {
  editing.save == Saved && !editing.composing && editing.creation != Creating
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
  let preview = if editing.mode == Text { Unrequested } else { Preparing }
  let prepare_command = if editing.mode == Text {
    @cmd.none
  } else {
    @preview.after_paint(emit(BeginPreviewPreparation(activation)))
  }
  let next = {
    ..editing,
    activation,
    text: source.text(),
    composing: false,
    save: Saved,
    creation: Idle,
    preview,
  }
  (
    next,
    @cmd.batch([
      text_area.initialize(source.text()),
      @preview.activate_cmd(preview_engine, activation.generation),
      prepare_command,
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
              (
                Editing({
                  activation: {
                    document_id: source.document_id(),
                    generation: 0,
                  },
                  text,
                  composing: false,
                  save: Saved,
                  creation: Idle,
                  mode: Text,
                  compact,
                  preview: Unrequested,
                  repository: snapshot,
                }),
                @cmd.batch([
                  text_area.initialize(text),
                  @preview.activate_cmd(preview_engine, 0),
                ]),
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
      } else if editing.creation == Creating {
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
      } else if editing.creation == Creating {
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
            let save = match editing.save {
              Saving(candidate) => Saving(candidate)
              _ => Waiting
            }
            let save_command = if editing.composing {
              @cmd.none
            } else {
              @cmd.delay(emit(SaveRequested(owner, text)), AUTOSAVE_QUIET_MS)
            }
            let preview_command = match editing.preview {
              Unrequested | Preparing => @cmd.none
              Ready(_) =>
                @preview.apply_cmd(
                  preview_engine,
                  owner.generation,
                  change,
                  text,
                  result=emit.map(result => {
                    ParserAdvanced(owner, text, false, result)
                  }),
                )
              Failed(_) =>
                @preview.apply_cmd(
                  preview_engine,
                  owner.generation,
                  change,
                  text,
                  result=emit.map(result => {
                    ParserAdvanced(owner, text, true, result)
                  }),
                )
            }
            (
              Editing({ ..editing, text, save }),
              @cmd.batch([save_command, preview_command]),
            )
          }
        }
      }
    (Editing(editing), CompositionStarted(owner)) =>
      if owner != editing.activation || editing.creation == Creating {
        (model, @cmd.none)
      } else {
        (Editing({ ..editing, composing: true }), @cmd.none)
      }
    (Editing(editing), CompositionEnded(owner)) =>
      if owner != editing.activation {
        (model, @cmd.none)
      } else if editing.creation == Creating {
        (model, text_area.initialize(editing.text))
      } else {
        let command = match editing.save {
          Waiting =>
            @cmd.delay(
              emit(SaveRequested(owner, editing.text)),
              AUTOSAVE_QUIET_MS,
            )
          Saved | Saving(_) | Failed(_) => @cmd.none
        }
        (Editing({ ..editing, composing: false }), command)
      }
    (Editing(editing), ModeSelected(mode)) => {
      let (editing, command) = select_mode(editing, mode, emit, preview_engine)
      (Editing(editing), command)
    }
    (Editing(editing), BeginPreviewPreparation(owner)) =>
      if owner != editing.activation {
        (model, @cmd.none)
      } else {
        match editing.preview {
          Preparing =>
            (
              model,
              @preview.prepare_cmd(
                preview_engine,
                owner.generation,
                editing.text,
                result=emit.map(result => {
                  PreviewPrepared(owner, editing.text, result)
                }),
              ),
            )
          Unrequested | Ready(_) | Failed(_) => (model, @cmd.none)
        }
      }
    (Editing(editing), PreviewPrepared(owner, candidate, result)) =>
      if owner != editing.activation {
        (model, @cmd.none)
      } else if candidate != editing.text {
        (
          Editing({ ..editing, preview: Failed(None) }),
          @cmd.batch([
            @preview.discard_cmd(preview_engine, owner.generation),
            @cmd.delay(
              emit(PreviewRefreshRequested(owner, editing.text)),
              PREVIEW_QUIET_MS,
            ),
          ]),
        )
      } else {
        match result {
          Ok(output) =>
            (
              Editing({
                ..editing,
                preview: Ready(completed_preview(candidate, output)),
              }),
              @cmd.none,
            )
          Err(_) => (Editing({ ..editing, preview: Failed(None) }), @cmd.none)
        }
      }
    (Editing(editing), ParserAdvanced(owner, candidate, retry, result)) =>
      if owner != editing.activation {
        (model, @cmd.none)
      } else {
        match result {
          Ok(_) =>
            (
              model,
              @cmd.delay(
                emit(PreviewRefreshRequested(owner, candidate)),
                PREVIEW_QUIET_MS,
              ),
            )
          Err(_) => {
            let command = if retry {
              @cmd.delay(
                emit(PreviewRefreshRequested(owner, candidate)),
                PREVIEW_QUIET_MS,
              )
            } else {
              @cmd.none
            }
            (
              Editing({
                ..editing,
                preview: Failed(preview_last(editing.preview)),
              }),
              command,
            )
          }
        }
      }
    (Editing(editing), PreviewRefreshRequested(owner, candidate)) =>
      if owner != editing.activation || candidate != editing.text {
        (model, @cmd.none)
      } else {
        match editing.preview {
          Unrequested | Preparing => (model, @cmd.none)
          Ready(_) | Failed(_) =>
            (
              model,
              @preview.refresh_cmd(
                preview_engine,
                owner.generation,
                candidate,
                result=emit.map(result => {
                  PreviewRefreshed(owner, candidate, result)
                }),
              ),
            )
        }
      }
    (Editing(editing), PreviewRefreshed(owner, candidate, result)) =>
      if owner != editing.activation || candidate != editing.text {
        (model, @cmd.none)
      } else {
        match result {
          Ok(output) =>
            (
              Editing({
                ..editing,
                preview: Ready(completed_preview(candidate, output)),
              }),
              @cmd.none,
            )
          Err(_) =>
            (
              Editing({
                ..editing,
                preview: Failed(preview_last(editing.preview)),
              }),
              @cmd.none,
            )
        }
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
    (Editing(editing), ViewportChanged(width)) =>
      (Editing({ ..editing, compact: compact_viewport(width) }), @cmd.none)
    (Recovery(failure, _), ViewportChanged(width)) =>
      (Recovery(failure, compact_viewport(width)), @cmd.none)
    (Editing(editing), SaveRequested(owner, candidate)) =>
      if owner != editing.activation ||
        candidate != editing.text ||
        editing.composing ||
        editing.creation == Creating {
        (model, @cmd.none)
      } else {
        match editing.save {
          Waiting => {
            let document_id = owner.document_id
            (
              Editing({ ..editing, save: Saving(candidate) }),
              @source_repository.save(
                editing.repository,
                document_id,
                candidate,
                result=emit.map(result => {
                  SaveCompleted(owner, candidate, result)
                }),
              ),
            )
          }
          Saved | Saving(_) | Failed(_) => (model, @cmd.none)
        }
      }
    (Editing(editing), SaveCompleted(owner, candidate, result)) =>
      if owner != editing.activation || editing.save != Saving(candidate) {
        (model, @cmd.none)
      } else {
        match result {
          @source_repository.SaveResult::Stored(success) => {
            let completed = { ..editing, repository: success }
            if candidate == editing.text {
              (Editing({ ..completed, save: Saved }), @cmd.none)
            } else if editing.composing {
              (Editing({ ..completed, save: Waiting }), @cmd.none)
            } else {
              let latest = editing.text
              (
                Editing({ ..completed, save: Saving(latest) }),
                @source_repository.save(
                  completed.repository,
                  owner.document_id,
                  latest,
                  result=emit.map(result => SaveCompleted(owner, latest, result)),
                ),
              )
            }
          }
          @source_repository.SaveResult::Failed(failure) =>
            (Editing({ ..editing, save: Failed(failure) }), @cmd.none)
        }
      }
    (Editing(editing), RetrySave) =>
      match editing.save {
        Failed(_) => {
          let latest = editing.text
          let owner = editing.activation
          (
            Editing({ ..editing, save: Saving(latest) }),
            @source_repository.save(
              editing.repository,
              owner.document_id,
              latest,
              result=emit.map(result => SaveCompleted(owner, latest, result)),
            ),
          )
        }
        Saved | Waiting | Saving(_) => (model, @cmd.none)
      }
    _ => (model, @cmd.none)
  }
}
