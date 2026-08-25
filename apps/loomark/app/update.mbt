///|
const AUTOSAVE_QUIET_MS : Int = 250

///|
type PreparePreview = (String) -> @rabbita.Cmd

///|
fn editing_state(
  document_id : String,
  text : String,
  save : SaveState,
) -> EditingState {
  {
    document_id,
    text,
    composing: false,
    save,
    display: Text,
    preview: PreviewState::initial(),
    initial_text_focus: true,
  }
}

///|
fn initial_state(emit : @rabbita.Emit[Msg]) -> (Model, @rabbita.Cmd) {
  (Loading, @browser_storage.open(result=emit.map(result => Opened(result))))
}

///|
fn preview_is_presented(display : DisplayLayout) -> Bool {
  match display {
    Text => false
    Preview | Split => true
  }
}

///|
fn request_preview(
  editing : EditingState,
  prepare : PreparePreview,
) -> (EditingState, @rabbita.Cmd) {
  guard !editing.composing else { return (editing, @cmd.none) }
  guard editing.preview.preparing_input is None else {
    return (editing, @cmd.none)
  }
  match editing.preview.last_completed {
    Some(result) if result.input_text() == editing.text =>
      return (editing, @cmd.none)
    _ => ()
  }
  guard editing.preview.failed_input != Some(editing.text) else {
    return (editing, @cmd.none)
  }
  let input_text = editing.text
  (
    {
      ..editing,
      preview: {
        ..editing.preview,
        preparing_input: Some(input_text),
        failed_input: None,
        failure: None,
      },
    },
    prepare(input_text),
  )
}

///|
fn request_visible_preview(
  editing : EditingState,
  prepare : PreparePreview,
) -> (EditingState, @rabbita.Cmd) {
  if preview_is_presented(editing.display) {
    request_preview(editing, prepare)
  } else {
    (editing, @cmd.none)
  }
}

///|
fn update(
  model : Model,
  msg : Msg,
  emit : @rabbita.Emit[Msg],
  prepare : PreparePreview,
) -> (Model, @rabbita.Cmd) {
  match (model, msg) {
    (Loading, Opened(result)) =>
      match result {
        @browser_storage.OpenResult::New(document_id) =>
          (
            Editing(editing_state(document_id, "", Saving(""))),
            @browser_storage.save(
              document_id,
              "",
              result=emit.map(result => SaveCompleted("", result)),
            ),
          )
        @browser_storage.OpenResult::Loaded(document_id, text) =>
          (Editing(editing_state(document_id, text, Saved)), @cmd.none)
        @browser_storage.OpenResult::Failed(failure) =>
          (Recovery(failure), @cmd.none)
      }
    (Editing(editing), TextChanged(text)) => {
      let save = match editing.save {
        Saving(candidate) => Saving(candidate)
        _ => Waiting
      }
      let save_command = if editing.composing {
        @cmd.none
      } else {
        @cmd.delay(emit(SaveRequested(text)), AUTOSAVE_QUIET_MS)
      }
      let changed = { ..editing, text, save }
      let (changed, preview_command) = request_visible_preview(changed, prepare)
      (Editing(changed), @cmd.batch([save_command, preview_command]))
    }
    (Editing(editing), CompositionStarted) =>
      (Editing({ ..editing, composing: true }), @cmd.none)
    (Editing(editing), CompositionEnded) => {
      let save_command = match editing.save {
        Waiting =>
          @cmd.delay(emit(SaveRequested(editing.text)), AUTOSAVE_QUIET_MS)
        Saved | Saving(_) | Failed(_) => @cmd.none
      }
      let (editing, preview_command) = request_visible_preview(
        { ..editing, composing: false },
        prepare,
      )
      (Editing(editing), @cmd.batch([save_command, preview_command]))
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
    (Editing(editing), DisplaySelected(display)) => {
      let selected = { ..editing, display, initial_text_focus: false }
      let (selected, command) = request_visible_preview(selected, prepare)
      (Editing(selected), command)
    }
    (Editing(editing), PreviewIntent) => {
      let (editing, command) = request_preview(editing, prepare)
      (Editing(editing), command)
    }
    (Editing(editing), PreviewPrepared(input_text, result)) => {
      guard editing.preview.preparing_input == Some(input_text) else {
        return (model, @cmd.none)
      }
      match result {
        Ok(result) => {
          let completed = {
            ..editing,
            preview: {
              last_completed: Some(result),
              preparing_input: None,
              failed_input: None,
              failure: None,
            },
          }
          let (completed, next_command) = request_visible_preview(
            completed, prepare,
          )
          (
            Editing(completed),
            @cmd.batch([@preview.record_after_render(result), next_command]),
          )
        }
        Err(failure) => {
          let current_failure = input_text == editing.text
          let failed = {
            ..editing,
            preview: {
              ..editing.preview,
              preparing_input: None,
              failed_input: if current_failure {
                Some(input_text)
              } else {
                None
              },
              failure: if current_failure {
                Some(failure)
              } else {
                None
              },
            },
          }
          let (failed, next_command) = request_visible_preview(failed, prepare)
          (Editing(failed), next_command)
        }
      }
    }
    _ => (model, @cmd.none)
  }
}
