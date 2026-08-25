///|
const AUTOSAVE_QUIET_MS : Int = 250

///|
const TEXT_SURFACE_ID : String = "loomark-text"

///|
type PreparePreview = (String) -> @rabbita.Cmd

///|
type AdvancePreview = (@text_change.TextChange, String) -> @rabbita.Cmd

///|
type ResetPreview = (String) -> @rabbita.Cmd

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
    metrics: InputMetrics::initial(),
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
fn text_is_presented(display : DisplayLayout) -> Bool {
  match display {
    Preview => false
    Text | Split => true
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
fn save_after_edit(
  editing : EditingState,
  text : String,
  emit : @rabbita.Emit[Msg],
) -> (SaveState, @rabbita.Cmd) {
  let save = match editing.save {
    Saving(candidate) => Saving(candidate)
    _ => Waiting
  }
  (save, @cmd.delay(emit(SaveRequested(text)), AUTOSAVE_QUIET_MS))
}

///|
fn accept_edit(
  editing : EditingState,
  input_type : String,
  change : @text_change.TextChange,
  text : String,
  emit : @rabbita.Emit[Msg],
  prepare : PreparePreview,
  advance : AdvancePreview,
) -> (Model, @rabbita.Cmd) {
  let (save, save_command) = save_after_edit(editing, text, emit)
  let changed = {
    ..editing,
    text,
    composing: false,
    save,
    metrics: {
      ..editing.metrics,
      accepted_edits: editing.metrics.accepted_edits + 1,
      last_input_type: input_type,
    },
  }
  let (changed, preview_command) = request_visible_preview(changed, prepare)
  (
    Editing(changed),
    @cmd.batch([save_command, advance(change, text), preview_command]),
  )
}

///|
fn request_whole_value(
  editing : EditingState,
  reason : @text_edit.RecoveryReason,
  emit : @rabbita.Emit[Msg],
) -> (Model, @rabbita.Cmd) {
  (
    Editing({
      ..editing,
      metrics: {
        ..editing.metrics,
        recovery_count: editing.metrics.recovery_count + 1,
        last_recovery: reason.label(),
      },
    }),
    @text_surface.read(
      TEXT_SURFACE_ID,
      result=emit.map(text => WholeValueRead(reason, text)),
    ),
  )
}

///|
fn resolve_input(
  editing : EditingState,
  before : @text_edit.InputObservation,
  after : @text_edit.InputObservation,
  emit : @rabbita.Emit[Msg],
  prepare : PreparePreview,
  advance : AdvancePreview,
) -> (Model, @rabbita.Cmd) {
  let resolution = @text_edit.resolve(editing.text, before, after)
  match resolution {
    @text_edit.Resolution::Accepted(change, text) =>
      accept_edit(
        editing,
        before.input_type(),
        change,
        text,
        emit,
        prepare,
        advance,
      )
    @text_edit.Resolution::IgnoreComposition => (Editing(editing), @cmd.none)
    @text_edit.Resolution::Recover(reason) =>
      request_whole_value(editing, reason, emit)
  }
}

///|
fn update(
  model : Model,
  msg : Msg,
  emit : @rabbita.Emit[Msg],
  prepare : PreparePreview,
  advance : AdvancePreview,
  reset_preview : ResetPreview,
) -> (Model, @rabbita.Cmd) {
  match (model, msg) {
    (Loading, Opened(result)) =>
      match result {
        @browser_storage.OpenResult::New(document_id) => {
          let editing = editing_state(document_id, "", Saving(""))
          (
            Editing(editing),
            @cmd.batch([
              @text_surface.install(TEXT_SURFACE_ID, ""),
              reset_preview(""),
              @browser_storage.save(
                document_id,
                "",
                result=emit.map(result => SaveCompleted("", result)),
              ),
            ]),
          )
        }
        @browser_storage.OpenResult::Loaded(document_id, text) => {
          let editing = editing_state(document_id, text, Saved)
          (
            Editing(editing),
            @cmd.batch([
              @text_surface.install(TEXT_SURFACE_ID, text),
              reset_preview(text),
            ]),
          )
        }
        @browser_storage.OpenResult::Failed(failure) =>
          (Recovery(failure), @cmd.none)
      }
    (Editing(editing), BeforeInputCaptured(observation)) => {
      let editing = {
        ..editing,
        metrics: {
          ..editing.metrics,
          value_length_reads: editing.metrics.value_length_reads + 1,
        },
      }
      ignore(observation)
      (Editing(editing), @cmd.none)
    }
    (Editing(editing), InputCaptured(before, observation)) => {
      let editing = {
        ..editing,
        metrics: {
          ..editing.metrics,
          value_length_reads: editing.metrics.value_length_reads + 1,
        },
      }
      if editing.composing {
        (Editing(editing), @cmd.none)
      } else {
        match before {
          Some(before) =>
            resolve_input(editing, before, observation, emit, prepare, advance)
          None =>
            request_whole_value(
              editing,
              @text_edit.missing_before_input(),
              emit,
            )
        }
      }
    }
    (Editing(editing), CompositionStarted) =>
      (
        Editing({
          ..editing,
          composing: true,
          metrics: {
            ..editing.metrics,
            value_length_reads: editing.metrics.value_length_reads + 1,
          },
        }),
        @cmd.none,
      )
    (Editing(editing), CompositionEnded(started, observation)) => {
      let editing = {
        ..editing,
        composing: false,
        metrics: {
          ..editing.metrics,
          value_length_reads: editing.metrics.value_length_reads + 1,
        },
      }
      match started {
        None =>
          request_whole_value(editing, @text_edit.missing_before_input(), emit)
        Some(started) => {
          let resolution = @text_edit.resolve_composition(
            editing.text,
            started,
            observation,
          )
          match resolution {
            @text_edit.Resolution::Accepted(change, text) =>
              accept_edit(
                editing, "insertCompositionText", change, text, emit, prepare, advance,
              )
            @text_edit.Resolution::IgnoreComposition =>
              (Editing(editing), @cmd.none)
            @text_edit.Resolution::Recover(reason) =>
              request_whole_value(editing, reason, emit)
          }
        }
      }
    }
    (Editing(editing), WholeValueRead(reason, value)) => {
      let metrics = {
        ..editing.metrics,
        complete_value_reads: editing.metrics.complete_value_reads + 1,
        last_recovery: reason.label(),
      }
      match value {
        None => (Editing({ ..editing, metrics, }), @cmd.none)
        Some(text) => {
          let (save, save_command) = save_after_edit(editing, text, emit)
          let recovered = {
            ..editing,
            text,
            composing: false,
            save,
            metrics,
            preview: PreviewState::initial(),
          }
          let (recovered, preview_command) = request_visible_preview(
            recovered, prepare,
          )
          (
            Editing(recovered),
            @cmd.batch([reset_preview(text), save_command, preview_command]),
          )
        }
      }
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
      let (selected, preview_command) = request_visible_preview(
        selected, prepare,
      )
      let install_command = if text_is_presented(display) {
        @text_surface.install(TEXT_SURFACE_ID, selected.text)
      } else {
        @cmd.none
      }
      (Editing(selected), @cmd.batch([preview_command, install_command]))
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
