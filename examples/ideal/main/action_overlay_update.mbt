///|
fn apply_overlay_effect(model : Model, effect : OverlayEffect) -> (Cmd, Model) {
  match effect {
    NoOverlayEffect => (none, model)
    FocusMenu => (model.overlay.menu.focus_cmd(), model)
    FocusNamePrompt =>
      (focus_selector_after_render(".name-prompt-input"), model)
    ExecuteAction(action, choice~, name~) =>
      execute_action(model, action, choice, name)
    CloseOverlay => close_action_overlay(model)
  }
}

///|
fn handle_overlay_msg(model : Model, overlay_msg : OverlayMsg) -> (Cmd, Model) {
  let result = model.overlay.update(overlay_msg)
  apply_overlay_effect({ ..model, overlay: result.state }, result.effect)
}
