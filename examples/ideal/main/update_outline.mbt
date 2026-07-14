///|
fn handle_outline(emit : Emit[Msg], msg : Msg, model : Model) -> (Cmd, Model)? {
  let _ = emit
  match msg {
    OutlineNodeClicked(node_id) => {
      let cmd = select_editor_node_cmd(model, node_id)
      let selected = select_with_highlight(model, Some(node_id), true)
      Some((cmd, selected))
    }
    OutlineNavigate(node_id_str) => {
      let new_selected : String? = if node_id_str == "" {
        None
      } else {
        Some(node_id_str)
      }
      let outline_state = match new_selected {
        Some(s) =>
          match parse_node_id(s) {
            Some(nid) =>
              model.outline_state.apply_edit(
                @canopy_core.GenericTreeOp::Select(node_id=nid),
              )
            None => return Some((none, model))
          }
        None => model.outline_state
      }
      let cmd = match new_selected {
        Some(s) =>
          @rabbita.batch([
            select_editor_node_cmd(model, s),
            scroll_selector_after_render(".outline-panel .tree-row.selected"),
          ])
        None => none
      }
      let selected = select_with_highlight(model, new_selected, false)
      Some((cmd, { ..selected, outline_state, }))
    }
    // Drag-and-drop
    OutlineDragStart(node_id) =>
      Some((none, { ..model, drag_source: Some(node_id) }))
    OutlineDragOver(target_id, position) =>
      Some(
        (
          none,
          {
            ..model,
            drop_target_id: Some(target_id),
            drop_position: Some(position),
          },
        ),
      )
    OutlineDragLeave =>
      Some((none, { ..model, drop_target_id: None, drop_position: None }))
    OutlineDragEnd =>
      Some(
        (
          none,
          {
            ..model,
            drag_source: None,
            drop_target_id: None,
            drop_position: None,
          },
        ),
      )
    OutlineDrop(target_id, position) => {
      let source = model.drag_source
      let model = {
        ..model,
        drag_source: None,
        drop_target_id: None,
        drop_position: None,
      }
      match source {
        None => Some((none, model))
        Some(source_id) => {
          let tree_op = @lambda_edits.TreeEditOp::Drop(
            source=source_id,
            target=target_id,
            position~,
          )
          match commit_tree_edit(model, tree_op) {
            Ok(result) => Some(result)
            Err(_) => Some((none, model))
          }
        }
      }
    }
    _ => None
  }
}
