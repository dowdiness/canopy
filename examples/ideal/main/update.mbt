///|
fn apply_structural_edit_request(
  model : Model,
  op : String,
  node_id : String,
) -> (Cmd, Model) {
  let nid = match parse_node_id(node_id) {
    Some(id) => id
    None => return (none, model)
  }
  let tree_op = match @lambda.structural_edit_op_to_tree_edit(op, nid) {
    Some(tree_op) => tree_op
    None => return (none, model)
  }
  match commit_tree_edit(model, tree_op) {
    Ok(result) => result
    Err(_) => (none, model)
  }
}

///|
fn update(emit : Emit[Msg], msg : Msg, model : Model) -> (Cmd, Model) {
  match handle_workspace(emit, msg, model) {
    Some(r) => return r
    None => ()
  }
  match handle_structural(emit, msg, model) {
    Some(r) => return r
    None => ()
  }
  match handle_outline(emit, msg, model) {
    Some(r) => return r
    None => ()
  }
  match handle_overlay(emit, msg, model) {
    Some(r) => return r
    None => ()
  }
  match handle_file_io(emit, msg, model) {
    Some(r) => return r
    None => ()
  }
  match handle_structure_mode(emit, msg, model) {
    Some(r) => return r
    None => ()
  }
  match handle_codemirror(emit, msg, model) {
    Some(r) => return r
    None => ()
  }
  abort("unhandled message")
}
