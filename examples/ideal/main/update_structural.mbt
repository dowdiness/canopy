///|
fn handle_structural(
  emit : Emit[Msg],
  msg : Msg,
  model : Model,
) -> (Cmd, Model)? {
  let _ = emit
  match msg {
    StructuralEditRequested(op~, node_id~) =>
      if op == "" || node_id == "" {
        Some((none, model))
      } else {
        Some(apply_structural_edit_request(model, op, node_id))
      }
    TreeEdited(op) =>
      match op {
        @lambda_edits.Expand(node_id~) => {
          let hydrate_after_expand = can_hydrate_tree_node(model, node_id)
          let outline_state = if hydrate_after_expand {
            model.outline_state.expand_node(
              node_id,
              model.editor.get_proj_node(),
              model.editor.get_source_map(),
            )
          } else {
            model.outline_state.apply_edit(op.to_generic())
          }
          Some((none, { ..model, outline_state, }))
        }
        @lambda_edits.Collapse(..)
        | @lambda_edits.Select(..)
        | @lambda_edits.SelectRange(..) => {
          let outline_state = model.outline_state.apply_edit(op.to_generic())
          Some((none, { ..model, outline_state, }))
        }
        _ => Some((none, model))
      }
    OutlineStructuralEdit(tree_op) =>
      match commit_tree_edit(model, tree_op) {
        Ok((cmd, new_model)) => {
          let (new_selected, outline_state) = match
            new_model.editor
            .get_source_map()
            .innermost_node_at(new_model.editor.get_cursor()) {
            Some(nid) => {
              let os = new_model.outline_state.apply_edit(
                @canopy_core.GenericTreeOp::Select(node_id=nid),
              )
              (Some(node_id_to_string(nid)), os)
            }
            None => (None, new_model.outline_state)
          }
          let selected = select_with_highlight(new_model, new_selected, true)
          Some((cmd, { ..selected, outline_state, }))
        }
        Err(_) => Some((none, model))
      }
    _ => None
  }
}
