///|
fn compute_extract_to_let(
  ctx : EditContext[@ast.Term],
  node_id : NodeId,
  var_name : String,
) -> EditResult {
  let { source_text, definition_index, .. } = ctx
  let module_view = edit_module_view(ctx)
  let (node, range) = ctx.resolve(node_id) catch {
    ResolveError(e) => return Err(e)
  }
  match ensure_replaceable_node_range(ctx, node_id, node, range) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  let g = @scope.build(ctx.registry, ctx.source_map)
  let fv = free_vars(node.kind, @immut/hashset.new())
  // Build edits
  let expr_text = @ast.print_term(node.kind)
  let let_text = "let " + var_name + " = " + expr_text + "\n"
  // If the node lives in a nested block scope, insert into that block rather
  // than hoisting to the root. Walk ancestor scopes to find the innermost
  // enclosing Module (handles empty blocks and lambda-nested nodes correctly).
  // NOTE: block detection must run BEFORE the root-relative capture check;
  // the block sub-paths have their own guards.
  if find_enclosing_block(g, ctx.registry, node_id) is Some(block_node) {
    let block_view = EditModuleView::from_root(block_node)
    let block_body_start = match block_view.final_expr {
      Some(body) =>
        match ctx.source_map.get_range(body.id()) {
          Some(r) => r.start
          None => source_text.length()
        }
      None => source_text.length()
    }
    if range.start >= block_body_start {
      // Node is in the block body. The let is inserted immediately before the
      // body, so free vars of the expression remain in scope — no rebind check.
      let block_body_end = match block_view.final_expr {
        Some(body) =>
          match ctx.source_map.get_range(body.id()) {
            Some(r) => r.end
            None => source_text.length()
          }
        None => source_text.length()
      }
      // Guard: inserting `let var_name = expr` makes var_name visible throughout
      // the new body. Any Var(var_name) in the body OUTSIDE the extracted
      // expression — whether currently resolved or free — must be refused:
      // a resolved use would be retargeted; a free use would become bound.
      // Both change semantics.
      if block_view.final_expr is Some(body_node) {
        let node_subtree = subtree_node_ids(node)
        let body_var_ids : Array[NodeId] = []
        collect_var_usages(body_node, var_name, body_var_ids)
        for vid in body_var_ids {
          if !node_subtree.contains(vid) {
            return Err(
              "Cannot extract: '" +
              var_name +
              "' appears in the block body outside the selected expression",
            )
          }
        }
        // Guard: node may sit inside a lambda nested in the block body. The
        // let is inserted before the lambda, outside its param's scope, so
        // any free var of the extracted expression that resolves via the
        // lambda param would become unbound after extraction.
        if free_names_would_rebind_at_node(g, node, body_node.id(), fv) {
          return Err(
            "Cannot extract: expression captures lambda-bound variables",
          )
        }
      }
      let prefix = source_text[block_body_start:range.start].to_owned()
      let suffix = source_text[range.end:block_body_end].to_owned()
      let new_body_text = let_text + prefix + var_name + suffix
      return Ok(
        Some(
          (
            [
              {
                start: block_body_start,
                delete_len: block_body_end - block_body_start,
                inserted: new_body_text,
              },
            ],
            MoveCursor(
              position=block_body_start + let_text.length() + prefix.length(),
            ),
          ),
        ),
      )
    } else {
      // Node is in a block def. The let is inserted before ALL block defs, so
      // block-local free vars (not in scope before the first def) would become
      // unbound. Apply the root-relative capture check as a conservative guard.
      let would_capture = if module_view.defs.is_empty() {
        free_names_captured_at_use_sites(g, node, fv)
      } else {
        free_names_would_rebind_at_module_end(g, definition_index, node, fv)
      }
      if would_capture {
        return Err("Cannot extract: expression captures lambda-bound variables")
      }
      // Guard: inserting `let var_name = expr` before all block defs makes
      // var_name visible throughout the block. Any Var(var_name) in the block
      // outside the extracted expression — whether currently resolved or free —
      // must be refused: a resolved use would be retargeted; a free use would
      // become bound. Both change semantics.
      let node_subtree = subtree_node_ids(node)
      let block_var_ids : Array[NodeId] = []
      collect_var_usages(block_node, var_name, block_var_ids)
      for vid in block_var_ids {
        if !node_subtree.contains(vid) {
          return Err(
            "Cannot extract: '" +
            var_name +
            "' appears in this block outside the selected expression",
          )
        }
      }
      guard block_node.children.length() > 0 else {
        return Err("Cannot extract: block has no children")
      }
      let block_start = block_node.children[0].start
      return Ok(
        Some(
          (
            [
              { start: block_start, delete_len: 0, inserted: let_text },
              {
                start: range.start,
                delete_len: range.end - range.start,
                inserted: var_name,
              },
            ],
            // let_text inserted at block_start < range.start, so range shifts right
            MoveCursor(position=range.start + let_text.length()),
          ),
        ),
      )
    }
  }
  // Root-level extraction: apply the standard capture check.
  let would_capture = if module_view.defs.is_empty() {
    free_names_captured_at_use_sites(g, node, fv)
  } else {
    free_names_would_rebind_at_module_end(g, definition_index, node, fv)
  }
  if would_capture {
    return Err("Cannot extract: expression captures lambda-bound variables")
  }
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
        match ctx.source_map.get_range(body.id()) {
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
          match ctx.source_map.get_range(body.id()) {
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
  let { source_text, .. } = ctx
  let (node, range) = ctx.resolve(node_id) catch {
    ResolveError(e) => return Err(e)
  }
  guard node.kind is @ast.Term::Var(var_name) else {
    return Err("InlineDefinition requires a Var node")
  }
  // Resolve the binding
  let g = @scope.build(ctx.registry, ctx.source_map)
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
      let init_text = match
        binding_inline_text(source_text, ctx.source_map, def) {
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
          get_binding_text_range(source_text, ctx.source_map, def) {
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
  let { source_text, .. } = ctx
  // Find all references resolved to this binding.
  let g = @scope.build(ctx.registry, ctx.source_map)
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
    match binding_inline_text(source_text, ctx.source_map, def) {
      Ok(text) => text
      Err(e) => return Err(e)
    }
  }
  // Build replacement edits for all references (reverse document order)
  let edits : Array[SpanEdit] = []
  // Collect reference ranges, sorted by position (descending)
  let ref_ranges : Array[(Int, Int)] = []
  for rid in ref_ids {
    if ctx.source_map.get_range(rid) is Some(r) {
      ref_ranges.push((r.start, r.end))
    }
  }
  ref_ranges.sort_by(fn(a, b) { b.0.compare(a.0) })
  for rr in ref_ranges {
    edits.push({ start: rr.0, delete_len: rr.1 - rr.0, inserted: init_text })
  }
  // Delete the binding
  let (let_start, binding_end) = match
    get_binding_text_range(source_text, ctx.source_map, def) {
    Ok(r) => r
    Err(e) => return Err(e)
  }
  let (del_start, del_len) = binding_delete_range(
    source_text, let_start, binding_end,
  )
  edits.push({ start: del_start, delete_len: del_len, inserted: "" })
  Ok(Some((edits, RestoreCursor)))
}
