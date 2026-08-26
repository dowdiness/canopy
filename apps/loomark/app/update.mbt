///|
const AUTOSAVE_QUIET_MS : Int = 250

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
            }),
            text_area.initialize(text),
          )
        @browser_storage.OpenResult::Failed(failure) =>
          (Recovery(failure, compact), @cmd.none)
      }
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
          let command = if editing.composing {
            @cmd.none
          } else {
            @cmd.delay(emit(SaveRequested(text)), AUTOSAVE_QUIET_MS)
          }
          (Editing({ ..editing, text, save }), command)
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
    (Editing(editing), ModeSelected(mode)) =>
      (Editing({ ..editing, mode, focused_mode: mode }), @cmd.none)
    (Editing(editing), ModeKeyPressed(key)) =>
      match key {
        "Enter" | " " =>
          (Editing({ ..editing, mode: editing.focused_mode }), @cmd.none)
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
