///|
fn compute_delete_binding(
  ctx : EditContext,
  binding_node_id : NodeId,
) -> EditResult {
  let { source_text, source_map, flat_proj, .. } = ctx
  let def_index = match find_def_index(flat_proj, binding_node_id) {
    Ok(i) => i
    Err(e) => return Err(e)
  }
  let (let_start, binding_end) = match
    get_binding_text_range(source_text, source_map, flat_proj.defs[def_index]) {
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
fn compute_duplicate_binding(
  ctx : EditContext,
  binding_node_id : NodeId,
) -> EditResult {
  let { source_text, source_map, flat_proj, .. } = ctx
  let def_index = match find_def_index(flat_proj, binding_node_id) {
    Ok(i) => i
    Err(e) => return Err(e)
  }
  let def = flat_proj.defs[def_index]
  let (let_start, binding_end) = match
    get_binding_text_range(source_text, source_map, def) {
    Ok(r) => r
    Err(e) => return Err(e)
  }
  // Extract binding text and create copy with _copy suffix on name
  let binding_text = source_text[let_start:binding_end].to_string()
  let new_name = def.0 + "_copy"
  let init_text = @ast.print_term(def.1.kind)
  let new_binding = "let " + new_name + " = " + init_text
  // Insert after the current binding (after newline)
  let insert_pos = if binding_end < source_text.length() &&
    source_text[binding_end] == '\n' {
    binding_end + 1
  } else {
    binding_end
  }
  let _ = binding_text
  let insert_text = if insert_pos == binding_end {
    // No trailing newline — add one before the new binding
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
  ctx : EditContext,
  binding_node_id : NodeId,
) -> EditResult {
  let { source_text, source_map, flat_proj, .. } = ctx
  let def_index = match find_def_index(flat_proj, binding_node_id) {
    Ok(i) => i
    Err(e) => return Err(e)
  }
  if def_index == 0 {
    return Err("Cannot move first binding up")
  }
  // Scoping guard: check if either name is free in the other's init
  let cur_def = flat_proj.defs[def_index]
  let prev_def = flat_proj.defs[def_index - 1]
  let empty_env : @immut/hashset.HashSet[String] = @immut/hashset.new()
  let cur_fv = free_vars(cur_def.1.kind, empty_env)
  let prev_fv = free_vars(prev_def.1.kind, empty_env)
  // Only check if cur depends on prev: after swap, cur comes first,
  // so prev (now below) wouldn't be in scope for cur's init.
  // The reverse (prev depends on cur) is safe: after swap, cur is above prev.
  if cur_fv.contains(prev_def.0) {
    return Err(
      "Cannot move up: " + cur_def.0 + " uses " + prev_def.0 + " in its init",
    )
  }
  if cur_def.0 == prev_def.0 {
    return Err("Cannot swap bindings with the same name")
  }
  // Get text ranges for both bindings
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
  // Swap the two binding lines by replacing the combined range
  let prev_text = source_text[prev_start:prev_end].to_string()
  let cur_text = source_text[cur_start:cur_end].to_string()
  // The separator between bindings (typically "\n")
  let separator = source_text[prev_end:cur_start].to_string()
  let swapped = cur_text + separator + prev_text
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
  ctx : EditContext,
  binding_node_id : NodeId,
) -> EditResult {
  let { source_text, source_map, flat_proj, .. } = ctx
  let def_index = match find_def_index(flat_proj, binding_node_id) {
    Ok(i) => i
    Err(e) => return Err(e)
  }
  if def_index >= flat_proj.defs.length() - 1 {
    return Err("Cannot move last binding down")
  }
  // Scoping guard: check if either name is free in the other's init
  let cur_def = flat_proj.defs[def_index]
  let next_def = flat_proj.defs[def_index + 1]
  let empty_env : @immut/hashset.HashSet[String] = @immut/hashset.new()
  let cur_fv = free_vars(cur_def.1.kind, empty_env)
  let next_fv = free_vars(next_def.1.kind, empty_env)
  // Only check if next depends on cur: after swap, next comes first,
  // so cur (now below) wouldn't be in scope for next's init.
  // The reverse (cur depends on next) is safe: after swap, next is above cur.
  if next_fv.contains(cur_def.0) {
    return Err(
      "Cannot move down: " + next_def.0 + " uses " + cur_def.0 + " in its init",
    )
  }
  if cur_def.0 == next_def.0 {
    return Err("Cannot swap bindings with the same name")
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
  // Swap the two binding lines by replacing the combined range
  let cur_text = source_text[cur_start:cur_end].to_string()
  let next_text = source_text[next_start:next_end].to_string()
  let separator = source_text[cur_end:next_start].to_string()
  let swapped = next_text + separator + cur_text
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
  ctx : EditContext,
  module_node_id : NodeId,
) -> EditResult {
  let { registry, flat_proj, .. } = ctx
  // Validate target is a Module node before delegating
  match registry.get(module_node_id) {
    None => Err("Module not found: " + module_node_id.to_string())
    Some(node) =>
      match node.kind {
        @ast.Term::Module(_, _) =>
          compute_insert_child(
            ctx,
            module_node_id,
            flat_proj.defs.length(),
            @ast.Term::Int(0),
          )
        _ => Err("AddBinding target is not a Module node")
      }
  }
}
