///|
fn handle_structure_mode(
  emit : Emit[Msg],
  msg : Msg,
  model : Model,
) -> (Cmd, Model)? {
  let _ = emit
  match msg {
    StructureNodeSelected(node_id) =>
      if node_id == "" {
        Some((none, model))
      } else {
        let selected = select_with_highlight(model, Some(node_id), true)
        Some((none, selected))
      }
    StructureStructuralEdit(op~, node_id~) =>
      if op == "" || node_id == "" {
        Some((none, model))
      } else {
        let rebuilt = parse_node_id(node_id).bind(nid => {
          @lambda.structural_edit_op_to_tree_edit(op, nid)
        })
        match rebuilt {
          Some(tree_op) => push_intent(model, tree_op)
          None => push_intent_label(model, "\{op}(node=\{node_id})")
        }
        let new_model = refresh({
          ..model,
          next_timestamp: model.next_timestamp + 1,
        })
        Some((sync_after_external_crdt_change(new_model), new_model))
      }
    ExternalCrdtChanged => {
      let new_model = refresh(model)
      Some((sync_after_external_crdt_change(new_model), new_model))
    }
    _ => None
  }
}
