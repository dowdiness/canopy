///|
fn module_def_decl_for_binding(
  g : @scope.ScopeGraph,
  binding_node_id : NodeId,
) -> Result[@scope.Decl, String] {
  match
    g.decls
    .iter()
    .find_first(fn(decl) {
      decl.node_id == binding_node_id &&
      decl.kind is @scope.DeclKind::ModuleDef(_)
    }) {
    Some(decl) => Ok(decl)
    None => Err("Binding not found: " + binding_node_id.to_string())
  }
}

///|
/// The sibling module-binding decl in `scope` at `target_index`, or None when no
/// `ModuleDef` in that scope holds that index. `def_index` is scope-local (the
/// builder assigns `ModuleDef(def_index=i)` per scope, root and nested block
/// alike), so adjacent indices in the SAME scope are the move-up/down neighbours
/// — this is what makes the binding move ops block-local-aware rather than
/// root-relative.
fn sibling_module_def_decl(
  g : @scope.ScopeGraph,
  scope : @scope.ScopeId,
  target_index : Int,
) -> @scope.Decl? {
  let @scope.ScopeId(si) = scope
  g.scopes[si].decl_ids
  .iter()
  .map(fn(did) {
    let @scope.DeclId(di) = did
    g.decls[di]
  })
  .find_first(fn(decl) {
    decl.kind is @scope.DeclKind::ModuleDef(def_index~) &&
    def_index == target_index
  })
}

///|
/// Whether `init` contains any reference to `name` that currently resolves in
/// the scope graph. Used in binding move ops: if a reference in one binding's
/// init currently resolves — whether to an earlier same-scope sibling, a
/// lambda parameter, or any outer-scope binding — swapping the two bindings
/// would silently re-target that reference to the moved binding. Returns false
/// only when every reference to `name` in `init` is free, meaning the swap
/// would improve them from free to bound (safe to allow).
fn init_ref_resolves(
  g : @scope.ScopeGraph,
  init : ProjNode[@ast.Term],
  name : String,
) -> Bool {
  let var_ids : Array[NodeId] = []
  collect_var_usages(init, name, var_ids)
  let subtree = subtree_node_ids(init)
  var_ids.any(fn(vid) {
    match @scope.declaration(g, vid) {
      Some(decl) if subtree.contains(decl.node_id) => false
      _ =>
        g.refs
        .iter()
        .any(fn(r) { r.node_id == vid && r.resolution.decl is Some(_) })
    }
  })
}

///|
fn[T] subtree_node_ids(node : ProjNode[T]) -> @immut/hashset.HashSet[NodeId] {
  let m : Map[NodeId, ProjNode[T]] = {}
  @core.collect_registry(node, m)
  @immut/hashset.HashSet::from_iter(m.keys())
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
  // A var occurrence whose binder is inside the subtree is locally bound —
  // not a real free use of the outer name — and must not trigger a capture report.
  let subtree = subtree_node_ids(node)
  free_names
  .iter()
  .any(fn(v) {
    let var_ids : Array[NodeId] = []
    collect_var_usages(node, v, var_ids)
    var_ids.any(fn(vid) {
      match @scope.declaration(g, vid) {
        Some(decl) if subtree.contains(decl.node_id) => false
        _ => name_captured_at_node(g, vid, v)
      }
    })
  })
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
/// Whether `scope_id` contains at least one ModuleDef decl (i.e. it is a
/// block/module scope, not a pure lambda scope). Used to distinguish nested
/// block scopes from lambda scopes when deciding the insertion target for
/// ExtractToLet.
fn scope_has_module_defs(
  g : @scope.ScopeGraph,
  scope_id : @scope.ScopeId,
) -> Bool {
  let @scope.ScopeId(si) = scope_id
  g.scopes[si].decl_ids
  .iter()
  .any(fn(did) {
    let @scope.DeclId(di) = did
    g.decls[di].kind is @scope.DeclKind::ModuleDef(_)
  })
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
  node_id : NodeId,
  name : String,
) -> @scope.DeclId? {
  @scope.declaration_for_name_at(g, node_id, name).map(fn(decl) { decl.id })
}

///|
fn declaration_id_for_name_at_module_end(
  g : @scope.ScopeGraph,
  definition_index : DefinitionIndex,
  name : String,
) -> @scope.DeclId? {
  guard root_scope_id(g) is Some(root_scope) else { return None }
  declaration_id_for_name_from_scope(
    g,
    root_scope,
    definition_index.length(),
    name,
  )
}

///|
fn free_names_would_rebind_at_node(
  g : @scope.ScopeGraph,
  source_node : ProjNode[@ast.Term],
  target_node_id : NodeId,
  free_names : @immut/hashset.HashSet[String],
) -> Bool {
  let subtree = subtree_node_ids(source_node)
  free_names
  .iter()
  .any(fn(v) {
    let target_decl = declaration_id_for_name_at_node(g, target_node_id, v)
    free_name_would_rebind_to(g, source_node, v, target_decl, subtree)
  })
}

///|
fn free_names_would_rebind_at_module_end(
  g : @scope.ScopeGraph,
  definition_index : DefinitionIndex,
  source_node : ProjNode[@ast.Term],
  free_names : @immut/hashset.HashSet[String],
) -> Bool {
  let subtree = subtree_node_ids(source_node)
  free_names
  .iter()
  .any(fn(v) {
    let target_decl = declaration_id_for_name_at_module_end(
      g, definition_index, v,
    )
    free_name_would_rebind_to(g, source_node, v, target_decl, subtree)
  })
}

///|
fn free_name_would_rebind_to(
  g : @scope.ScopeGraph,
  source_node : ProjNode[@ast.Term],
  name : String,
  target_decl : @scope.DeclId?,
  subtree : @immut/hashset.HashSet[NodeId],
) -> Bool {
  let var_ids : Array[NodeId] = []
  collect_var_usages(source_node, name, var_ids)
  var_ids.any(fn(vid) {
    match @scope.declaration(g, vid) {
      Some(decl) if subtree.contains(decl.node_id) => false
      decl_opt => decl_opt.map(fn(d) { d.id }) != target_decl
    }
  })
}

///|
/// Look up the module binding NodeId for a given init expression or LetDef NodeId.
/// Init-expression callers are mapped to the parent LetDef id; direct LetDef
/// callers return the binding id unchanged.
pub fn find_binding_for_init(
  init_node_id : NodeId,
  definition_index : DefinitionIndex,
) -> (NodeId, Int)? {
  definition_index.binding_for_node(init_node_id)
}
