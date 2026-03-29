///|
fn compute_unwrap(
  ctx : EditContext[@ast.Term],
  node_id : NodeId,
  keep_child_index : Int,
) -> EditResult {
  let { source_map, registry, .. } = ctx
  match (source_map.get_range(node_id), registry.get(node_id)) {
    (Some(range), Some(node)) =>
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
    _ => Err("Node not found: " + node_id.to_string())
  }
}

///|
fn compute_swap_children(
  ctx : EditContext[@ast.Term],
  node_id : NodeId,
) -> EditResult {
  let { source_map, registry, .. } = ctx
  match (source_map.get_range(node_id), registry.get(node_id)) {
    (Some(range), Some(node)) =>
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
    _ => Err("Node not found: " + node_id.to_string())
  }
}

///|
fn compute_change_operator(
  ctx : EditContext[@ast.Term],
  node_id : NodeId,
  new_op : @ast.Bop,
) -> EditResult {
  let { source_map, registry, .. } = ctx
  match (source_map.get_range(node_id), registry.get(node_id)) {
    (Some(range), Some(node)) =>
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
    _ => Err("Node not found: " + node_id.to_string())
  }
}
