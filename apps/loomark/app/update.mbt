///|
const AUTOSAVE_QUIET_MS : Int = 250

///|
fn initial_state(emit : @rabbita.Emit[Msg]) -> (Model, @rabbita.Cmd) {
  (Loading, @browser_storage.open(result=emit.map(result => Opened(result))))
}

///|
fn update(
  model : Model,
  msg : Msg,
  emit : @rabbita.Emit[Msg],
  text_area : @text_area.TextArea,
) -> (Model, @rabbita.Cmd) {
  match (model, msg) {
    (Loading, Opened(result)) =>
      match result {
        @browser_storage.OpenResult::New(document_id) =>
          (
            Editing({
              document_id,
              text: "",
              composing: false,
              save: Saving(""),
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
            Editing({ document_id, text, composing: false, save: Saved }),
            text_area.initialize(text),
          )
        @browser_storage.OpenResult::Failed(failure) =>
          (Recovery(failure), @cmd.none)
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
