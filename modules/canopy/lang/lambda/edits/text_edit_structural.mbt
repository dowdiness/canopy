///|
fn compute_unwrap(
  ctx : EditContext[@ast.Term],
  node_id : NodeId,
  keep_child_index : Int,
) -> EditResult raise EditError {
  let (node, range) = ctx.resolve(node_id)
  ensure_replaceable_node_range(ctx, node_id, node, range)
  guard keep_child_index >= 0 && keep_child_index < node.children.length() else {
    raise Invariant(detail="Child index out of range")
  }
  let kept = node.children[keep_child_index]
  let kept_text = @ast.print_term(kept.kind)
  // Cursor at start of the replacement text (the parent's original start),
  // not the kept child's original position which is invalidated by the edit.
  Some(
    (
      [
        {
          start: range.start,
          delete_len: range.end - range.start,
          inserted: kept_text,
        },
      ],
      MoveCursor(position=range.start),
    ),
  )
}

///|
fn compute_swap_children(
  ctx : EditContext[@ast.Term],
  node_id : NodeId,
) -> EditResult raise EditError {
  let (node, range) = ctx.resolve(node_id)
  ensure_replaceable_node_range(ctx, node_id, node, range)
  match node.kind {
    @ast.Term::Bop(op, left, right) => {
      let new_kind = @ast.Term::Bop(op, right, left)
      let new_text = @ast.print_term(new_kind)
      Some(
        (
          [
            {
              start: range.start,
              delete_len: range.end - range.start,
              inserted: new_text,
            },
          ],
          RestoreCursor,
        ),
      )
    }
    @ast.Term::If(cond, then_body, else_body) => {
      let new_kind = @ast.Term::If(cond, else_body, then_body)
      let new_text = @ast.print_term(new_kind)
      Some(
        (
          [
            {
              start: range.start,
              delete_len: range.end - range.start,
              inserted: new_text,
            },
          ],
          RestoreCursor,
        ),
      )
    }
    _ => raise InvalidTarget(detail="SwapChildren requires Bop or If node")
  }
}

///|
fn compute_change_operator(
  ctx : EditContext[@ast.Term],
  node_id : NodeId,
  new_op : @ast.Bop,
) -> EditResult raise EditError {
  let (node, range) = ctx.resolve(node_id)
  ensure_replaceable_node_range(ctx, node_id, node, range)
  match node.kind {
    @ast.Term::Bop(_op, left, right) => {
      let new_kind = @ast.Term::Bop(new_op, left, right)
      let new_text = @ast.print_term(new_kind)
      Some(
        (
          [
            {
              start: range.start,
              delete_len: range.end - range.start,
              inserted: new_text,
            },
          ],
          RestoreCursor,
        ),
      )
    }
    _ => raise InvalidTarget(detail="ChangeOperator requires Bop node")
  }
}
