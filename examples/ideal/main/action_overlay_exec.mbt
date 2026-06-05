///|
/// Execute an action: build the tree edit op and apply it.
/// Returns (Cmd, Model) after execution.
fn execute_action(
  model : Model,
  action : @lambda_edits.Action,
  choice : String,
  name : String,
) -> (Cmd, Model) {
  let ctx = match model.overlay.node_context {
    Some(c) => c
    None => return (none, model)
  }
  match build_tree_edit_op(action.id, ctx, choice, name) {
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
            overlay: closed_overlay(),
          })
          let text = new_model.editor.get_text()
          let cmd = sync_after_local_model_change(new_model, text)
          (cmd, new_model)
        }
        Err(err) => {
          let overlay = { ..model.overlay, error: err.message() }
          (none, { ..model, overlay, })
        }
      }
    Ok(None) => show_name_prompt(model, action)
    Err(msg) => {
      let overlay = { ..model.overlay, error: msg }
      (none, { ..model, overlay, })
    }
  }
}
