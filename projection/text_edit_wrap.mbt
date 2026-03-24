///|
fn compute_wrap_lambda(
  ctx : EditContext[@ast.Term],
  node_id : NodeId,
  var_name : String,
) -> EditResult {
  let { source_map, registry, .. } = ctx
  match source_map.get_range(node_id) {
    None => Err("Node not found: " + node_id.to_string())
    Some(range) => {
      let existing = match registry.get(node_id) {
        Some(node) => @ast.print_term(node.kind)
        None => return Err("Node not found in registry")
      }
      let wrapped = "(λ" + var_name + ". " + existing + ")"
      Ok(
        Some(
          (
            [
              {
                start: range.start,
                delete_len: range.end - range.start,
                inserted: wrapped,
              },
            ],
            RestoreCursor,
          ),
        ),
      )
    }
  }
}

///|
fn compute_wrap_app(
  ctx : EditContext[@ast.Term],
  node_id : NodeId,
) -> EditResult {
  let { source_map, registry, .. } = ctx
  match source_map.get_range(node_id) {
    None => Err("Node not found: " + node_id.to_string())
    Some(range) => {
      let existing_kind = match registry.get(node_id) {
        Some(node) => node.kind
        None => return Err("Node not found in registry")
      }
      let wrapped = @ast.print_term(App(existing_kind, Var("a")))
      Ok(
        Some(
          (
            [
              {
                start: range.start,
                delete_len: range.end - range.start,
                inserted: wrapped,
              },
            ],
            RestoreCursor,
          ),
        ),
      )
    }
  }
}

///|
fn compute_wrap_if(
  ctx : EditContext[@ast.Term],
  node_id : NodeId,
) -> EditResult {
  let { source_map, registry, .. } = ctx
  match (source_map.get_range(node_id), registry.get(node_id)) {
    (Some(range), Some(node)) => {
      let wrapped = @ast.print_term(If(Int(0), node.kind, Int(0)))
      // "if 0 then ..." — condition placeholder "0" starts at offset 3
      let condition_pos = range.start + 3
      Ok(
        Some(
          (
            [
              {
                start: range.start,
                delete_len: range.end - range.start,
                inserted: wrapped,
              },
            ],
            MoveCursor(position=condition_pos),
          ),
        ),
      )
    }
    _ => Err("Node not found: " + node_id.to_string())
  }
}

///|
fn compute_wrap_bop(
  ctx : EditContext[@ast.Term],
  node_id : NodeId,
  op : @ast.Bop,
) -> EditResult {
  let { source_map, registry, .. } = ctx
  match (source_map.get_range(node_id), registry.get(node_id)) {
    (Some(range), Some(node)) => {
      let wrapped = @ast.print_term(Bop(op, node.kind, Int(0)))
      // "(expr + 0)" — placeholder "0" is at wrapped.length() - 2 from start
      let placeholder_pos = range.start + wrapped.length() - 2
      Ok(
        Some(
          (
            [
              {
                start: range.start,
                delete_len: range.end - range.start,
                inserted: wrapped,
              },
            ],
            MoveCursor(position=placeholder_pos),
          ),
        ),
      )
    }
    _ => Err("Node not found: " + node_id.to_string())
  }
}

///|
fn compute_insert_child(
  ctx : EditContext[@ast.Term],
  parent : NodeId,
  index : Int,
  kind : @ast.Term,
) -> EditResult {
  if index < 0 {
    return Err("Negative index")
  }
  let { source_map, registry, .. } = ctx
  let placeholder = placeholder_text_for_kind(kind)
  match registry.get(parent) {
    None => Err("Parent not found: " + parent.to_string())
    Some(parent_node) =>
      match source_map.get_range(parent) {
        None => Err("Parent not in source map")
        Some(parent_range) =>
          match parent_node.kind {
            @ast.Term::Module(_, _) => {
              // Insert a def between existing defs, with trailing newline separator
              let insert_text = "let x = " + placeholder + "\n"
              let insert_pos = if index >= parent_node.children.length() {
                // Insert before the body (last child)
                let body = parent_node.children[parent_node.children.length() -
                  1]
                match source_map.get_range(NodeId(body.node_id)) {
                  Some(r) => r.start
                  None => parent_range.end
                }
              } else {
                match
                  source_map.get_range(
                    NodeId(parent_node.children[index].node_id),
                  ) {
                  Some(r) => r.start
                  None => parent_range.start
                }
              }
              Ok(
                Some(
                  (
                    [
                      {
                        start: insert_pos,
                        delete_len: 0,
                        inserted: insert_text,
                      },
                    ],
                    RestoreCursor,
                  ),
                ),
              )
            }
            _ => {
              // Re-render whole parent with new child inserted
              let new_child = ProjNode::new(kind, 0, 0, 0, [])
              let new_parent = insert_child_at(parent_node, index, new_child)
              let new_text = @ast.print_term(new_parent.kind)
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
  }
}
