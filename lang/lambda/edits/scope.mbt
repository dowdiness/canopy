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
fn scope_id_for_node(
  g : @scope.ScopeGraph,
  node_id : NodeId,
) -> @scope.ScopeId? {
  @scope.scope_for_node(g, node_id)
}

///|
fn root_scope_id(g : @scope.ScopeGraph) -> @scope.ScopeId? {
  g.scopes.iter().find_first(fn(s) { s.parent is None }).map(fn(s) { s.id })
}

///|
/// Walk up ancestor scopes from `node_id` and return the innermost
/// enclosing `Term::Module` ProjNode that is not the root module.
///
/// The scope builder records nested Module nodes with their own inner
/// scope in `node_scope` (the Module node itself maps to the scope it
/// introduces), while Lam nodes keep their outer scope. So for a given
/// non-root scope `sid`, finding a Module whose `node_scope` entry equals
/// `sid` identifies the block that introduced that scope. Walking up the
/// parent chain handles both empty blocks (no ModuleDef decls) and nodes
/// nested inside a lambda within a block.
///
/// Returns None if the node is at root scope or no Module ancestor exists.
fn find_enclosing_block(
  g : @scope.ScopeGraph,
  registry : Map[NodeId, ProjNode[@ast.Term]],
  node_id : NodeId,
) -> ProjNode[@ast.Term]? {
  guard root_scope_id(g) is Some(root) else { return None }
  let mut cur = @scope.scope_for_node(g, node_id)
  while cur is Some(sid) && sid != root {
    let module_opt = registry
      .values()
      .find_first(fn(n) {
        n.kind is @ast.Term::Module(_, _) &&
        @scope.scope_for_node(g, n.id()) is Some(nsid) &&
        nsid == sid
      })
    if module_opt is Some(block) {
      return Some(block)
    }
    let @scope.ScopeId(si) = sid
    cur = g.scopes[si].parent
  }
  None
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
fn declaration_id_for_name_at_node(
  g : @scope.ScopeGraph,
  node_id : NodeId,
  name : String,
) -> @scope.DeclId? {
  @scope.declaration_for_name_at(g, node_id, name).map(fn(decl) { decl.id })
}
