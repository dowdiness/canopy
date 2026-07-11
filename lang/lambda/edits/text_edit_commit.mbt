///|
fn compute_commit(
  ctx : EditContext[@ast.Term],
  node_id : NodeId,
  new_value : String,
) -> EditResult raise EditError {
  let (node, range) = ctx.resolve(node_id)
  ensure_replaceable_node_range(ctx, node_id, node, range)
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
  )
}
