///|
fn compute_extract_to_let(
  ctx : EditContext[@ast.Term],
  node_id : NodeId,
  var_name : String,
) -> EditResult {
  let { source_text, source_map, registry, definition_index } = ctx
  let module_view = edit_module_view(ctx)
  let (node, range) = match ctx.resolve(node_id) {
    Ok(r) => r
    Err(e) => return Err(e)
  }
  match ensure_replaceable_node_range(ctx, node_id, node, range) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  let g = @scope.build(registry, source_map)
  let fv = free_vars(node.kind, @immut/hashset.new())
  let would_capture = if module_view.defs.is_empty() {
    free_names_captured_at_use_sites(g, node, fv)
  } else {
    free_names_would_rebind_at_module_end(g, definition_index, node, fv)
  }
  if would_capture {
    return Err("Cannot extract: expression captures lambda-bound variables")
  }
  // Build edits
  let expr_text = @ast.print_term(node.kind)
  let let_text = "let " + var_name + " = " + expr_text + "\n"
  if module_view.defs.is_empty() && module_view.final_expr is Some(_) {
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
    let body_start = match module_view.final_expr {
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
      let body_end = match module_view.final_expr {
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
  let { source_text, source_map, registry, .. } = ctx
  let (node, range) = match ctx.resolve(node_id) {
    Ok(r) => r
    Err(e) => return Err(e)
  }
  guard node.kind is @ast.Term::Var(var_name) else {
    return Err("InlineDefinition requires a Var node")
  }
  // Resolve the binding
  let g = @scope.build(registry, source_map)
  guard @scope.declaration(g, node_id) is Some(decl) else {
    return Err("No binding found for variable: " + var_name)
  }
  match decl.kind {
    DeclKind::LamParam(..) =>
      return Err("Cannot inline lambda-bound variable: " + var_name)
    DeclKind::ModuleDef(_) => {
      let def = match edit_binding_for_decl(ctx, decl) {
        Ok(def) => def
        Err(e) => return Err(e)
      }
      let init_text = match binding_inline_text(source_text, source_map, def) {
        Ok(text) => text
        Err(e) => return Err(e)
      }
      // Check for capture: would any free var in init be captured by an enclosing scope at the usage site?
      let init_fv = free_vars(def.init.kind, @immut/hashset.new())
      if free_names_would_rebind_at_node(g, def.init, node_id, init_fv) {
        return Err(
          "Cannot inline: would capture variables bound by enclosing lambda",
        )
      }
      // Check if this is the sole resolved reference.
      let refs = @scope.references(g, decl.id)
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
  let { source_text, source_map, registry, .. } = ctx
  // Find all references resolved to this binding.
  let g = @scope.build(registry, source_map)
  let decl = match module_def_decl_for_binding(g, binding_node_id) {
    Ok(decl) => decl
    Err(e) => return Err(e)
  }
  let def = match edit_binding_for_decl(ctx, decl) {
    Ok(def) => def
    Err(e) => return Err(e)
  }
  let var_name = def.name
  let ref_ids = @scope.references(g, decl.id)
  // Check for capture: would any free var in init be captured by an enclosing scope at any reference site?
  let init_fv = free_vars(def.init.kind, @immut/hashset.new())
  for rid in ref_ids {
    if free_names_would_rebind_at_node(g, def.init, rid, init_fv) {
      return Err(
        "Cannot inline: would capture variables bound by enclosing lambda",
      )
    }
  }
  let init_text = if ref_ids.is_empty() {
    ""
  } else {
    match binding_inline_text(source_text, source_map, def) {
      Ok(text) => text
      Err(e) => return Err(e)
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
