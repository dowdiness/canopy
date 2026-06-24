///|
fn compute_commit(
  ctx : EditContext[@ast.Term],
  node_id : NodeId,
  new_value : String,
) -> EditResult {
  let (node, range) = ctx.resolve(node_id) catch {
    ResolveError(e) => return Err(e)
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
