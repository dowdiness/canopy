///|
fn compute_commit(
  ctx : EditContext[@ast.Term],
  node_id : NodeId,
  new_value : String,
) -> EditResult {
  guard ctx.source_map.get_range(node_id) is Some(range) else {
    return Err("Node not found: " + node_id.to_string())
  }
  guard ctx.registry.get(node_id) is Some(node) else {
    return Err("Node not found: " + node_id.to_string())
  }
  match ensure_replaceable_node_range(ctx, node_id, node, range) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  Ok(
    Some(
      (
        [
          {
            start: range.start,
            delete_len: range.end - range.start,
            inserted: new_value,
          },
        ],
        RestoreCursor,
      ),
    ),
  )
}
