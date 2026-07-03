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
      match
        @lambda.apply_lambda_tree_edit(
          model.editor,
          model.companion,
          op,
          js_now_ms(),
        ) {
        Ok(edits) => {
          push_intent(model, op)
          push_patch(model, op, edits)
          js_set_overlay_open(false)
          let new_model = refresh({
            ..model,
            next_timestamp: model.next_timestamp + 1,
            overlay: model.overlay.close(),
          })
          let text = new_model.editor.get_text()
          let cmd = sync_after_local_model_change(new_model, text)
          (cmd, new_model)
        }
        Err(err) =>
          (runtime.send(SetError(ApplyActionFailed(err.message()))), model)
      }
    Ok(None) => (runtime.send(ShowNamePrompt(action)), model)
    Err(msg) => (runtime.send(SetError(BuildActionFailed(msg))), model)
  }
}
