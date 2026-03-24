///|
fn compute_commit(
  ctx : EditContext[@ast.Term],
  node_id : NodeId,
  new_value : String,
) -> EditResult {
  match ctx.source_map.get_range(node_id) {
    None => Err("Node not found: " + node_id.to_string())
    Some(range) =>
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
}
