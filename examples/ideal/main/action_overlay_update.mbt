///|
fn OverlayEvent::to_overlay_msg(self : OverlayEvent) -> OverlayMsg {
  match self {
    OverlayKeyPressed(key) => KeyPressed(key)
    OverlayNameCancel => NameCancel
  }
}

///|
fn handle_overlay_event(
  model : Model,
  overlay_event : OverlayEvent,
) -> (Cmd, Model) {
  match model.overlay.active {
    Some((_, runtime)) => (runtime.send(overlay_event.to_overlay_msg()), model)
    None => (none, model)
  }
}

///|
fn OverlayOutput::token(self : OverlayOutput) -> Int {
  match self {
    ExecuteAction(token~, _, ..) | CloseOverlay(token~) => token
  }
}

///|
fn ActionOverlayHost::active_for_output(
  self : ActionOverlayHost,
  output : OverlayOutput,
) -> (@lambda_edits.ActionContext, ActionOverlayRuntime)? {
  match self.active {
    Some((context, runtime)) =>
      if runtime.token == output.token() {
        Some((context, runtime))
      } else {
        None
      }
    None => None
  }
}

///|
/// Apply child-cell outputs only when they come from the currently mounted
/// overlay runtime. This prevents delayed outputs from a closed/reopened
/// overlay from executing against the wrong node context.
fn handle_overlay_output(model : Model, output : OverlayOutput) -> (Cmd, Model) {
  match output {
    ExecuteAction(action, choice~, name~, ..) => {
      guard model.overlay.active_for_output(output) is Some((context, runtime)) else {
        return (none, model)
      }
      execute_action(model, runtime, context, action, choice, name)
    }
    CloseOverlay(..) =>
      match model.overlay.active_for_output(output) {
        Some(_) => close_action_overlay(model)
        None => (none, model)
      }
  }
}
