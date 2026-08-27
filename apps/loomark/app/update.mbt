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
fn mode_dom_id(mode : EditorMode) -> String {
  match mode {
    Text => "loomark-mode-text"
    Preview => "loomark-mode-preview"
    Split => "loomark-mode-split"
  }
}

///|
fn adjacent_mode(mode : EditorMode, key : String) -> EditorMode? {
  match (mode, key) {
    (Text, "ArrowLeft") => Some(Split)
    (Preview, "ArrowLeft") => Some(Text)
    (Split, "ArrowLeft") => Some(Preview)
    (Text, "ArrowRight") => Some(Preview)
    (Preview, "ArrowRight") => Some(Split)
    (Split, "ArrowRight") => Some(Text)
    _ => None
  }
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
        { ..editing, mode, focused_mode: mode, preview: Preparing },
        @preview.after_paint(emit(BeginPreviewPreparation)),
      )
    Failed(_) if entering_preview =>
      (
        { ..editing, mode, focused_mode: mode },
        @preview.refresh_cmd(
          preview_engine,
          editing.text,
          result=emit.map(result => PreviewRefreshed(editing.text, result)),
        ),
      )
    Unrequested | Preparing | Ready(_) | Failed(_) =>
      ({ ..editing, mode, focused_mode: mode }, @cmd.none)
  }
}

///|
fn initial_state(
  emit : @rabbita.Emit[Msg],
  compact : Bool,
) -> (Model, @rabbita.Cmd) {
  (
    Loading(compact),
    @browser_storage.open(result=emit.map(result => Opened(result))),
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
        @browser_storage.OpenResult::New(document_id) =>
          (
            Editing({
              document_id,
              text: "",
              composing: false,
              save: Saving(""),
              mode: Text,
              focused_mode: Text,
              compact,
              preview: Unrequested,
            }),
            @cmd.batch([
              text_area.initialize(""),
              @browser_storage.save(
                document_id,
                "",
                result=emit.map(result => SaveCompleted("", result)),
              ),
            ]),
          )
        @browser_storage.OpenResult::Loaded(document_id, text) =>
          (
            Editing({
              document_id,
              text,
              composing: false,
              save: Saved,
              mode: Text,
              focused_mode: Text,
              compact,
              preview: Unrequested,
            }),
            text_area.initialize(text),
          )
        @browser_storage.OpenResult::Failed(failure) =>
          (Recovery(failure, compact), @cmd.none)
      }
    (Editing(_), ExampleSelected(text)) =>
      (
        model,
        @cmd.batch([
          text_area.initialize(text),
          emit(TextChanged(@text_change.TextChange::ReplaceAll(text))),
        ]),
      )
    (Editing(editing), TextChanged(change)) =>
      match change.apply(editing.text) {
        None =>
          (
            model,
            text_area.value(text => {
              emit(TextChanged(@text_change.TextChange::ReplaceAll(text)))
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
            @cmd.delay(emit(SaveRequested(text)), AUTOSAVE_QUIET_MS)
          }
          let preview_command = match editing.preview {
            Unrequested | Preparing => @cmd.none
            Ready(_) =>
              @preview.apply_cmd(
                preview_engine,
                change,
                text,
                result=emit.map(result => ParserAdvanced(text, false, result)),
              )
            Failed(_) =>
              @preview.apply_cmd(
                preview_engine,
                change,
                text,
                result=emit.map(result => ParserAdvanced(text, true, result)),
              )
          }
          (
            Editing({ ..editing, text, save }),
            @cmd.batch([save_command, preview_command]),
          )
        }
      }
    (Editing(editing), CompositionStarted) =>
      (Editing({ ..editing, composing: true }), @cmd.none)
    (Editing(editing), CompositionEnded) => {
      let command = match editing.save {
        Waiting =>
          @cmd.delay(emit(SaveRequested(editing.text)), AUTOSAVE_QUIET_MS)
        Saved | Saving(_) | Failed(_) => @cmd.none
      }
      (Editing({ ..editing, composing: false }), command)
    }
    (Editing(editing), ModeSelected(mode)) => {
      let (editing, command) = select_mode(editing, mode, emit, preview_engine)
      (Editing(editing), command)
    }
    (Editing(editing), ModeKeyPressed(key)) =>
      match key {
        "Enter" | " " => {
          let (editing, command) = select_mode(
            editing,
            editing.focused_mode,
            emit,
            preview_engine,
          )
          (Editing(editing), command)
        }
        _ =>
          match adjacent_mode(editing.focused_mode, key) {
            Some(focused_mode) =>
              (
                Editing({ ..editing, focused_mode, }),
                @mode_tabs.focus(mode_dom_id(focused_mode)),
              )
            None => (model, @cmd.none)
          }
      }
    (Editing(editing), BeginPreviewPreparation) =>
      match editing.preview {
        Preparing =>
          (
            model,
            @preview.prepare_cmd(
              preview_engine,
              editing.text,
              result=emit.map(result => PreviewPrepared(editing.text, result)),
            ),
          )
        Unrequested | Ready(_) | Failed(_) => (model, @cmd.none)
      }
    (Editing(editing), PreviewPrepared(candidate, result)) =>
      if candidate != editing.text {
        (
          Editing({ ..editing, preview: Failed(None) }),
          @cmd.batch([
            @preview.discard_cmd(preview_engine),
            @cmd.delay(
              emit(PreviewRefreshRequested(editing.text)),
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
    (Editing(editing), ParserAdvanced(candidate, retry_on_failure, result)) =>
      match result {
        Ok(_) =>
          (
            model,
            @cmd.delay(
              emit(PreviewRefreshRequested(candidate)),
              PREVIEW_QUIET_MS,
            ),
          )
        Err(_) => {
          let command = if retry_on_failure {
            @cmd.delay(
              emit(PreviewRefreshRequested(candidate)),
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
    (Editing(editing), PreviewRefreshRequested(candidate)) =>
      if candidate != editing.text {
        (model, @cmd.none)
      } else {
        match editing.preview {
          Unrequested | Preparing => (model, @cmd.none)
          Ready(_) | Failed(_) =>
            (
              model,
              @preview.refresh_cmd(
                preview_engine,
                candidate,
                result=emit.map(result => PreviewRefreshed(candidate, result)),
              ),
            )
        }
      }
    (Editing(editing), PreviewRefreshed(candidate, result)) =>
      if candidate != editing.text {
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
    (Editing(editing), ViewportChanged(width)) =>
      (Editing({ ..editing, compact: compact_viewport(width) }), @cmd.none)
    (Recovery(failure, _), ViewportChanged(width)) =>
      (Recovery(failure, compact_viewport(width)), @cmd.none)
    (Editing(editing), SaveRequested(candidate)) =>
      if candidate != editing.text || editing.composing {
        (model, @cmd.none)
      } else {
        match editing.save {
          Waiting =>
            (
              Editing({ ..editing, save: Saving(candidate) }),
              @browser_storage.save(
                editing.document_id,
                candidate,
                result=emit.map(result => SaveCompleted(candidate, result)),
              ),
            )
          Saved | Saving(_) | Failed(_) => (model, @cmd.none)
        }
      }
    (Editing(editing), SaveCompleted(candidate, result)) =>
      match result {
        @browser_storage.SaveResult::Stored =>
          if candidate == editing.text {
            (Editing({ ..editing, save: Saved }), @cmd.none)
          } else if editing.composing {
            (Editing({ ..editing, save: Waiting }), @cmd.none)
          } else {
            let latest = editing.text
            (
              Editing({ ..editing, save: Saving(latest) }),
              @browser_storage.save(
                editing.document_id,
                latest,
                result=emit.map(result => SaveCompleted(latest, result)),
              ),
            )
          }
        @browser_storage.SaveResult::Failed(failure) =>
          (Editing({ ..editing, save: Failed(failure) }), @cmd.none)
      }
    (Editing(editing), RetrySave) =>
      match editing.save {
        Failed(_) => {
          let latest = editing.text
          (
            Editing({ ..editing, save: Saving(latest) }),
            @browser_storage.save(
              editing.document_id,
              latest,
              result=emit.map(result => SaveCompleted(latest, result)),
            ),
          )
        }
        Saved | Waiting | Saving(_) => (model, @cmd.none)
      }
    _ => (model, @cmd.none)
  }
}
