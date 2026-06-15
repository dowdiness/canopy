///|
fn compute_delete(ctx : EditContext[@ast.Term], node_id : NodeId) -> EditResult {
  let (node, range) = ctx.resolve(node_id) catch {
    ResolveError(e) => return Err(e)
  }
  match find_parent(ctx.registry, node_id) {
    Some((parent_id, parent_node, child_index)) =>
      match parent_node.kind {
        @ast.Term::Error(_) =>
          // Error parent: remove child entirely
          Ok(
            Some(
              (
                [
                  {
                    start: range.start,
                    delete_len: range.end - range.start,
                    inserted: "",
                  },
                ],
                RestoreCursor,
              ),
            ),
          )
        _ => {
          // Replace child with placeholder in parent, then re-render parent
          let target = parent_node.children[child_index]
          let pk = placeholder_term_for_kind(target.kind)
          // Build new children array with placeholder at child_index
          let new_children = Array::makei(parent_node.children.length(), fn(i) {
            let c = parent_node.children[i]
            if i == child_index {
              ProjNode::new(pk, c.start, c.end, c.node_id, [])
            } else {
              c
            }
          })
          let new_parent_kind = rebuild_kind(parent_node.kind, new_children)
          let new_text = @ast.print_term(new_parent_kind)
          match ctx.source_map.get_range(parent_id) {
            None => {
              // No parent range — fall back to simple placeholder
              let placeholder = placeholder_text_for_kind(node.kind)
              Ok(
                Some(
                  (
                    [
                      {
                        start: range.start,
                        delete_len: range.end - range.start,
                        inserted: placeholder,
                      },
                    ],
                    RestoreCursor,
                  ),
                ),
              )
            }
            Some(parent_range) =>
              match
                ensure_replaceable_node_range(
                  ctx, parent_id, parent_node, parent_range,
                ) {
                Ok(_) =>
                  Ok(
                    Some(
                      (
                        [
                          {
                            start: parent_range.start,
                            delete_len: parent_range.end - parent_range.start,
                            inserted: new_text,
                          },
                        ],
                        RestoreCursor,
                      ),
                    ),
                  )
                Err(parent_err) =>
                  match
                    ensure_replaceable_node_range(ctx, node_id, target, range) {
                    Ok(_) => {
                      let placeholder = @ast.print_term(
                        placeholder_term_for_kind(target.kind),
                      )
                      Ok(
                        Some(
                          (
                            [
                              {
                                start: range.start,
                                delete_len: range.end - range.start,
                                inserted: placeholder,
                              },
                            ],
                            RestoreCursor,
                          ),
                        ),
                      )
                    }
                    Err(_) => Err(parent_err)
                  }
              }
          }
        }
      }
    None => {
      // No parent found — this is the root node. Just use placeholder.
      let placeholder = placeholder_text_for_kind(node.kind)
      Ok(
        Some(
          (
            [
              {
                start: range.start,
                delete_len: range.end - range.start,
                inserted: placeholder,
              },
            ],
            RestoreCursor,
          ),
        ),
      )
    }
  }
}
