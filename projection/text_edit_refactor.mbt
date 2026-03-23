///|
fn compute_extract_to_let(
  ctx : EditContext,
  node_id : NodeId,
  var_name : String,
) -> EditResult {
  let { source_text, source_map, registry, flat_proj } = ctx
  let node = match registry.get(node_id) {
    Some(n) => n
    None => return Err("Node not found")
  }
  let range = match source_map.get_range(node_id) {
    Some(r) => r
    None => return Err("Range not found")
  }
  // Free-var validation: check for lambda-captured variables
  let mut module_env : @immut/hashset.HashSet[String] = @immut/hashset.new()
  // Find which def contains this node (or if it's in the body)
  let mut in_def_index : Int = flat_proj.defs.length() // body sentinel
  for i, def in flat_proj.defs {
    match source_map.get_range(def.1.id()) {
      Some(r) =>
        if range.start >= r.start && range.end <= r.end {
          in_def_index = i
          break
        }
      None => ()
    }
  }
  // Add def names in scope at the extraction site
  let scope_limit = if in_def_index < flat_proj.defs.length() {
    in_def_index
  } else {
    flat_proj.defs.length()
  }
  for i = 0; i < scope_limit; i = i + 1 {
    module_env = module_env.add(flat_proj.defs[i].0)
  }
  // Check for lambda-captured vars
  let lam_env = collect_lam_env(node_id, registry)
  let fv = free_vars(node.kind, module_env)
  let mut captured_var : String? = None
  fv.each(fn(v) { if lam_env.contains(v) { captured_var = Some(v) } })
  if captured_var is Some(_) {
    return Err("Cannot extract: expression captures lambda-bound variables")
  }
  // Build edits
  let expr_text = @ast.print_term(node.kind)
  let let_text = "let " + var_name + " = " + expr_text + "\n"
  if flat_proj.defs.is_empty() && flat_proj.final_expr is Some(_) {
    // No module — wrap: replace expression with "let name = expr\nname"
    let new_text = let_text + var_name
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
          MoveCursor(position=range.start + let_text.length()),
        ),
      ),
    )
  } else {
    // Has Module — insert let before body, replace expr with var_name
    let body_start = match flat_proj.final_expr {
      Some(body) =>
        match source_map.get_range(body.id()) {
          Some(r) => r.start
          None => source_text.length()
        }
      None => source_text.length()
    }
    // Check if node is within the body (range starts at or after body start).
    // If so, we need a single combined edit to avoid overlapping edits.
    if range.start >= body_start {
      // Node is in the body — produce a single edit:
      // Replace body text from body_start to end with:
      //   "let var = expr\n" + (prefix before node) + var_name + (suffix after node)
      let body_end = match flat_proj.final_expr {
        Some(body) =>
          match source_map.get_range(body.id()) {
            Some(r) => r.end
            None => source_text.length()
          }
        None => source_text.length()
      }
      let prefix = source_text[body_start:range.start].to_string()
      let suffix = source_text[range.end:body_end].to_string()
      let new_body_text = let_text + prefix + var_name + suffix
      Ok(
        Some(
          (
            [
              {
                start: body_start,
                delete_len: body_end - body_start,
                inserted: new_body_text,
              },
            ],
            MoveCursor(
              position=body_start + let_text.length() + prefix.length(),
            ),
          ),
        ),
      )
    } else {
      // Node is in a def — two independent edits at non-overlapping positions
      Ok(
        Some(
          (
            [
              { start: body_start, delete_len: 0, inserted: let_text },
              {
                start: range.start,
                delete_len: range.end - range.start,
                inserted: var_name,
              },
            ],
            MoveCursor(position=range.start),
          ),
        ),
      )
    }
  }
}

///|
fn compute_inline_definition(ctx : EditContext, node_id : NodeId) -> EditResult {
  let { source_text, source_map, registry, flat_proj } = ctx
  let node = match registry.get(node_id) {
    Some(n) => n
    None => return Err("Node not found: " + node_id.to_string())
  }
  let var_name = match node.kind {
    @ast.Term::Var(name) => name
    _ => return Err("InlineDefinition requires a Var node")
  }
  let range = match source_map.get_range(node_id) {
    Some(r) => r
    None => return Err("Var not in source map")
  }
  // Resolve the binding
  let binder = match
    resolve_binder(node_id, var_name, flat_proj, registry, source_map) {
    Some(b) => b
    None => return Err("No binding found for variable: " + var_name)
  }
  match binder {
    LamBinder(..) =>
      return Err("Cannot inline lambda-bound variable: " + var_name)
    ModuleBinder(def_index~, ..) => {
      let def = flat_proj.defs[def_index]
      let init_text = @ast.print_term(def.1.kind)
      // Check for capture: would any free var in init be captured by a lambda at the usage site?
      let init_fv = free_vars(def.1.kind, @immut/hashset.new())
      let usage_lam_env = collect_lam_env(node_id, registry)
      let mut would_capture = false
      init_fv.each(fn(v) {
        if usage_lam_env.contains(v) {
          would_capture = true
        }
      })
      if would_capture {
        return Err(
          "Cannot inline: would capture variables bound by enclosing lambda",
        )
      }
      // Check if this is the sole usage
      let usages = find_usages(var_name, def_index + 1, flat_proj, registry)
      if usages.length() <= 1 {
        // Sole usage — inline and delete the binding
        let (let_start, binding_end) = match
          get_binding_text_range(source_text, source_map, def) {
          Ok(r) => r
          Err(e) => return Err(e)
        }
        let (del_start, del_len) = binding_delete_range(
          source_text, let_start, binding_end,
        )
        // If the var range is after the binding, we need to adjust
        // for the deletion. Produce edits in reverse document order.
        if range.start >= binding_end {
          // Var is after binding — two non-overlapping edits.
          // Cursor must use post-edit coordinates: the binding deletion
          // shifts everything after del_start left by del_len.
          Ok(
            Some(
              (
                [
                  {
                    start: range.start,
                    delete_len: range.end - range.start,
                    inserted: init_text,
                  },
                  { start: del_start, delete_len: del_len, inserted: "" },
                ],
                MoveCursor(position=range.start - del_len),
              ),
            ),
          )
        } else {
          // Var is within the binding init — just replace the var
          Ok(
            Some(
              (
                [
                  {
                    start: range.start,
                    delete_len: range.end - range.start,
                    inserted: init_text,
                  },
                ],
                MoveCursor(position=range.start),
              ),
            ),
          )
        }
      } else {
        // Multiple usages — just replace this single var
        Ok(
          Some(
            (
              [
                {
                  start: range.start,
                  delete_len: range.end - range.start,
                  inserted: init_text,
                },
              ],
              MoveCursor(position=range.start),
            ),
          ),
        )
      }
    }
  }
}

///|
fn compute_inline_all_usages(
  ctx : EditContext,
  binding_node_id : NodeId,
) -> EditResult {
  let { source_text, source_map, registry, flat_proj } = ctx
  let def_index = match find_def_index(flat_proj, binding_node_id) {
    Ok(i) => i
    Err(e) => return Err(e)
  }
  let def = flat_proj.defs[def_index]
  let var_name = def.0
  let init_text = @ast.print_term(def.1.kind)
  // Find all usages
  let usage_ids = find_usages(var_name, def_index + 1, flat_proj, registry)
  // Check for capture: would any free var in init be captured by a lambda at any usage site?
  let init_fv = free_vars(def.1.kind, @immut/hashset.new())
  for uid in usage_ids {
    let usage_lam_env = collect_lam_env(uid, registry)
    let mut would_capture = false
    init_fv.each(fn(v) { if usage_lam_env.contains(v) { would_capture = true } })
    if would_capture {
      return Err(
        "Cannot inline: would capture variables bound by enclosing lambda",
      )
    }
  }
  // Build replacement edits for all usages (reverse document order)
  let edits : Array[SpanEdit] = []
  // Collect usage ranges, sorted by position (descending)
  let usage_ranges : Array[(Int, Int)] = []
  for uid in usage_ids {
    match source_map.get_range(uid) {
      Some(r) => usage_ranges.push((r.start, r.end))
      None => ()
    }
  }
  usage_ranges.sort_by(fn(a, b) { b.0.compare(a.0) })
  for ur in usage_ranges {
    edits.push({ start: ur.0, delete_len: ur.1 - ur.0, inserted: init_text })
  }
  // Delete the binding
  let (let_start, binding_end) = match
    get_binding_text_range(source_text, source_map, def) {
    Ok(r) => r
    Err(e) => return Err(e)
  }
  let (del_start, del_len) = binding_delete_range(
    source_text, let_start, binding_end,
  )
  edits.push({ start: del_start, delete_len: del_len, inserted: "" })
  Ok(Some((edits, RestoreCursor)))
}
