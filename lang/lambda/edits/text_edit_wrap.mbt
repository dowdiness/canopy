///|
fn compute_wrap_lambda(
  ctx : EditContext[@ast.Term],
  node_id : NodeId,
  var_name : String,
) -> EditResult {
  let (node, range) = ctx.resolve(node_id) catch {
    ResolveError(e) => return Err(e)
  }
  match ensure_replaceable_node_range(ctx, node_id, node, range) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  let wrapped = @ast.print_term(@ast.Term::Lam(var_name, node.kind))
  let wrapped = match find_parent(ctx.registry, node_id) {
    Some(_) => "(" + wrapped + ")"
    None => wrapped
  }
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

///|
fn compute_wrap_app(
  ctx : EditContext[@ast.Term],
  node_id : NodeId,
) -> EditResult {
  let (node, range) = ctx.resolve(node_id) catch {
    ResolveError(e) => return Err(e)
  }
  match ensure_replaceable_node_range(ctx, node_id, node, range) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  let wrapped = @ast.print_term(App(node.kind, Var("a")))
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

///|
fn compute_wrap_if(
  ctx : EditContext[@ast.Term],
  node_id : NodeId,
) -> EditResult {
  let (node, range) = ctx.resolve(node_id) catch {
    ResolveError(e) => return Err(e)
  }
  match ensure_replaceable_node_range(ctx, node_id, node, range) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
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

///|
fn compute_wrap_bop(
  ctx : EditContext[@ast.Term],
  node_id : NodeId,
  op : @ast.Bop,
) -> EditResult {
  let (node, range) = ctx.resolve(node_id) catch {
    ResolveError(e) => return Err(e)
  }
  match ensure_replaceable_node_range(ctx, node_id, node, range) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  let wrapped = @ast.print_term(Bop(op, node.kind, Int(0)))
  // "expr + 0" — the printer emits no redundant outer parens (loom printer
  // catamorphism migration), so the placeholder "0" is the final character.
  let placeholder_pos = range.start + wrapped.length() - 1
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
  guard registry.get(parent) is Some(parent_node) else {
    return Err("Parent not found: " + parent.to_string())
  }
  guard source_map.get_range(parent) is Some(parent_range) else {
    return Err("Parent not in source map")
  }
  match parent_node.kind {
    @ast.Term::Module(_, _) => {
      // Insert a def between existing defs, with trailing newline separator
      let insert_text = "let x = " + placeholder + "\n"
      let insert_pos = if index >= parent_node.children.length() {
        // Insert before the body (last child)
        let body = parent_node.children[parent_node.children.length() - 1]
        match source_map.get_range(body.id()) {
          // Synthetic body (empty-def block): body start equals parent end.
          // Insert before the closing brace instead of after it.
          Some(r) if r.start < parent_range.end => r.start
          _ => parent_range.end - 1
        }
      } else {
        match source_map.get_range(parent_node.children[index].id()) {
          Some(r) if r.start < parent_range.end => r.start
          _ => parent_range.end - 1
        }
      }
      Ok(
        Some(
          (
            [{ start: insert_pos, delete_len: 0, inserted: insert_text }],
            RestoreCursor,
          ),
        ),
      )
    }
    _ => {
      match
        ensure_replaceable_node_range(ctx, parent, parent_node, parent_range) {
        Err(e) => return Err(e)
        Ok(_) => ()
      }
      // Re-render whole parent with new child inserted
      let new_child = ProjNode(kind, 0, 0, 0, [])
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
