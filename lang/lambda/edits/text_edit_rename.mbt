///|
fn compute_rename(
  ctx : EditContext[@ast.Term],
  node_id : NodeId,
  new_name : String,
) -> EditResult raise EditError {
  match ctx.registry.get(node_id) {
    Some(n) =>
      match n.kind {
        @ast.Term::Var(old_name) =>
          rename_from_var(ctx, node_id, old_name, new_name)
        @ast.Term::Lam(old_name, _) => {
          let g = @scope.build(ctx.registry, ctx.source_map)
          rename_lam_param(ctx, g, node_id, n, old_name, new_name)
        }
        _ => rename_binding_by_id(ctx, node_id, new_name)
      }
    None => rename_binding_by_id(ctx, node_id, new_name)
  }
}

///|
fn is_identifier_code(code : UInt16) -> Bool {
  let ch = code.to_int()
  (ch >= 'a'.to_int() && ch <= 'z'.to_int()) ||
  (ch >= 'A'.to_int() && ch <= 'Z'.to_int()) ||
  (ch >= '0'.to_int() && ch <= '9'.to_int()) ||
  ch == '_'.to_int()
}

///|
fn name_matches_at(source : String, pos : Int, name : String) -> Bool {
  if pos < 0 || pos + name.length() > source.length() {
    false
  } else {
    // Mutable flag keeps the code-unit comparison allocation-free.
    let mut matches = true
    // Manual index loop stops at the first mismatch without slicing.
    for i = 0; i < name.length(); i = i + 1 {
      if source[pos + i] != name[i] {
        matches = false
        break
      }
    }
    matches
  }
}

///|
fn has_identifier_boundaries(source : String, start : Int, end : Int) -> Bool {
  let left_ok = start == 0 || !is_identifier_code(source[start - 1])
  let right_ok = end >= source.length() || !is_identifier_code(source[end])
  left_ok && right_ok
}

///|
fn tight_name_range(
  source : String,
  range : @loomcore.Range,
  name : String,
) -> (Int, Int) raise EditError {
  guard !(name.length() == 0 || range.end - range.start < name.length()) else {
    raise SourceSpanMissing(
      detail="Cannot rename: identifier range does not contain name",
    )
  }
  let last = range.end - name.length()
  // Manual range scan returns the first bounded occurrence without allocating candidates.
  for pos = range.start; pos <= last; pos = pos + 1 {
    let end = pos + name.length()
    if name_matches_at(source, pos, name) &&
      has_identifier_boundaries(source, pos, end) {
      return (pos, end)
    }
  }
  raise SourceSpanMissing(
    detail="Cannot rename: identifier range does not contain '" + name + "'",
  )
}

///|
fn ref_edit_range(
  ctx : EditContext[@ast.Term],
  node_id : NodeId,
  old_name : String,
) -> (Int, Int) raise EditError {
  guard ctx.source_map.get_range(node_id) is Some(r) else {
    raise NodeNotInSourceMap(action="Rename reference", node_id~)
  }
  tight_name_range(ctx.source_text, r, old_name)
}

///|
fn lambda_param_references(
  g : @scope.ScopeGraph,
  lam_id : NodeId,
) -> Array[NodeId] raise EditError {
  for decl in g.decls {
    match decl.kind {
      @scope.DeclKind::LamParam(lam_id=decl_lam_id) if decl_lam_id == lam_id =>
        return @scope.references(g, decl.id)
      _ => ()
    }
  }
  raise BindingNotFound(action="Lambda param references", node_id=lam_id)
}

///|
fn lam_scope_id(g : @scope.ScopeGraph, lam_id : NodeId) -> @scope.ScopeId? {
  g.decls
  .iter()
  .find_first(fn(decl) {
    match decl.kind {
      @scope.DeclKind::LamParam(lam_id=decl_lam_id) => decl_lam_id == lam_id
      _ => false
    }
  })
  .map(fn(decl) { decl.scope })
}

///|
fn new_name_captured_before_lam(
  g : @scope.ScopeGraph,
  ref_id : NodeId,
  new_name : String,
  lam_id : NodeId,
) -> Bool {
  guard scope_id_for_node(g, ref_id) is Some(start_scope) else { return false }
  guard lam_scope_id(g, lam_id) is Some(stop_scope) else { return false }
  // Stateful cursor walks parent links until the lambda's declaring scope.
  let mut cur : @scope.ScopeId? = Some(start_scope)
  // `while` is used because each step depends on the previous scope's parent.
  while cur is Some(sid) {
    let @scope.ScopeId(si) = sid
    let scope = g.scopes[si]
    for did in scope.decl_ids {
      let @scope.DeclId(di) = did
      let decl = g.decls[di]
      if decl.name == new_name {
        return true
      }
    }
    if sid == stop_scope {
      return false
    }
    cur = scope.parent
  }
  false
}

///|
/// Rename a Lam's parameter and all bound Var occurrences in its body.
fn rename_lam_param(
  ctx : EditContext[@ast.Term],
  g : @scope.ScopeGraph,
  lam_id : NodeId,
  lam_node : ProjNode[@ast.Term],
  old_name : String,
  new_name : String,
) -> EditResult raise EditError {
  let source_map = ctx.source_map
  // Resolve via scope graph; fall back to structural body walk if empty.
  let scope_ref_ids = lambda_param_references(g, lam_id)
  let ref_ids = if scope_ref_ids.length() == 0 && lam_node.children.length() > 0 {
    let walk_ids : Array[NodeId] = []
    collect_var_usages(lam_node.children[0], old_name, walk_ids)
    walk_ids
  } else {
    scope_ref_ids
  }
  // Guard: check if new_name is free in the lambda body — renaming would capture it.
  if lam_node.kind is @ast.Term::Lam(_, _) {
    // Include the Lam node itself in the subtree so refs resolving to this
    // lambda's parameter are "inside" and excluded by references_outside_subtree.
    let lam_subtree = subtree_node_ids(lam_node)
    let body_refs = @scope.references_outside_subtree(
      g,
      lam_subtree,
      registry=Some(ctx.registry),
    )
    guard !body_refs.any(fn(r) { r.name == new_name }) else {
      raise CaptureViolation(
        detail="Cannot rename: would capture free variable '" + new_name + "'",
      )
    }
  }
  // Guard: an inner binder with the target name would capture renamed uses.
  if new_name != old_name {
    for ref_id in ref_ids {
      guard !new_name_captured_before_lam(g, ref_id, new_name, lam_id) else {
        raise CaptureViolation(
          detail="Cannot rename: '" +
            new_name +
            "' is bound by an inner scope at a usage site",
        )
      }
    }
  }
  let edits : Array[SpanEdit] = []
  // Get param token span
  match source_map.get_token_span(lam_id, @lambda_proj.PARAM_ROLE) {
    Some(param_range) =>
      edits.push({
        start: param_range.start,
        delete_len: param_range.end - param_range.start,
        inserted: new_name,
      })
    None =>
      // Fallback: if no token span, re-render the whole Lam
      match (lam_node.kind, source_map.get_range(lam_id)) {
        (@ast.Term::Lam(_, body), Some(range)) => {
          let new_kind = @ast.Term::Lam(new_name, body)
          let new_text = @ast.print_term(new_kind)
          return Some(
            (
              [
                {
                  start: range.start,
                  delete_len: range.end - range.start,
                  inserted: new_text,
                },
              ],
              RestoreCursor,
            ),
          )
        }
        _ => raise NodeNotInSourceMap(action="Rename lambda", node_id=lam_id)
      }
  }
  // Add edits for each identity-resolved reference, collecting tight name
  // ranges first so parser trivia around the VarRef is preserved.
  let var_ranges : Array[(Int, Int)] = []
  // Push loop lets us abort on the first invalid range before emitting edits.
  for vid in ref_ids {
    var_ranges.push(ref_edit_range(ctx, vid, old_name))
  }
  // Sort descending by position for reverse-order application
  var_ranges.sort_by(fn(a, b) { b.0.compare(a.0) })
  for vr in var_ranges {
    edits.push({ start: vr.0, delete_len: vr.1 - vr.0, inserted: new_name })
  }
  // Sort all edits by start position descending (param edit might be first)
  edits.sort_by(fn(a, b) { b.start.compare(a.start) })
  Some((edits, RestoreCursor))
}

///|
using @scope {type DeclKind}

///|
/// Rename a variable by resolving its binder and renaming at the definition site + all usages.
fn rename_from_var(
  ctx : EditContext[@ast.Term],
  var_node_id : NodeId,
  old_name : String,
  new_name : String,
) -> EditResult raise EditError {
  let g = @scope.build(ctx.registry, ctx.source_map)
  guard @scope.declaration(g, var_node_id) is Some(decl) else {
    raise BindingNotFound(action="Rename from var", node_id=var_node_id)
  }
  match decl.kind {
    DeclKind::LamParam(lam_id~) => {
      guard ctx.registry.get(lam_id) is Some(lam_node) else {
        raise NodeNotFound(action="Rename lambda", node_id=lam_id)
      }
      rename_lam_param(ctx, g, lam_id, lam_node, old_name, new_name)
    }
    // The decl is already the block-aware declaration the var resolves to;
    // thread it straight through (its `def_index` is scope-relative and must
    // NOT be re-interpreted against the root module's defs).
    DeclKind::ModuleDef(_) =>
      rename_module_binding(ctx, g, decl, old_name, new_name)
  }
}

///|
/// Rename a module binding by its binding_node_id. Resolves the binder to its
/// graph declaration by structural node id, so a block-local LetDef binder
/// renames its own scope's binding rather than a root def at the same index.
fn rename_binding_by_id(
  ctx : EditContext[@ast.Term],
  binding_node_id : NodeId,
  new_name : String,
) -> EditResult raise EditError {
  let g = @scope.build(ctx.registry, ctx.source_map)
  let decl = module_def_decl_for_binding(g, binding_node_id)
  rename_module_binding(ctx, g, decl, decl.name, new_name)
}

///|
/// Core rename logic for a module-level binding (top-level OR block-local).
/// Operates on the resolved `decl` and the graph that produced it — never on a
/// root-relative `def_index` — so every lookup (references, binder location,
/// sibling collision) stays scoped to the declaration's own block.
///
/// Capture analysis is conservative (sound — never mis-renames — but may reject
/// some legal renames; precise scope-bounded analysis is tracked in
/// docs/TODO.md §20). It rejects in both directions:
/// - D's own references rebinding OUTWARD: `new_name` visible in any enclosing
///   scope at a usage site (`name_captured_at_node`), including an ancestor the
///   renamed binder would shadow;
/// - an existing `new_name` use captured INWARD: a `Var(new_name)` inside D's
///   region resolving outside it (or free) that the renamed binder would shadow
///   (`rename_captures_existing_use`).
/// The inward check over-approximates (e.g. a same-scope use before D, or D's own
/// initializer, is rejected though sequentially safe).
fn rename_module_binding(
  ctx : EditContext[@ast.Term],
  g : @scope.ScopeGraph,
  decl : @scope.Decl,
  old_name : String,
  new_name : String,
) -> EditResult raise EditError {
  let source_map = ctx.source_map
  // No-op rename: nothing to edit, and dup/capture checks do not apply.
  guard new_name != old_name else { return Some(([], RestoreCursor)) }
  // Guard: a sibling binding in the SAME scope already uses new_name. Keyed on
  // the declaration's scope (block-local aware), not the root module's defs.
  guard !g.decls
    .iter()
    .any(fn(d2) {
      d2.scope == decl.scope && d2.id != decl.id && d2.name == new_name
    }) else {
    raise ScopeViolation(
      detail="Cannot rename: binding '" +
        new_name +
        "' already exists in this scope",
    )
  }
  // Guard: an EXISTING new_name use inside the decl's region would be captured
  // by the renamed binder (e.g. a block body `y` resolving to an outer `y`).
  guard !rename_captures_existing_use(g, decl, new_name) else {
    raise CaptureViolation(
      detail="Cannot rename: '" +
        new_name +
        "' is already used at a site the renamed binding would capture",
    )
  }
  // References resolved to THIS declaration (identity-based, shadowing-correct).
  let ref_ids = @scope.references(g, decl.id)
  // Guard: new_name would be captured by an enclosing scope at a usage site.
  guard !ref_ids
    .iter()
    .any(fn(ref_id) { name_captured_at_node(g, ref_id, new_name) }) else {
    raise ScopeViolation(
      detail="Cannot rename: '" +
        new_name +
        "' is bound by an enclosing scope at a usage site",
    )
  }
  let edits : Array[SpanEdit] = []
  // `@scope.binder_span` locates the binder block-locally (it reads
  // `LET_DEF_NAME_ROLE` off the decl's own `LetDef` node and only falls back to
  // the root `module_name_role` for a root-scope decl).
  guard @scope.binder_span(g, decl, source_map) is Some(range) else {
    raise SourceSpanMissing(
      detail="No token span for binding name: " + decl.name,
    )
  }
  edits.push({
    start: range.start,
    delete_len: range.end - range.start,
    inserted: new_name,
  })
  let ref_ranges : Array[(Int, Int)] = []
  // Push loop lets us abort on the first invalid range before emitting edits.
  for rid in ref_ids {
    ref_ranges.push(ref_edit_range(ctx, rid, old_name))
  }
  // Sort descending by position
  ref_ranges.sort_by(fn(a, b) { b.0.compare(a.0) })
  for rr in ref_ranges {
    edits.push({ start: rr.0, delete_len: rr.1 - rr.0, inserted: new_name })
  }
  // Sort all edits descending
  edits.sort_by(fn(a, b) { b.start.compare(a.start) })
  Some((edits, RestoreCursor))
}
