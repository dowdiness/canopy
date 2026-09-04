///|
fn handle_structure_mode(
  emit : Emit[Msg],
  msg : Msg,
  model : Model,
) -> (Cmd, Model)? raise {
  let _ = emit
  match msg {
    StructureNodeSelected(node_id) =>
      if node_id == "" {
        Some((none, model))
      } else {
        let selected = select_with_highlight(model, Some(node_id), true)
        Some((none, selected))
      }
    StructureTreeEdit(generation~, tree_op) =>
      if model.mode != Structure || generation != model.structure_generation {
        Some((none, model))
      } else {
        match tree_op {
          @lambda_edits.Delete(..)
          | @lambda_edits.WrapInLambda(..)
          | @lambda_edits.Drop(..) =>
            match commit_tree_edit(model, tree_op) {
              Ok((cmd, new_model)) => Some((cmd, new_model))
              Err(_) => Some((none, model))
            }
          _ => Some((none, model))
        }
      }
    StructureHistory(generation~, direction) =>
      if model.mode != Structure || generation != model.structure_generation {
        Some((none, model))
      } else {
        Some(apply_history(model, direction))
      }
    ExternalCrdtChanged => {
      let new_model = refresh(model)
      Some((sync_after_external_crdt_change(new_model), new_model))
    }
    _ => None
  }
}
