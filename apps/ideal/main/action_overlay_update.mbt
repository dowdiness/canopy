///|
const NAME_PROMPT_SELECTOR = ".name-prompt-input"

///|
fn OverlayEvent::to_overlay_msg(self : OverlayEvent) -> OverlayMsg {
  match self {
    OverlayKeyPressed(key) => KeyPressed(key)
    OverlayNameCancel => NameCancel
  }
}

///|
fn overlay_effect_to_cmd(
  parent_emit : @rabbita.Emit[Msg],
  token : Int,
  state : OverlayState,
  effect : OverlayEffect,
) -> Cmd {
  match effect {
    NoOverlayEffect => none
    FocusMenu => state.menu_model().focus_cmd()
    FocusNamePrompt => focus_selector_after_render(NAME_PROMPT_SELECTOR)
    ExecuteAction(action, choice~, name~) =>
      parent_emit(
        ActionOverlayEffect(
          token~,
          OverlayOutput::ExecuteAction(action, choice~, name~),
        ),
      )
    CloseOverlay =>
      parent_emit(ActionOverlayEffect(token~, OverlayOutput::CloseOverlay))
  }
}

///|
fn handle_overlay_msg(
  parent_emit : @rabbita.Emit[Msg],
  token : Int,
  msg : OverlayMsg,
  model : Model,
) -> (Cmd, Model) {
  match model.overlay.active_for_token(token) {
    Some((_, state, active_token)) => {
      let result = state.update(msg)
      let updated = { ..model, overlay: model.overlay.set_state(result.state) }
      let cmd = overlay_effect_to_cmd(
        parent_emit,
        active_token,
        result.state,
        result.effect,
      )
      (cmd, updated)
    }
    None => (none, model)
  }
}

///|
fn handle_overlay_event(
  parent_emit : @rabbita.Emit[Msg],
  model : Model,
  overlay_event : OverlayEvent,
) -> (Cmd, Model) {
  match model.overlay.active {
    Some((_, _, token)) =>
      handle_overlay_msg(
        parent_emit,
        token,
        overlay_event.to_overlay_msg(),
        model,
      )
    None => (none, model)
  }
}

///|

///|
/// Apply a parent-stamped overlay effect only when it belongs to the currently
/// mounted overlay session. Delayed effects from a closed/reopened session are
/// ignored.
fn handle_overlay_output(
  model : Model,
  token : Int,
  output : OverlayOutput,
) -> (Cmd, Model) {
  guard model.overlay.active_for_token(token) is Some((context, _, _)) else {
    return (none, model)
  }
  match output {
    ExecuteAction(action, choice~, name~) =>
      execute_action(model, context, action, choice, name)
    CloseOverlay => close_action_overlay(model)
  }
}
