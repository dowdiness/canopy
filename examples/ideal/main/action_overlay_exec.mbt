///|
/// Execute an action: build the tree edit op and apply it.
/// Returns (Cmd, Model) after execution.
fn execute_action(
  model : Model,
  runtime : ActionOverlayRuntime,
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
          (runtime.send(SetError(ApplyActionFailed(err.message()))), model)
      }
    Ok(None) => (runtime.send(ShowNamePrompt(action)), model)
    Err(msg) => (runtime.send(SetError(BuildActionFailed(msg))), model)
  }
}
