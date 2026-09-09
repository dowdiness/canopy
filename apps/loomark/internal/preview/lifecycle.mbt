///|
const PREVIEW_QUIET_MS : Int = 24

///|
/// A captured read of app-owned Document text, not another text authority.
pub struct Input {
  priv generation : Int
  priv document_text : String
  priv composing : Bool
} derive(Eq)

///|
pub fn Input::Input(
  generation : Int,
  document_text : String,
  composing? : Bool = false,
) -> Input {
  { generation, document_text, composing }
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
/// One pending wake and at most one exact edit. Dirty + None denotes replacement
/// fallback, not an empty edit. Revisions contain no captured source text.
pub struct State {
  priv phase : Phase
  priv demanded : Bool
  priv dirty : Bool
  priv pending_change : @text_change.TextChange?
  priv revision : Int
  priv scheduled_revision : Int
  priv wake_ticket : Int
  priv wake_scheduled : Bool
  priv busy : Bool
} derive(Eq)

///|
priv enum EventKind {
  BeginPreparation(Int, Int)
  Prepared(Input, Result[PreviewOutput, PreviewFailure])
  Wakeup(Int, Int)
  Refreshed(Input, Result[PreviewOutput, PreviewFailure])
}

///|
pub struct Event {
  priv kind : EventKind
}

///|
priv enum PreviewInputEvent {
  Activated
  Requested
  Suspended
  CompositionStarted
  CompositionEnded
  DocumentChanged(@text_change.TextChange)
  Complete(EventKind)
}

///|
priv enum PreviewDecision {
  NoCommand
  ActivateGeneration(Int)
  BeginPreparationAfterPaint(Int, Int)
  BeginRefreshAfterPaint(Int, Int)
  Prepare(Input)
  CatchUp(Input, @text_change.TextChange?)
  Discard(Int)
  ScheduleWake(Int, Int)
  Admit(PreviewOutput, State, State)
}

///|
priv struct PreviewTransition {
  state : State
  decision : PreviewDecision
}

///|
fn initial_state() -> State {
  {
    phase: Unrequested,
    demanded: false,
    dirty: false,
    pending_change: None,
    revision: 0,
    scheduled_revision: 0,
    wake_ticket: 0,
    wake_scheduled: false,
    busy: false,
  }
}

///|
/// Select one text-free wake. This is a pure lifecycle decision, not a queue.
fn queue_refresh(
  state : State,
  current : Input,
  paint_first? : Bool = false,
) -> PreviewTransition {
  if !state.demanded || current.composing || state.wake_scheduled || state.busy {
    { state, decision: NoCommand }
  } else {
    let ticket = state.wake_ticket + 1
    {
      state: {
        ..state,
        wake_ticket: ticket,
        wake_scheduled: true,
        scheduled_revision: state.revision,
      },
      decision: if paint_first {
        BeginRefreshAfterPaint(current.generation, ticket)
      } else {
        ScheduleWake(current.generation, ticket)
      },
    }
  }
}

///|
fn preview_transition(
  state : State,
  current : Input,
  event : PreviewInputEvent,
) -> PreviewTransition {
  let state = match event {
    Complete(Prepared(input, _) | Refreshed(input, _)) if input.generation ==
      current.generation => { ..state, busy: false }
    _ => state
  }
  match event {
    Activated =>
      {
        state: initial_state(),
        decision: ActivateGeneration(current.generation),
      }
    Requested => {
      let demanded = { ..state, demanded: true }
      if current.composing || state.busy {
        { state: demanded, decision: NoCommand }
      } else {
        match state.phase {
          Unrequested => {
            let ticket = state.wake_ticket + 1
            {
              state: {
                ..demanded,
                phase: Preparing,
                wake_ticket: ticket,
                wake_scheduled: true,
              },
              decision: BeginPreparationAfterPaint(current.generation, ticket),
            }
          }
          Preparing => { state: demanded, decision: NoCommand }
          Ready(preview) if preview.document_text == current.document_text &&
            !state.dirty => { state: demanded, decision: NoCommand }
          Ready(_) | Failed(_) =>
            queue_refresh(demanded, current, paint_first=true)
        }
      }
    }
    Suspended | CompositionStarted => {
      let preparing = state.phase is Preparing
      {
        state: {
          ..state,
          phase: if preparing {
            Unrequested
          } else {
            state.phase
          },
          demanded: if event is Suspended {
            false
          } else {
            state.demanded
          },
          wake_ticket: state.wake_ticket + 1,
          wake_scheduled: false,
        },
        decision: if preparing {
          Discard(current.generation)
        } else {
          NoCommand
        },
      }
    }
    CompositionEnded =>
      if !state.demanded {
        { state, decision: NoCommand }
      } else {
        match state.phase {
          Unrequested => preview_transition(state, current, Requested)
          Preparing => { state, decision: NoCommand }
          Ready(preview) if !state.dirty &&
            preview.document_text == current.document_text =>
            { state, decision: NoCommand }
          Ready(_) | Failed(_) => queue_refresh(state, current)
        }
      }
    DocumentChanged(change) =>
      match state.phase {
        Unrequested => { state, decision: NoCommand }
        Preparing =>
          {
            state: {
              ..state,
              dirty: true,
              revision: state.revision + 1,
              pending_change: None,
            },
            decision: NoCommand,
          }
        Ready(_) | Failed(_) => {
          let next = {
            ..state,
            dirty: true,
            revision: state.revision + 1,
            pending_change: if state.dirty {
              None
            } else {
              Some(change)
            },
          }
          queue_refresh(next, current)
        }
      }
    Complete(completion) =>
      match completion {
        BeginPreparation(generation, ticket) if generation == current.generation &&
          state.phase is Preparing &&
          state.demanded &&
          state.wake_scheduled &&
          ticket == state.wake_ticket &&
          !current.composing =>
          {
            state: { ..state, wake_scheduled: false, busy: true },
            decision: Prepare(current),
          }
        Wakeup(generation, ticket) if generation == current.generation &&
          state.demanded &&
          state.wake_scheduled &&
          ticket == state.wake_ticket => {
          let awake = { ..state, wake_scheduled: false }
          if current.composing {
            { state: awake, decision: NoCommand }
          } else if state.revision != state.scheduled_revision {
            // Input changed while the existing timer was pending. Wait a full
            // quiet interval without allocating another timer on each input.
            queue_refresh(awake, current)
          } else {
            {
              state: { ..awake, busy: true },
              decision: CatchUp(current, state.pending_change),
            }
          }
        }
        Prepared(input, _) if input.generation == current.generation &&
          state.phase is Preparing &&
          input != current => {
          // A captured result cannot strand preparation. Retry by reading the
          // latest app input after paint; catch_up also handles a stale cache.
          let retry = {
            ..state,
            phase: Unrequested,
            wake_scheduled: false,
            wake_ticket: state.wake_ticket + 1,
          }
          if state.demanded && !current.composing {
            preview_transition(retry, current, Requested)
          } else {
            { state: retry, decision: NoCommand }
          }
        }
        Prepared(input, _) if input.generation == current.generation &&
          (state.phase is Unrequested || current.composing || !state.demanded) =>
          if state.demanded && !current.composing {
            preview_transition(state, current, Requested)
          } else {
            { state, decision: NoCommand }
          }
        Prepared(input, result) if input == current &&
          state.phase is Preparing &&
          state.demanded &&
          !current.composing =>
          match result {
            Ok(output) => {
              let accepted = {
                ..state,
                phase: Ready(completed_preview(input, output)),
                dirty: false,
                pending_change: None,
                wake_scheduled: false,
                wake_ticket: state.wake_ticket + 1,
                busy: false,
              }
              { state, decision: Admit(output, accepted, state) }
            }
            Err(_) =>
              {
                state: {
                  ..state,
                  phase: Failed(None),
                  wake_scheduled: false,
                  busy: false,
                },
                decision: NoCommand,
              }
          }
        Refreshed(input, _) if input.generation == current.generation &&
          (input != current || current.composing || !state.demanded) =>
          queue_refresh({ ..state, pending_change: None }, current)
        Refreshed(input, result) if input == current &&
          state.demanded &&
          !current.composing =>
          match result {
            Ok(output) => {
              let accepted = {
                ..state,
                phase: Ready(completed_preview(input, output)),
                dirty: false,
                pending_change: None,
                wake_scheduled: false,
                wake_ticket: state.wake_ticket + 1,
                busy: false,
              }
              { state, decision: Admit(output, accepted, state) }
            }
            Err(_) =>
              {
                state: {
                  ..state,
                  phase: Failed(last_preview(state.phase)),
                  wake_scheduled: false,
                  busy: false,
                },
                decision: NoCommand,
              }
          }
        _ => { state, decision: NoCommand }
      }
  }
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
    guard self.owns(input.generation) else { return }
    if self.worker_mode {
      let sequence = self.worker_sequence
      self.worker_sequence += 1
      preview_worker_request(
        self.worker_client,
        input.generation,
        sequence,
        input.document_text,
        "null",
        text => {
          scheduler.add(
            emit({
              kind: Prepared(input, self.worker_output(input, sequence, text)),
            }),
          )
        },
      )
    } else if self.prepare_owned(input.generation, input.document_text)
      is Some(result) {
      scheduler.add(emit({ kind: Prepared(input, result) }))
    }
  })
}

///|
fn PreviewEngine::catch_up_command(
  self : PreviewEngine,
  input : Input,
  change : @text_change.TextChange?,
  emit : @cmd.Emit[Event],
) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    guard self.owns(input.generation) else { return }
    if self.worker_mode {
      let sequence = self.worker_sequence
      self.worker_sequence += 1
      preview_worker_request(
        self.worker_client,
        input.generation,
        sequence,
        input.document_text,
        worker_edit_json(change),
        text => {
          scheduler.add(
            emit({
              kind: Refreshed(input, self.worker_output(input, sequence, text)),
            }),
          )
        },
      )
    } else if self.catch_up_owned(input.generation, input.document_text, change)
      is Some(result) {
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
fn PreviewEngine::execute(
  self : PreviewEngine,
  transition : PreviewTransition,
  emit : @cmd.Emit[Event],
) -> (State, @cmd.Cmd) {
  match transition.decision {
    NoCommand => (transition.state, @cmd.none)
    ActivateGeneration(g) =>
      (
        transition.state,
        @cmd.custom_cmd(_ => ignore(self.activate_generation(g))),
      )
    BeginPreparationAfterPaint(g, t) =>
      (transition.state, after_paint(emit({ kind: BeginPreparation(g, t) })))
    BeginRefreshAfterPaint(g, t) =>
      (transition.state, after_paint(emit({ kind: Wakeup(g, t) })))
    Prepare(input) => (transition.state, self.prepare_command(input, emit))
    CatchUp(input, change) =>
      (transition.state, self.catch_up_command(input, change, emit))
    Discard(g) => (transition.state, self.discard_command(g))
    ScheduleWake(g, t) =>
      (
        transition.state,
        @cmd.delay(emit({ kind: Wakeup(g, t) }), PREVIEW_QUIET_MS),
      )
    Admit(output, accepted, rejected) => {
      let did_accept = self.accept(output)
      if self.worker_mode {
        preview_worker_ack(self.worker_client, did_accept)
      }
      (if did_accept { accepted } else { rejected }, @cmd.none)
    }
  }
}

///|
pub fn PreviewEngine::activate(
  self : PreviewEngine,
  input : Input,
) -> (State, @cmd.Cmd) {
  self.execute(
    preview_transition(initial_state(), input, Activated),
    @cmd.Emit(_ => @cmd.none),
  )
}

///|
pub fn PreviewEngine::request(
  self : PreviewEngine,
  state : State,
  input : Input,
  emit : @cmd.Emit[Event],
) -> (State, @cmd.Cmd) {
  self.execute(preview_transition(state, input, Requested), emit)
}

///|
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
pub fn PreviewEngine::composition_started(
  self : PreviewEngine,
  state : State,
  input : Input,
) -> (State, @cmd.Cmd) {
  self.execute(
    preview_transition(state, input, CompositionStarted),
    @cmd.Emit(_ => @cmd.none),
  )
}

///|
pub fn PreviewEngine::composition_ended(
  self : PreviewEngine,
  state : State,
  input : Input,
  emit : @cmd.Emit[Event],
) -> (State, @cmd.Cmd) {
  self.execute(preview_transition(state, input, CompositionEnded), emit)
}

///|
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
pub fn PreviewEngine::update(
  self : PreviewEngine,
  state : State,
  current : Input,
  event : Event,
  emit : @cmd.Emit[Event],
) -> (State, @cmd.Cmd) {
  let result = self.execute(
    preview_transition(state, current, Complete(event.kind)),
    emit,
  )
  if self.worker_mode {
    match event.kind {
      Prepared(input, _) | Refreshed(input, _) if input.generation ==
        current.generation => {
        preview_worker_ack(self.worker_client, false)
        self.pending_render = None
      }
      _ => ()
    }
  }
  result
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
