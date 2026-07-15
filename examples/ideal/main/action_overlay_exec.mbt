///|
/// Execute an action: build the tree edit op and apply it.
/// Returns (Cmd, Model) after execution.
fn execute_action(
  model : Model,
  context : @lambda_edits.ActionContext,
  action : @lambda_edits.Action,
  choice : String,
  name : String,
) -> (Cmd, Model) {
  match @lambda_edits.build_tree_edit_op(action.id, context, choice, name) {
    Ok(Some(op)) =>
      match commit_tree_edit(model, op) {
        Ok((cmd, new_model)) => {
          js_set_overlay_open(false)
          (cmd, { ..new_model, overlay: model.overlay.close() })
        }
        Err(err) =>
          match model.overlay.active {
            Some((_, state, _)) =>
              (
                none,
                {
                  ..model,
                  overlay: model.overlay.set_state(
                    state.with_error(
                      Some(
                        @overlay.OverlayError::ApplyActionFailed(err.message()),
                      ),
                    ),
                  ),
                },
              )
            None => (none, model)
          }
      }
    Ok(None) =>
      match model.overlay.active {
        Some((_, state, _)) => {
          let result = state.show_name_prompt(action)
          (
            focus_selector_after_render(NAME_PROMPT_SELECTOR),
            { ..model, overlay: model.overlay.set_state(result.state) },
          )
        }
        None => (none, model)
      }
    Err(msg) =>
      match model.overlay.active {
        Some((_, state, _)) =>
          (
            none,
            {
              ..model,
              overlay: model.overlay.set_state(
                state.with_error(
                  Some(@overlay.OverlayError::BuildActionFailed(msg)),
                ),
              ),
            },
          )
        None => (none, model)
      }
  }
}
