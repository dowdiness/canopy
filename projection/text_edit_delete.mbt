///|
fn compute_delete(ctx : EditContext[@ast.Term], node_id : NodeId) -> EditResult {
  let { source_map, registry, .. } = ctx
  match source_map.get_range(node_id) {
    None => Err("Node not found: " + node_id.to_string())
    Some(range) =>
      match find_parent(registry, node_id) {
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
              let new_children : Array[ProjNode[@ast.Term]] = []
              for i, c in parent_node.children {
                if i == child_index {
                  new_children.push(
                    ProjNode::new(pk, c.start, c.end, c.node_id, []),
                  )
                } else {
                  new_children.push(c)
                }
              }
              let new_parent_kind = rebuild_kind(parent_node.kind, new_children)
              let new_text = @ast.print_term(new_parent_kind)
              match source_map.get_range(parent_id) {
                None => {
                  // No parent range — fall back to simple placeholder
                  let placeholder = match registry.get(node_id) {
                    Some(node) => placeholder_text_for_kind(node.kind)
                    None => "a"
                  }
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
              }
            }
          }
        None => {
          // No parent found — this is the root node. Just use placeholder.
          let placeholder = match registry.get(node_id) {
            Some(node) => placeholder_text_for_kind(node.kind)
            None => "a"
          }
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
}
