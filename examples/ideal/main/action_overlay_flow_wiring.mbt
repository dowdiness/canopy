///|
fn overlay_effect_to_cmd(
  parent_emit : @rabbita.Emit[Msg],
  token : Int,
  result : OverlayUpdate,
) -> Cmd {
  match result.effect {
    NoOverlayEffect => none
    FocusMenu => result.state.menu.focus_cmd()
    FocusNamePrompt => focus_selector_after_render(".name-prompt-input")
    // Unconditional emit is safe: close() atomically clears both runtime and
    // context (and does NOT increment next_token), so queued outputs from a
    // closed overlay are caught by the parent's token guard in
    // handle_overlay_output. If close() is ever split into two steps, restore
    // the child-side guard here.
    ExecuteAction(action, choice~, name~) =>
      parent_emit(
        ActionOverlayEffect(
          OverlayOutput::ExecuteAction(token~, action, choice~, name~),
        ),
      )
    CloseOverlay =>
      parent_emit(ActionOverlayEffect(OverlayOutput::CloseOverlay(token~)))
  }
}

///|
fn overlay_cell_update(
  parent_emit : @rabbita.Emit[Msg],
  token : Int,
  _emit : @rabbita.Emit[OverlayMsg],
  msg : OverlayMsg,
  state : OverlayState,
) -> (Cmd, OverlayState) {
  let result = state.update(msg)
  (overlay_effect_to_cmd(parent_emit, token, result), result.state)
}

///|
fn create_overlay_cell(
  parent_emit : @rabbita.Emit[Msg],
  token : Int,
  initial_state : OverlayState,
) -> (@rabbita.Emit[OverlayMsg], @rabbita.Cell) {
  @rabbita.cell_with_emit(
    model=initial_state,
    update=fn(emit, msg, state) {
      overlay_cell_update(parent_emit, token, emit, msg, state)
    },
    view=fn(emit, state) { view_overlay(emit, state) },
  )
}
