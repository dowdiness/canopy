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
/// Rename a Lam's parameter and all bound Var occurrences in its body.
fn rename_lam_param(
  ctx : EditContext[@ast.Term],
  lam_id : NodeId,
  lam_node : ProjNode[@ast.Term],
  old_name : String,
  new_name : String,
) -> Result[(Array[SpanEdit], FocusHint)?, String] {
  let source_map = ctx.source_map
  // Guard: check if new_name is free in the lambda body — renaming would capture it
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
  // Find all bound Var occurrences in the body
  let var_ids : Array[NodeId] = []
  for child in lam_node.children {
    collect_var_usages(child, old_name, var_ids)
  }
  // Add edits for each var, collecting ranges first
  let var_ranges : Array[(Int, Int)] = []
  for vid in var_ids {
    if source_map.get_range(vid) is Some(r) {
      var_ranges.push((r.start, r.end))
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
  let g = @scope.build(ctx.flat_proj, ctx.registry, ctx.source_map)
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
      // Find the Module node in the registry
      let mut module_id : NodeId? = None
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
  let def_index = match find_def_index(ctx.flat_proj, binding_node_id) {
    Ok(i) => i
    Err(e) => return Err(e)
  }
  let old_name = ctx.flat_proj.defs[def_index].0
  // Find Module node
  let mut module_id : NodeId? = None
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
  let { source_map, registry, flat_proj, .. } = ctx
  // Guard: check if another binding already uses new_name
  for i, def in flat_proj.defs {
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
  let g = @scope.build(flat_proj, registry, source_map)
  let ref_ids = match module_def_references(g, def_index) {
    Ok(ids) => ids
    Err(e) => return Err(e)
  }
  // Guard: check if new_name would be captured by an enclosing lambda at any reference site
  for ref_id in ref_ids {
    let ref_lam_env = collect_lam_env(ref_id, registry)
    if ref_lam_env.contains(new_name) {
      return Err(
        "Cannot rename: '" +
        new_name +
        "' is bound by an enclosing lambda at a usage site",
      )
    }
  }
  let edits : Array[SpanEdit] = []
  // Get the name token span
  let role = @lambda_proj.module_name_role(def_index)
  match source_map.get_token_span(module_id, role) {
    Some(name_range) =>
      edits.push({
        start: name_range.start,
        delete_len: name_range.end - name_range.start,
        inserted: new_name,
      })
    None =>
      return Err(
        "No token span for binding name at def index " + def_index.to_string(),
      )
  }
  let ref_ranges : Array[(Int, Int)] = []
  for rid in ref_ids {
    if source_map.get_range(rid) is Some(r) {
      ref_ranges.push((r.start, r.end))
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
