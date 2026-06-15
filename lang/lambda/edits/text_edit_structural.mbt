///|
fn compute_unwrap(
  ctx : EditContext[@ast.Term],
  node_id : NodeId,
  keep_child_index : Int,
) -> EditResult {
  let (node, range) = match ctx.resolve(node_id) {
    Ok(r) => r
    Err(e) => return Err(e)
  }
  match ensure_replaceable_node_range(ctx, node_id, node, range) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  if keep_child_index < 0 || keep_child_index >= node.children.length() {
    Err("Child index out of range")
  } else {
    let kept = node.children[keep_child_index]
    let kept_text = @ast.print_term(kept.kind)
    // Cursor at start of the replacement text (the parent's original start),
    // not the kept child's original position which is invalidated by the edit.
    Ok(
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
      ),
    )
  }
}

///|
fn compute_swap_children(
  ctx : EditContext[@ast.Term],
  node_id : NodeId,
) -> EditResult {
  let (node, range) = match ctx.resolve(node_id) {
    Ok(r) => r
    Err(e) => return Err(e)
  }
  match ensure_replaceable_node_range(ctx, node_id, node, range) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  match node.kind {
    @ast.Term::Bop(op, l, r) => {
      let swapped = @ast.print_term(Bop(op, r, l))
      Ok(
        Some(
          (
            [
              {
                start: range.start,
                delete_len: range.end - range.start,
                inserted: swapped,
              },
            ],
            RestoreCursor,
          ),
        ),
      )
    }
    @ast.Term::If(c, t, e) => {
      let swapped = @ast.print_term(If(c, e, t))
      Ok(
        Some(
          (
            [
              {
                start: range.start,
                delete_len: range.end - range.start,
                inserted: swapped,
              },
            ],
            RestoreCursor,
          ),
        ),
      )
    }
    _ => Err("SwapChildren requires Bop or If node")
  }
}

///|
fn compute_change_operator(
  ctx : EditContext[@ast.Term],
  node_id : NodeId,
  new_op : @ast.Bop,
) -> EditResult {
  let (node, range) = match ctx.resolve(node_id) {
    Ok(r) => r
    Err(e) => return Err(e)
  }
  match ensure_replaceable_node_range(ctx, node_id, node, range) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  match node.kind {
    @ast.Term::Bop(_, l, r) => {
      let new_text = @ast.print_term(Bop(new_op, l, r))
      Ok(
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
        ),
      )
    }
    _ => Err("ChangeOperator requires Bop node")
  }
}
