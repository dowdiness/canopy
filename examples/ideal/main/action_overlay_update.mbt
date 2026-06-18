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
  match model.overlay_runtime {
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
fn current_overlay_runtime_for_output(
  runtime : ActionOverlayRuntime?,
  output : OverlayOutput,
) -> ActionOverlayRuntime? {
  match runtime {
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
      match current_overlay_runtime_for_output(model.overlay_runtime, output) {
        Some(runtime) =>
          execute_action(model, runtime, context, action, choice, name)
        None => (none, model)
      }
    CloseOverlay(..) =>
      match current_overlay_runtime_for_output(model.overlay_runtime, output) {
        Some(_) => close_action_overlay(model)
        None => (none, model)
      }
  }
}
