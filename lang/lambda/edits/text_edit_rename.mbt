///|
fn compute_rename(
  ctx : EditContext[@ast.Term],
  node_id : NodeId,
  new_name : String,
) -> EditResult {
  match ctx.registry.get(node_id) {
    Some(n) =>
      match n.kind {
        @ast.Term::Var(old_name) =>
          rename_from_var(ctx, node_id, old_name, new_name)
        @ast.Term::Lam(old_name, _) =>
          rename_lam_param(ctx, node_id, n, old_name, new_name)
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
) -> Result[(Int, Int), String] {
  if name.length() == 0 || range.end - range.start < name.length() {
    return Err("Cannot rename: identifier range does not contain name")
  }
  let last = range.end - name.length()
  // Manual range scan returns the first bounded occurrence without allocating candidates.
  for pos = range.start; pos <= last; pos = pos + 1 {
    let end = pos + name.length()
    if name_matches_at(source, pos, name) &&
      has_identifier_boundaries(source, pos, end) {
      return Ok((pos, end))
    }
  }
  Err("Cannot rename: identifier range does not contain '" + name + "'")
}

///|
fn ref_edit_range(
  ctx : EditContext[@ast.Term],
  node_id : NodeId,
  old_name : String,
) -> Result[(Int, Int), String] {
  match ctx.source_map.get_range(node_id) {
    Some(r) => tight_name_range(ctx.source_text, r, old_name)
    None => Err("Cannot rename: reference not in source map")
  }
}

///|
fn lambda_param_references(
  g : @scope.ScopeGraph,
  lam_id : NodeId,
) -> Result[Array[NodeId], String] {
  for decl in g.decls {
    match decl.kind {
      @scope.DeclKind::LamParam(lam_id=decl_lam_id) if decl_lam_id == lam_id =>
        return Ok(@scope.references(g, decl.id))
      _ => ()
    }
  }
  Err("No scope declaration for lambda parameter")
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
  lam_id : NodeId,
  lam_node : ProjNode[@ast.Term],
  old_name : String,
  new_name : String,
) -> Result[(Array[SpanEdit], FocusHint)?, String] {
  let source_map = ctx.source_map
  let g = @scope.build(ctx.module_projection, ctx.registry, source_map)
  let ref_ids = match lambda_param_references(g, lam_id) {
    Ok(ids) => ids
    Err(e) => return Err(e)
  }
  // Guard: check if new_name is free in the lambda body — renaming would capture it.
  if lam_node.kind is @ast.Term::Lam(_, body) {
    let bound : @immut/hashset.HashSet[String] = @immut/hashset.new().add(
      old_name,
    )
    let body_fv = free_vars(body, bound)
    if body_fv.contains(new_name) {
      return Err(
        "Cannot rename: would capture free variable '" + new_name + "'",
      )
    }
  }
  // Guard: an inner binder with the target name would capture renamed uses.
  if new_name != old_name {
    for ref_id in ref_ids {
      if new_name_captured_before_lam(g, ref_id, new_name, lam_id) {
        return Err(
          "Cannot rename: '" +
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
          return Ok(
            Some(
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
            ),
          )
        }
        _ => return Err("Cannot rename: lambda not in source map")
      }
  }
  // Add edits for each identity-resolved reference, collecting tight name
  // ranges first so parser trivia around the VarRef is preserved.
  let var_ranges : Array[(Int, Int)] = []
  // Push loop lets us abort on the first invalid range before emitting edits.
  for vid in ref_ids {
    match ref_edit_range(ctx, vid, old_name) {
      Ok(r) => var_ranges.push(r)
      Err(e) => return Err(e)
    }
  }
  // Sort descending by position for reverse-order application
  var_ranges.sort_by(fn(a, b) { b.0.compare(a.0) })
  for vr in var_ranges {
    edits.push({ start: vr.0, delete_len: vr.1 - vr.0, inserted: new_name })
  }
  // Sort all edits by start position descending (param edit might be first)
  edits.sort_by(fn(a, b) { b.start.compare(a.start) })
  Ok(Some((edits, RestoreCursor)))
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
) -> Result[(Array[SpanEdit], FocusHint)?, String] {
  let g = @scope.build(ctx.module_projection, ctx.registry, ctx.source_map)
  guard @scope.declaration(g, var_node_id) is Some(decl) else {
    return Err("No binding found for variable: " + old_name)
  }
  match decl.kind {
    DeclKind::LamParam(lam_id~) =>
      match ctx.registry.get(lam_id) {
        Some(lam_node) =>
          rename_lam_param(ctx, lam_id, lam_node, old_name, new_name)
        None => Err("Lambda node not found in registry")
      }
    DeclKind::ModuleDef(def_index~) => {
      // Find the Module node in the registry.
      // Mutable slot records the first hit without materializing registry entries.
      let mut module_id : NodeId? = None
      // Manual scan can break as soon as the Module node is found.
      for pid, pnode in ctx.registry {
        if pnode.kind is @ast.Term::Module(_, _) {
          module_id = Some(pid)
          break
        }
      }
      match module_id {
        Some(mid) =>
          rename_module_binding(ctx, mid, def_index, old_name, new_name)
        None => Err("Module node not found in registry")
      }
    }
  }
}

///|
/// Rename a module binding by its binding_node_id.
fn rename_binding_by_id(
  ctx : EditContext[@ast.Term],
  binding_node_id : NodeId,
  new_name : String,
) -> Result[(Array[SpanEdit], FocusHint)?, String] {
  let def_index = match find_def_index(ctx.module_projection, binding_node_id) {
    Ok(i) => i
    Err(e) => return Err(e)
  }
  let old_name = ctx.module_projection.defs[def_index].0
  // Find Module node.
  // Mutable slot records the first hit without materializing registry entries.
  let mut module_id : NodeId? = None
  // Manual scan can break as soon as the Module node is found.
  for pid, pnode in ctx.registry {
    if pnode.kind is @ast.Term::Module(_, _) {
      module_id = Some(pid)
      break
    }
  }
  match module_id {
    Some(mid) => rename_module_binding(ctx, mid, def_index, old_name, new_name)
    None => Err("Module node not found in registry")
  }
}

///|
/// Core rename logic for a module-level binding: renames the binding name token + all usages.
fn rename_module_binding(
  ctx : EditContext[@ast.Term],
  module_id : NodeId,
  def_index : Int,
  old_name : String,
  new_name : String,
) -> Result[(Array[SpanEdit], FocusHint)?, String] {
  let { source_map, registry, module_projection, .. } = ctx
  // Guard: check if another binding already uses new_name
  for i, def in module_projection.defs {
    if i != def_index && def.0 == new_name {
      return Err(
        "Cannot rename: binding '" +
        new_name +
        "' already exists at index " +
        i.to_string(),
      )
    }
  }
  // Find all references resolved to this binding.
  let g = @scope.build(module_projection, registry, source_map)
  let ref_ids = match module_def_references(g, def_index) {
    Ok(ids) => ids
    Err(e) => return Err(e)
  }
  // Guard: check if new_name would be captured by an enclosing scope at any reference site
  for ref_id in ref_ids {
    if new_name != old_name && name_captured_at_node(g, ref_id, new_name) {
      return Err(
        "Cannot rename: '" +
        new_name +
        "' is bound by an enclosing lambda at a usage site",
      )
    }
  }
  let edits : Array[SpanEdit] = []
  // Get the binder-name token span. Prefer the first-class LetDef node; keep
  // the module-level `name:<i>` lookup as a migration fallback for older maps.
  let binding_node_id = module_projection.defs[def_index].3
  let name_range = match
    source_map.get_token_span(binding_node_id, @lambda_proj.LET_DEF_NAME_ROLE) {
    Some(r) => Some(r)
    None =>
      source_map.get_token_span(
        module_id,
        @lambda_proj.module_name_role(def_index),
      )
  }
  match name_range {
    Some(range) =>
      edits.push({
        start: range.start,
        delete_len: range.end - range.start,
        inserted: new_name,
      })
    None =>
      return Err(
        "No token span for binding name at def index " + def_index.to_string(),
      )
  }
  let ref_ranges : Array[(Int, Int)] = []
  // Push loop lets us abort on the first invalid range before emitting edits.
  for rid in ref_ids {
    match ref_edit_range(ctx, rid, old_name) {
      Ok(r) => ref_ranges.push(r)
      Err(e) => return Err(e)
    }
  }
  // Sort descending by position
  ref_ranges.sort_by(fn(a, b) { b.0.compare(a.0) })
  for rr in ref_ranges {
    edits.push({ start: rr.0, delete_len: rr.1 - rr.0, inserted: new_name })
  }
  // Sort all edits descending
  edits.sort_by(fn(a, b) { b.start.compare(a.start) })
  Ok(Some((edits, RestoreCursor)))
}
