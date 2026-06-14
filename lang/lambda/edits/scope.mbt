///|
/// Identity-based references to a module definition, delegated to the canonical
/// scope graph query. The old name-based usage scan could over-match a later
/// shadowing definition's body; this helper first locates the graph-local
/// `DeclId` for the requested module def, then asks `@scope.references` for only
/// refs resolved to that declaration.
fn module_def_references(
  g : @scope.ScopeGraph,
  def_index : Int,
) -> Result[Array[NodeId], String] {
  for decl in g.decls {
    match decl.kind {
      @scope.DeclKind::ModuleDef(def_index=i) if i == def_index =>
        return Ok(@scope.references(g, decl.id))
      _ => ()
    }
  }
  Err("No scope declaration for module def index " + def_index.to_string())
}

///|
/// Recursively collect Var nodes matching the given name, stopping at shadowing Lam params.
fn collect_var_usages(
  node : ProjNode[@ast.Term],
  name : String,
  results : Array[NodeId],
) -> Unit {
  match node.kind {
    @ast.Term::Var(x) => if x == name { results.push(node.id()) }
    @ast.Term::Lam(param, _) =>
      if param != name {
        for child in node.children {
          collect_var_usages(child, name, results)
        }
      }
    _ =>
      for child in node.children {
        collect_var_usages(child, name, results)
      }
  }
}

///|
fn name_captured_at_node(
  g : @scope.ScopeGraph,
  node_id : NodeId,
  name : String,
) -> Bool {
  @scope.enclosing_env(g, node_id).contains(name)
}

///|
fn free_names_captured_at_use_sites(
  g : @scope.ScopeGraph,
  node : ProjNode[@ast.Term],
  free_names : @immut/hashset.HashSet[String],
) -> Bool {
  let mut captured = false
  free_names.each(fn(v) {
    let var_ids : Array[NodeId] = []
    collect_var_usages(node, v, var_ids)
    if var_ids.any(fn(vid) { name_captured_at_node(g, vid, v) }) {
      captured = true
    }
  })
  captured
}

///|
fn def_cutoff_at_node(
  module_projection : ModuleProjection,
  source_map : SourceMap,
  node_id : NodeId,
) -> Int {
  guard source_map.get_range(node_id) is Some(r) else {
    return module_projection.defs.length()
  }
  module_projection.defs
  .search_by(fn(def) {
    source_map.get_range(def.1.id()) is Some(dr) &&
    r.start >= dr.start &&
    r.start < dr.end
  })
  .unwrap_or(module_projection.defs.length())
}

///|
fn scope_id_for_node(
  g : @scope.ScopeGraph,
  node_id : NodeId,
) -> @scope.ScopeId? {
  match g.refs.iter().find_first(fn(r) { r.node_id == node_id }) {
    Some(r) => Some(r.scope)
    None =>
      g.decls
      .iter()
      .find_first(fn(d) { d.node_id == node_id })
      .map(fn(d) { d.scope })
  }
}

///|
fn root_scope_id(g : @scope.ScopeGraph) -> @scope.ScopeId? {
  g.scopes.iter().find_first(fn(s) { s.parent is None }).map(fn(s) { s.id })
}

///|
/// Whether `scope` is `ancestor` itself or any descendant of it — i.e. whether
/// `ancestor` lies on `scope`'s parent chain. Used to test if a reference sits
/// inside a declaration's visibility region (its declaring scope's subtree).
fn scope_is_within(
  g : @scope.ScopeGraph,
  scope : @scope.ScopeId,
  ancestor : @scope.ScopeId,
) -> Bool {
  let mut cur : @scope.ScopeId? = Some(scope)
  while cur is Some(sid) {
    if sid == ancestor {
      return true
    }
    let @scope.ScopeId(si) = sid
    cur = g.scopes[si].parent
  }
  false
}

///|
/// Whether renaming `decl` to `new_name` would CAPTURE an existing reference: a
/// `Var(new_name)` used inside `decl`'s scope subtree that currently resolves to
/// a binding OUTSIDE that subtree (or is free). After the rename the new local
/// binder would shadow that outer binding and silently re-target the reference,
/// so such a rename must be rejected. References already resolving inside the
/// subtree are unaffected; same-scope siblings are handled by the dup-name guard.
fn rename_captures_existing_use(
  g : @scope.ScopeGraph,
  decl : @scope.Decl,
  new_name : String,
) -> Bool {
  g.refs
  .iter()
  .any(fn(r) {
    r.name == new_name &&
    scope_is_within(g, r.scope, decl.scope) &&
    (match r.resolution.decl {
      // Free use inside the region → would become bound to the renamed decl.
      None => true
      // Bound to a binding outside the region → would be shadowed (captured).
      Some(rid) => {
        let @scope.DeclId(di) = rid
        !scope_is_within(g, g.decls[di].scope, decl.scope)
      }
    })
  })
}

///|
fn declaration_id_for_name_from_scope(
  g : @scope.ScopeGraph,
  start_scope : @scope.ScopeId,
  cutoff : Int,
  name : String,
) -> @scope.DeclId? {
  let mut cur : @scope.ScopeId? = Some(start_scope)
  while cur is Some(sid) {
    let @scope.ScopeId(si) = sid
    let scope = g.scopes[si]
    let mut hit : @scope.DeclId? = None
    for did in scope.decl_ids {
      let @scope.DeclId(di) = did
      let decl = g.decls[di]
      if decl.name == name {
        match decl.kind {
          @scope.DeclKind::ModuleDef(def_index~) =>
            if def_index < cutoff {
              hit = Some(did)
            }
          @scope.DeclKind::LamParam(_) => hit = Some(did)
        }
      }
    }
    if hit is Some(_) {
      return hit
    }
    cur = scope.parent
  }
  None
}

///|
fn declaration_id_for_name_at_node(
  g : @scope.ScopeGraph,
  module_projection : ModuleProjection,
  source_map : SourceMap,
  node_id : NodeId,
  name : String,
) -> @scope.DeclId? {
  guard scope_id_for_node(g, node_id) is Some(start_scope) else { return None }
  declaration_id_for_name_from_scope(
    g,
    start_scope,
    def_cutoff_at_node(module_projection, source_map, node_id),
    name,
  )
}

///|
fn declaration_id_for_name_at_module_end(
  g : @scope.ScopeGraph,
  module_projection : ModuleProjection,
  name : String,
) -> @scope.DeclId? {
  guard root_scope_id(g) is Some(root_scope) else { return None }
  declaration_id_for_name_from_scope(
    g,
    root_scope,
    module_projection.defs.length(),
    name,
  )
}

///|
fn free_names_would_rebind_at_node(
  g : @scope.ScopeGraph,
  module_projection : ModuleProjection,
  source_map : SourceMap,
  source_node : ProjNode[@ast.Term],
  target_node_id : NodeId,
  free_names : @immut/hashset.HashSet[String],
) -> Bool {
  let mut rebound = false
  free_names.each(fn(v) {
    let target_decl = declaration_id_for_name_at_node(
      g, module_projection, source_map, target_node_id, v,
    )
    if free_name_would_rebind_to(g, source_node, v, target_decl) {
      rebound = true
    }
  })
  rebound
}

///|
fn free_names_would_rebind_at_module_end(
  g : @scope.ScopeGraph,
  module_projection : ModuleProjection,
  source_node : ProjNode[@ast.Term],
  free_names : @immut/hashset.HashSet[String],
) -> Bool {
  let mut rebound = false
  free_names.each(fn(v) {
    let target_decl = declaration_id_for_name_at_module_end(
      g, module_projection, v,
    )
    if free_name_would_rebind_to(g, source_node, v, target_decl) {
      rebound = true
    }
  })
  rebound
}

///|
fn free_name_would_rebind_to(
  g : @scope.ScopeGraph,
  source_node : ProjNode[@ast.Term],
  name : String,
  target_decl : @scope.DeclId?,
) -> Bool {
  let var_ids : Array[NodeId] = []
  collect_var_usages(source_node, name, var_ids)
  var_ids.any(fn(vid) {
    @scope.declaration(g, vid).map(fn(d) { d.id }) != target_decl
  })
}

///|
/// Look up the ModuleProjection binding NodeId for a given init expression or LetDef NodeId.
/// Init-expression callers are mapped to the parent LetDef id; direct LetDef
/// callers return the binding id unchanged.
pub fn find_binding_for_init(
  init_node_id : NodeId,
  module_projection : ModuleProjection,
) -> (NodeId, Int)? {
  for i, def in module_projection.defs {
    if def.3 == init_node_id || def.1.id() == init_node_id {
      return Some((def.3, i))
    }
  }
  None
}
