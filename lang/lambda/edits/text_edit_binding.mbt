///|
/// Check scoping guards for swapping two adjacent bindings. `a_def` is the
/// binding that becomes first after the swap; `b_def` becomes second.
/// Rejects if a's init references b's name (which would become free), or if
/// b's init references a's name AND that ref currently resolves (which would
/// silently re-target to a).
fn check_swap_scoping(
  g : @scope.ScopeGraph,
  a_def : EditModuleBinding,
  b_def : EditModuleBinding,
  direction : String,
  registry : Map[NodeId, ProjNode[@ast.Term]],
) -> Result[Unit, String] {
  let a_subtree = subtree_node_ids(a_def.init)
  let b_subtree = subtree_node_ids(b_def.init)
  let a_outside = @scope.references_outside_subtree(
    g,
    a_subtree,
    registry=Some(registry),
  )
  let b_outside = @scope.references_outside_subtree(
    g,
    b_subtree,
    registry=Some(registry),
  )
  if a_outside.any(r => r.name == b_def.name) {
    return Err(
      "Cannot move " +
      direction +
      ": " +
      a_def.name +
      " uses " +
      b_def.name +
      " in its init",
    )
  }
  if b_outside.any(r => r.name == a_def.name && r.resolution.decl is Some(_)) {
    return Err(
      "Cannot move " +
      direction +
      ": " +
      b_def.name +
      " uses " +
      a_def.name +
      " in its init",
    )
  }
  Ok(())
}

///|
fn compute_delete_binding(
  ctx : EditContext[@ast.Term],
  binding_node_id : NodeId,
) -> EditResult {
  let { source_text, source_map, registry, .. } = ctx
  let g = @scope.build(registry, source_map)
  let decl = match module_def_decl_for_binding(g, binding_node_id) {
    Ok(d) => d
    Err(e) => return Err(e)
  }
  let def = match edit_binding_for_decl(ctx, decl) {
    Ok(d) => d
    Err(e) => return Err(e)
  }
  let (let_start, binding_end) = match
    get_binding_text_range(source_text, source_map, def) {
    Ok(r) => r
    Err(e) => return Err(e)
  }
  let (del_start, del_len) = binding_delete_range(
    source_text, let_start, binding_end,
  )
  Ok(
    Some(
      ([{ start: del_start, delete_len: del_len, inserted: "" }], RestoreCursor),
    ),
  )
}

///|
fn declaration_names_in_scope(
  g : @scope.ScopeGraph,
  scope : @scope.ScopeId,
) -> @immut/hashset.HashSet[String] {
  let @scope.ScopeId(si) = scope
  @immut/hashset.HashSet::from_iter(
    g.scopes[si].decl_ids
    .iter()
    .map(fn(did) {
      let @scope.DeclId(di) = did
      g.decls[di].name
    }),
  )
}

///|
/// Generate a Lambda-valid copy name from `base` that does not collide with any
/// name in `avoid`. `base` is already a valid Lambda identifier, so appending
/// decimal digits preserves lexability.
fn compute_fresh_name(
  base : String,
  avoid : @immut/hashset.HashSet[String],
  captures_existing_use : (String) -> Bool,
) -> String {
  for i = 1 {
    let candidate = base + i.to_string()
    if !avoid.contains(candidate) && !captures_existing_use(candidate) {
      break candidate
    }
    continue i + 1
  }
}

///|
/// Return the run of space characters starting at `pos`, used as the indentation
/// prefix for a line that already exists at that position.
fn leading_whitespace_at(source_text : String, pos : Int) -> String {
  let suffix = source_text[pos:]
  match suffix.find_by(fn(ch) { ch != ' ' }) {
    Some(end) => suffix[:end].to_owned()
    None => suffix.to_owned()
  }
}

///|
fn compute_duplicate_binding(
  ctx : EditContext[@ast.Term],
  binding_node_id : NodeId,
) -> EditResult {
  let { source_text, source_map, registry, .. } = ctx
  let g = @scope.build(registry, source_map)
  let decl = match module_def_decl_for_binding(g, binding_node_id) {
    Ok(d) => d
    Err(e) => return Err(e)
  }
  let def = match edit_binding_for_decl(ctx, decl) {
    Ok(d) => d
    Err(e) => return Err(e)
  }
  let binding_source = match
    binding_rewrite_source(source_text, source_map, def) {
    Ok(source) => source
    Err(e) => return Err(e)
  }
  // Create a fresh copy name while preserving source syntax such as `fn`
  // parameter annotations instead of reprinting the desugared Lam spine.
  let avoid = @scope.enclosing_env(g, binding_node_id).union(
    declaration_names_in_scope(g, decl.scope),
  )
  let new_name = compute_fresh_name(def.name, avoid, fn(candidate) {
    rename_captures_existing_use(g, decl, candidate)
  })
  let new_binding = match
    binding_source.renamed_text(source_text, source_map, new_name) {
    Ok(text) => text
    Err(e) => return Err(e)
  }
  // Insert after the current binding (after newline). Block-local bindings need
  // the following line's indentation prepended to the inserted copy.
  let block = find_enclosing_block(g, registry, binding_node_id)
  let binding_end = binding_source.binding_end
  let insert_pos = if binding_end < source_text.length() &&
    source_text[binding_end] == '\n' {
    binding_end + 1
  } else {
    binding_end
  }
  let insert_text = if block is Some(_) {
    let indent = leading_whitespace_at(source_text, insert_pos)
    let copied_indent_len = leading_whitespace_at(new_binding, 0).length()
    let block_binding = new_binding[copied_indent_len:].to_owned()
    if insert_pos == binding_end {
      "\n" + indent + block_binding + "\n"
    } else {
      indent + block_binding + "\n"
    }
  } else if insert_pos == binding_end {
    // No trailing newline — add one before the new binding.
    "\n" + new_binding
  } else {
    new_binding + "\n"
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

///|
fn compute_move_binding_up(
  ctx : EditContext[@ast.Term],
  binding_node_id : NodeId,
) -> EditResult {
  let { source_text, source_map, registry, .. } = ctx
  let g = @scope.build(registry, source_map)
  let decl = match module_def_decl_for_binding(g, binding_node_id) {
    Ok(d) => d
    Err(e) => return Err(e)
  }
  guard decl.kind is @scope.DeclKind::ModuleDef(def_index~) else {
    return Err("Binding is not a module definition")
  }
  if def_index == 0 {
    return Err("Cannot move first binding up")
  }
  // Move neighbour is the def at def_index - 1 in the SAME scope (block-local
  // aware), not a root sibling.
  let prev_decl = match sibling_module_def_decl(g, decl.scope, def_index - 1) {
    Some(d) => d
    None => return Err("Cannot move first binding up")
  }
  let cur_def = match edit_binding_for_decl(ctx, decl) {
    Ok(d) => d
    Err(e) => return Err(e)
  }
  let prev_def = match edit_binding_for_decl(ctx, prev_decl) {
    Ok(d) => d
    Err(e) => return Err(e)
  }
  if cur_def.name == prev_def.name {
    return Err("Cannot swap bindings with the same name")
  }
  // Scoping guards: the swap re-orders sequential visibility.
  match check_swap_scoping(g, cur_def, prev_def, "up", registry) {
    Ok(_) => ()
    Err(e) => return Err(e)
  }
  let (cur_start, cur_end) = match
    get_binding_text_range(source_text, source_map, cur_def) {
    Ok(r) => r
    Err(e) => return Err(e)
  }
  let (prev_start, prev_end) = match
    get_binding_text_range(source_text, source_map, prev_def) {
    Ok(r) => r
    Err(e) => return Err(e)
  }
  // Swap the two binding lines by replacing the combined range.
  // Strip leading whitespace from both texts and re-indent to destination positions,
  // so that block-local bindings (which may carry indentation) normalize correctly.
  let prev_text = source_text[prev_start:prev_end].to_owned()
  let cur_text = source_text[cur_start:cur_end].to_owned()
  let prev_indent_len = leading_whitespace_at(prev_text, 0).length()
  let cur_indent_len = leading_whitespace_at(cur_text, 0).length()
  let swapped = leading_whitespace_at(source_text, prev_start) +
    cur_text[cur_indent_len:].to_owned() +
    "\n" +
    leading_whitespace_at(source_text, cur_start) +
    prev_text[prev_indent_len:].to_owned()
  Ok(
    Some(
      (
        [
          {
            start: prev_start,
            delete_len: cur_end - prev_start,
            inserted: swapped,
          },
        ],
        RestoreCursor,
      ),
    ),
  )
}

///|
fn compute_move_binding_down(
  ctx : EditContext[@ast.Term],
  binding_node_id : NodeId,
) -> EditResult {
  let { source_text, source_map, registry, .. } = ctx
  let g = @scope.build(registry, source_map)
  let decl = match module_def_decl_for_binding(g, binding_node_id) {
    Ok(d) => d
    Err(e) => return Err(e)
  }
  guard decl.kind is @scope.DeclKind::ModuleDef(def_index~) else {
    return Err("Binding is not a module definition")
  }
  // Move neighbour is the def at def_index + 1 in the SAME scope (block-local
  // aware); its absence means this is the last binding in its block.
  let next_decl = match sibling_module_def_decl(g, decl.scope, def_index + 1) {
    Some(d) => d
    None => return Err("Cannot move last binding down")
  }
  let cur_def = match edit_binding_for_decl(ctx, decl) {
    Ok(d) => d
    Err(e) => return Err(e)
  }
  let next_def = match edit_binding_for_decl(ctx, next_decl) {
    Ok(d) => d
    Err(e) => return Err(e)
  }
  if cur_def.name == next_def.name {
    return Err("Cannot swap bindings with the same name")
  }
  // Scoping guards: the swap re-orders sequential visibility.
  match check_swap_scoping(g, next_def, cur_def, "down", registry) {
    Ok(_) => ()
    Err(e) => return Err(e)
  }
  // Get text ranges for both bindings
  let (cur_start, cur_end) = match
    get_binding_text_range(source_text, source_map, cur_def) {
    Ok(r) => r
    Err(e) => return Err(e)
  }
  let (next_start, next_end) = match
    get_binding_text_range(source_text, source_map, next_def) {
    Ok(r) => r
    Err(e) => return Err(e)
  }
  // Swap the two binding lines by replacing the combined range.
  // Strip leading whitespace from both texts and re-indent to destination positions.
  let cur_text = source_text[cur_start:cur_end].to_owned()
  let next_text = source_text[next_start:next_end].to_owned()
  let cur_indent_len = leading_whitespace_at(cur_text, 0).length()
  let next_indent_len = leading_whitespace_at(next_text, 0).length()
  let swapped = leading_whitespace_at(source_text, cur_start) +
    next_text[next_indent_len:].to_owned() +
    "\n" +
    leading_whitespace_at(source_text, next_start) +
    cur_text[cur_indent_len:].to_owned()
  Ok(
    Some(
      (
        [
          {
            start: cur_start,
            delete_len: next_end - cur_start,
            inserted: swapped,
          },
        ],
        RestoreCursor,
      ),
    ),
  )
}

///|
fn compute_add_binding(
  ctx : EditContext[@ast.Term],
  module_node_id : NodeId,
) -> EditResult {
  let { registry, .. } = ctx
  let module_view = edit_module_view(ctx)
  // Validate target is a Module node before delegating
  guard registry.get(module_node_id) is Some(node) else {
    return Err("Module not found: " + module_node_id.to_string())
  }
  match node.kind {
    @ast.Term::Module(_, _) =>
      compute_insert_child(
        ctx,
        module_node_id,
        module_view.defs.length(),
        @ast.Term::Int(0),
      )
    _ => Err("AddBinding target is not a Module node")
  }
}
