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
/// Preview demand and presentation state retained in the Rabbita Model.
pub struct State {
  priv phase : Phase
  priv demanded : Bool
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
/// Inputs accepted by the deterministic Preview lifecycle core.
priv enum PreviewInputEvent {
  Activated
  Requested
  Suspended
  DocumentChanged(@text_change.TextChange)
  Complete(EventKind)
}

///|
/// Domain-specific work selected by the pure lifecycle core for the imperative
/// PreviewEngine shell. Rabbita Cmd remains the sole effect representation.
priv enum PreviewDecision {
  NoCommand
  ActivateGeneration(Int)
  BeginPreparationAfterPaint(Int)
  Prepare(Input)
  Apply(Input, @text_change.TextChange, Bool)
  Discard(Int)
  DiscardAndScheduleRefresh(Input)
  ScheduleRefresh(Input)
  Refresh(Input)
  Admit(PreviewOutput, State, State)
}

///|
priv struct PreviewTransition {
  state : State
  decision : PreviewDecision
}

///|
/// Deterministically select the next Preview state and shell work.
///
/// This boundary neither reads nor mutates PreviewEngine and performs no I/O.
fn preview_transition(
  state : State,
  current : Input,
  event : PreviewInputEvent,
) -> PreviewTransition {
  match event {
    Activated =>
      {
        state: { phase: Unrequested, demanded: false },
        decision: ActivateGeneration(current.generation),
      }
    Requested => {
      let demanded = { ..state, demanded: true }
      match state.phase {
        Unrequested =>
          {
            state: { phase: Preparing, demanded: true },
            decision: BeginPreparationAfterPaint(current.generation),
          }
        Failed(_) => { state: demanded, decision: Refresh(current) }
        Preparing => { state: demanded, decision: NoCommand }
        Ready(preview) =>
          if preview.document_text == current.document_text {
            { state: demanded, decision: NoCommand }
          } else {
            { state: demanded, decision: Refresh(current) }
          }
      }
    }
    Suspended =>
      if state.phase is Preparing {
        {
          state: { phase: Unrequested, demanded: false },
          decision: Discard(current.generation),
        }
      } else {
        { state: { ..state, demanded: false }, decision: NoCommand }
      }
    DocumentChanged(change) =>
      match state.phase {
        Unrequested | Preparing => { state, decision: NoCommand }
        Ready(_) => { state, decision: Apply(current, change, false) }
        Failed(_) => { state, decision: Apply(current, change, true) }
      }
    Complete(completion) =>
      match completion {
        BeginPreparation(generation) if generation == current.generation &&
          state.demanded &&
          state.phase is Preparing => { state, decision: Prepare(current) }
        Prepared(input, _) if input.generation == current.generation &&
          state.phase is Preparing &&
          input.document_text != current.document_text =>
          {
            state: { phase: Failed(None), demanded: state.demanded },
            decision: if state.demanded {
              DiscardAndScheduleRefresh(current)
            } else {
              Discard(current.generation)
            },
          }
        Prepared(input, result) if input == current && state.phase is Preparing =>
          match result {
            Ok(output) =>
              {
                state,
                decision: Admit(
                  output,
                  {
                    phase: Ready(completed_preview(input, output)),
                    demanded: state.demanded,
                  },
                  { phase: Failed(None), demanded: state.demanded },
                ),
              }
            Err(_) =>
              {
                state: { phase: Failed(None), demanded: state.demanded },
                decision: NoCommand,
              }
          }
        ParserAdvanced(input, retry, result) if input == current =>
          match result {
            Ok(_) =>
              {
                state,
                decision: if state.demanded {
                  ScheduleRefresh(input)
                } else {
                  NoCommand
                },
              }
            Err(_) =>
              {
                state: {
                  phase: Failed(last_preview(state.phase)),
                  demanded: state.demanded,
                },
                decision: if retry && state.demanded {
                  ScheduleRefresh(input)
                } else {
                  NoCommand
                },
              }
          }
        RefreshRequested(input) if input == current && state.demanded =>
          match state.phase {
            Ready(_) | Failed(_) => { state, decision: Refresh(input) }
            Unrequested | Preparing => { state, decision: NoCommand }
          }
        Refreshed(input, result) if input == current =>
          match result {
            Ok(output) =>
              {
                state,
                decision: Admit(
                  output,
                  {
                    phase: Ready(completed_preview(input, output)),
                    demanded: state.demanded,
                  },
                  state,
                ),
              }
            Err(_) =>
              {
                state: {
                  phase: Failed(last_preview(state.phase)),
                  demanded: state.demanded,
                },
                decision: NoCommand,
              }
          }
        _ => { state, decision: NoCommand }
      }
  }
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
/// Interpret one pure lifecycle decision in the imperative PreviewEngine shell.
fn PreviewEngine::execute(
  self : PreviewEngine,
  transition : PreviewTransition,
  emit : @cmd.Emit[Event],
) -> (State, @cmd.Cmd) {
  match transition.decision {
    NoCommand => (transition.state, @cmd.none)
    ActivateGeneration(generation) =>
      (transition.state, self.activate_command(generation))
    BeginPreparationAfterPaint(generation) =>
      (
        transition.state,
        after_paint(emit({ kind: BeginPreparation(generation) })),
      )
    Prepare(input) => (transition.state, self.prepare_command(input, emit))
    Apply(input, change, retry) =>
      (transition.state, self.apply_command(input, change, retry, emit))
    Discard(generation) => (transition.state, self.discard_command(generation))
    DiscardAndScheduleRefresh(input) =>
      (
        transition.state,
        @cmd.batch([
          self.discard_command(input.generation),
          @cmd.delay(emit({ kind: RefreshRequested(input) }), PREVIEW_QUIET_MS),
        ]),
      )
    ScheduleRefresh(input) =>
      (
        transition.state,
        @cmd.delay(emit({ kind: RefreshRequested(input) }), PREVIEW_QUIET_MS),
      )
    Refresh(input) => (transition.state, self.refresh_command(input, emit))
    Admit(output, accepted, rejected) =>
      (if self.accept(output) { accepted } else { rejected }, @cmd.none)
  }
}

///|
/// Activate Preview ownership for a selected Loomark document.
pub fn PreviewEngine::activate(
  self : PreviewEngine,
  input : Input,
) -> (State, @cmd.Cmd) {
  let transition = preview_transition(
    { phase: Unrequested, demanded: false },
    input,
    Activated,
  )
  match transition.decision {
    ActivateGeneration(generation) =>
      (transition.state, self.activate_command(generation))
    _ => (transition.state, @cmd.none)
  }
}

///|
/// Request Preview after Preview or Split becomes visible.
pub fn PreviewEngine::request(
  self : PreviewEngine,
  state : State,
  input : Input,
  emit : @cmd.Emit[Event],
) -> (State, @cmd.Cmd) {
  self.execute(preview_transition(state, input, Requested), emit)
}

///|
/// Stop Preview output work while retaining completed output and a healthy Parser.
pub fn PreviewEngine::suspend(
  self : PreviewEngine,
  state : State,
  input : Input,
) -> (State, @cmd.Cmd) {
  self.execute(
    preview_transition(state, input, Suspended),
    @cmd.Emit(_ => @cmd.none),
  )
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
  self.execute(preview_transition(state, input, DocumentChanged(change)), emit)
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
  self.execute(preview_transition(state, current, Complete(event.kind)), emit)
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
