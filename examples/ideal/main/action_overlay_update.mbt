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
  match model.overlay.runtime {
    Some(runtime) => (runtime.send(overlay_event.to_overlay_msg()), model)
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
fn ActionOverlayHost::current_runtime_for_output(
  self : ActionOverlayHost,
  output : OverlayOutput,
) -> ActionOverlayRuntime? {
  match self.runtime {
    Some(runtime) =>
      if runtime.token == output.token() {
        Some(runtime)
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
    ExecuteAction(context~, action, choice~, name~, ..) =>
      match model.overlay.current_runtime_for_output(output) {
        Some(runtime) =>
          execute_action(model, runtime, context, action, choice, name)
        None => (none, model)
      }
    CloseOverlay(..) =>
      match model.overlay.current_runtime_for_output(output) {
        Some(_) => close_action_overlay(model)
        None => (none, model)
      }
  }
}
