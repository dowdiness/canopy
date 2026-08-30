///|
const PREVIEW_QUIET_MS : Int = 24

///|
/// Current app-owned facts needed by the Preview lifecycle.
///
/// Document text remains owned by the app Model. A captured Input identifies
/// the activation and text from which one Preview operation was requested; it
/// is not a request identity or a second text authority.
pub struct Input {
  priv generation : Int
  priv document_text : String
} derive(Eq)

///|
pub fn Input::Input(generation : Int, document_text : String) -> Input {
  { generation, document_text }
}

///|
priv struct RenderedPreview {
  document_text : String
  html : @rabbita.Html
  empty : Bool
} derive(Eq)

///|
priv enum Phase {
  Unrequested
  Preparing
  Ready(RenderedPreview)
  Failed(RenderedPreview?)
} derive(Eq)

///|
/// Plain Preview presentation state retained in the Rabbita Model.
pub struct State {
  priv phase : Phase
} derive(Eq)

///|
priv enum EventKind {
  BeginPreparation(Int)
  Prepared(Input, Result[PreviewOutput, PreviewFailure])
  ParserAdvanced(Input, Bool, Result[Unit, PreviewFailure])
  RefreshRequested(Input)
  Refreshed(Input, Result[PreviewOutput, PreviewFailure])
}

///|
/// Opaque completion from Preview commands back into the Rabbita update loop.
pub struct Event {
  priv kind : EventKind
}

///|
fn PreviewEngine::activate_command(
  self : PreviewEngine,
  generation : Int,
) -> @cmd.Cmd {
  @cmd.custom_cmd(_ => ignore(self.activate_generation(generation)))
}

///|
fn after_paint(command : @cmd.Cmd) -> @cmd.Cmd {
  @cmd.custom_cmd(kind=@cmd.after_render, scheduler => {
    ignore(
      @dom.window().request_animation_frame(_ => {
        ignore(@dom.window().set_timeout(() => scheduler.add(command), 0))
      }),
    )
  })
}

///|
fn PreviewEngine::prepare_command(
  self : PreviewEngine,
  input : Input,
  emit : @cmd.Emit[Event],
) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    if self.prepare_owned(input.generation, input.document_text) is Some(result) {
      scheduler.add(emit({ kind: Prepared(input, result) }))
    }
  })
}

///|
fn PreviewEngine::apply_command(
  self : PreviewEngine,
  input : Input,
  change : @text_change.TextChange,
  retry : Bool,
  emit : @cmd.Emit[Event],
) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    if self.apply_owned(input.generation, change, input.document_text)
      is Some(result) {
      scheduler.add(emit({ kind: ParserAdvanced(input, retry, result) }))
    }
  })
}

///|
fn PreviewEngine::refresh_command(
  self : PreviewEngine,
  input : Input,
  emit : @cmd.Emit[Event],
) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    if self.refresh_owned(input.generation, input.document_text) is Some(result) {
      scheduler.add(emit({ kind: Refreshed(input, result) }))
    }
  })
}

///|
fn PreviewEngine::discard_command(
  self : PreviewEngine,
  generation : Int,
) -> @cmd.Cmd {
  @cmd.custom_cmd(_ => ignore(self.discard_owned(generation)))
}

///|
/// Activate Preview ownership for a selected Loomark document.
pub fn PreviewEngine::activate(
  self : PreviewEngine,
  input : Input,
) -> (State, @cmd.Cmd) {
  ({ phase: Unrequested }, self.activate_command(input.generation))
}

///|
/// Request Preview after Preview or Split becomes visible.
pub fn PreviewEngine::request(
  self : PreviewEngine,
  state : State,
  input : Input,
  emit : @cmd.Emit[Event],
) -> (State, @cmd.Cmd) {
  match state.phase {
    Unrequested =>
      (
        { phase: Preparing },
        after_paint(emit({ kind: BeginPreparation(input.generation) })),
      )
    Failed(_) => (state, self.refresh_command(input, emit))
    Preparing | Ready(_) => (state, @cmd.none)
  }
}

///|
/// Advance the long-lived Parser immediately after one committed Document edit.
pub fn PreviewEngine::document_changed(
  self : PreviewEngine,
  state : State,
  input : Input,
  change : @text_change.TextChange,
  emit : @cmd.Emit[Event],
) -> (State, @cmd.Cmd) {
  match state.phase {
    Unrequested | Preparing => (state, @cmd.none)
    Ready(_) => (state, self.apply_command(input, change, false, emit))
    Failed(_) => (state, self.apply_command(input, change, true, emit))
  }
}

///|
/// Admit one Preview completion against the current app-owned Input.
pub fn PreviewEngine::update(
  self : PreviewEngine,
  state : State,
  current : Input,
  event : Event,
  emit : @cmd.Emit[Event],
) -> (State, @cmd.Cmd) {
  match event.kind {
    BeginPreparation(generation) if generation == current.generation &&
      state.phase is Preparing => (state, self.prepare_command(current, emit))
    Prepared(input, result) if input.generation == current.generation &&
      state.phase is Preparing =>
      if input.document_text != current.document_text {
        (
          { phase: Failed(None) },
          @cmd.batch([
            self.discard_command(current.generation),
            @cmd.delay(
              emit({ kind: RefreshRequested(current) }),
              PREVIEW_QUIET_MS,
            ),
          ]),
        )
      } else {
        match result {
          Ok(output) if self.accept(output) =>
            ({ phase: Ready(completed_preview(input, output)) }, @cmd.none)
          Ok(_) | Err(_) => ({ phase: Failed(None) }, @cmd.none)
        }
      }
    ParserAdvanced(input, retry, result) if input == current =>
      match result {
        Ok(_) =>
          (
            state,
            @cmd.delay(
              emit({ kind: RefreshRequested(input) }),
              PREVIEW_QUIET_MS,
            ),
          )
        Err(_) => {
          let command = if retry {
            @cmd.delay(
              emit({ kind: RefreshRequested(input) }),
              PREVIEW_QUIET_MS,
            )
          } else {
            @cmd.none
          }
          ({ phase: Failed(last_preview(state.phase)) }, command)
        }
      }
    RefreshRequested(input) if input == current =>
      match state.phase {
        Ready(_) | Failed(_) => (state, self.refresh_command(input, emit))
        Unrequested | Preparing => (state, @cmd.none)
      }
    Refreshed(input, result) if input == current =>
      match result {
        Ok(output) if self.accept(output) =>
          ({ phase: Ready(completed_preview(input, output)) }, @cmd.none)
        Ok(_) => (state, @cmd.none)
        Err(_) => ({ phase: Failed(last_preview(state.phase)) }, @cmd.none)
      }
    _ => (state, @cmd.none)
  }
}

///|
fn completed_preview(input : Input, output : PreviewOutput) -> RenderedPreview {
  { document_text: input.document_text, html: output.html, empty: output.empty }
}

///|
fn last_preview(phase : Phase) -> RenderedPreview? {
  match phase {
    Ready(preview) => Some(preview)
    Failed(preview) => preview
    Unrequested | Preparing => None
  }
}
