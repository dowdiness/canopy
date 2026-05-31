///|
fn compute_extract_to_let(
  ctx : EditContext[@ast.Term],
  node_id : NodeId,
  var_name : String,
) -> EditResult {
  let { source_text, source_map, registry, flat_proj } = ctx
  guard registry.get(node_id) is Some(node) else {
    return Err("Node not found")
  }
  guard source_map.get_range(node_id) is Some(range) else {
    return Err("Range not found")
  }
  let g = @scope.build(flat_proj, registry, source_map)
  let fv = free_vars(node.kind, @immut/hashset.new())
  let would_capture = if flat_proj.defs.is_empty() {
    free_names_captured_at_use_sites(g, node, fv)
  } else {
    free_names_would_rebind_at_module_end(g, flat_proj, node, fv)
  }
  if would_capture {
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
      let prefix = source_text[body_start:range.start].to_owned()
      let suffix = source_text[range.end:body_end].to_owned()
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
fn compute_inline_definition(
  ctx : EditContext[@ast.Term],
  node_id : NodeId,
) -> EditResult {
  let { source_text, source_map, registry, flat_proj } = ctx
  guard registry.get(node_id) is Some(node) else {
    return Err("Node not found: " + node_id.to_string())
  }
  guard node.kind is @ast.Term::Var(var_name) else {
    return Err("InlineDefinition requires a Var node")
  }
  guard source_map.get_range(node_id) is Some(range) else {
    return Err("Var not in source map")
  }
  // Resolve the binding
  let g = @scope.build(flat_proj, registry, source_map)
  guard @scope.declaration(g, node_id) is Some(decl) else {
    return Err("No binding found for variable: " + var_name)
  }
  match decl.kind {
    DeclKind::LamParam(..) =>
      return Err("Cannot inline lambda-bound variable: " + var_name)
    DeclKind::ModuleDef(def_index~) => {
      let def = flat_proj.defs[def_index]
      let init_text = @ast.print_term(def.1.kind)
      // Check for capture: would any free var in init be captured by an enclosing scope at the usage site?
      let init_fv = free_vars(def.1.kind, @immut/hashset.new())
      if free_names_would_rebind_at_node(
          g,
          flat_proj,
          source_map,
          def.1,
          node_id,
          init_fv,
        ) {
        return Err(
          "Cannot inline: would capture variables bound by enclosing lambda",
        )
      }
      // Check if this is the sole resolved reference.
      let refs = match module_def_references(g, def_index) {
        Ok(ids) => ids
        Err(e) => return Err(e)
      }
      if refs.length() <= 1 {
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
  ctx : EditContext[@ast.Term],
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
  // Find all references resolved to this binding.
  let g = @scope.build(flat_proj, registry, source_map)
  let ref_ids = match module_def_references(g, def_index) {
    Ok(ids) => ids
    Err(e) => return Err(e)
  }
  // Check for capture: would any free var in init be captured by an enclosing scope at any reference site?
  let init_fv = free_vars(def.1.kind, @immut/hashset.new())
  for rid in ref_ids {
    if free_names_would_rebind_at_node(
        g,
        flat_proj,
        source_map,
        def.1,
        rid,
        init_fv,
      ) {
      return Err(
        "Cannot inline: would capture variables bound by enclosing lambda",
      )
    }
  }
  // Build replacement edits for all references (reverse document order)
  let edits : Array[SpanEdit] = []
  // Collect reference ranges, sorted by position (descending)
  let ref_ranges : Array[(Int, Int)] = []
  for rid in ref_ids {
    if source_map.get_range(rid) is Some(r) {
      ref_ranges.push((r.start, r.end))
    }
  }
  ref_ranges.sort_by(fn(a, b) { b.0.compare(a.0) })
  for rr in ref_ranges {
    edits.push({ start: rr.0, delete_len: rr.1 - rr.0, inserted: init_text })
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
