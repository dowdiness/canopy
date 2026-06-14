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
/// Whether moving `source_node` (an init expression) to `target_node_id` would
/// rebind any of its free vars — i.e. some free var resolves to a different
/// declaration at the target site than at the source. The target resolution uses
/// the scope graph's per-(node,scope) cutoffs (`@scope.resolve_name_at`), so it
/// is correct for nested-block scopes, not a single root-relative cutoff.
fn free_names_would_rebind_at_node(
  g : @scope.ScopeGraph,
  source_node : ProjNode[@ast.Term],
  target_node_id : NodeId,
  free_names : @immut/hashset.HashSet[String],
) -> Bool {
  let subtree : Map[NodeId, ProjNode[@ast.Term]] = {}
  @core.collect_registry(source_node, subtree)
  free_names
  .iter()
  .any(fn(v) {
    let target_decl = @scope.resolve_name_at(g, target_node_id, v).map(fn(d) {
      d.id
    })
    free_name_would_rebind_to(g, source_node, subtree, v, target_decl)
  })
}

///|
/// Whether moving `source_node` to the END of the root module (where extract
/// inserts a new top-level `let`) would rebind any of its free vars. The target
/// resolution is root-module-end (`@scope.resolve_at_module_root_end`), which is
/// total even when the module body is a synthetic `Unit`.
fn free_names_would_rebind_at_module_end(
  g : @scope.ScopeGraph,
  source_node : ProjNode[@ast.Term],
  free_names : @immut/hashset.HashSet[String],
) -> Bool {
  let subtree : Map[NodeId, ProjNode[@ast.Term]] = {}
  @core.collect_registry(source_node, subtree)
  free_names
  .iter()
  .any(fn(v) {
    let target_decl = @scope.resolve_at_module_root_end(g, v).map(fn(d) { d.id })
    free_name_would_rebind_to(g, source_node, subtree, v, target_decl)
  })
}

///|
/// Whether any free occurrence of `name` in `source_node` currently resolves to
/// a declaration other than `target_decl` (the declaration `name` would resolve
/// to at the move target). Occurrences bound WITHIN `source_node` — to a lambda
/// param or a nested-block def in the init — are excluded: moving the init does
/// not change their binding. `subtree` is the registry of all nodes under
/// `source_node` (built once by the caller via `@core.collect_registry`), used
/// to test that "bound within". An unbound occurrence rebinds iff the target
/// binds the name.
fn free_name_would_rebind_to(
  g : @scope.ScopeGraph,
  source_node : ProjNode[@ast.Term],
  subtree : Map[NodeId, ProjNode[@ast.Term]],
  name : String,
  target_decl : @scope.DeclId?,
) -> Bool {
  let var_ids : Array[NodeId] = []
  collect_var_usages(source_node, name, var_ids)
  var_ids.any(fn(vid) {
    match @scope.declaration(g, vid) {
      // Bound inside the init (its binder is in the subtree) → unaffected.
      Some(d) =>
        if subtree.contains(d.node_id) {
          false
        } else {
          Some(d.id) != target_decl
        }
      // Free/unbound at source → rebinds iff the target site binds the name.
      None => target_decl is Some(_)
    }
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
  module_projection.definition_index().binding_for_node(init_node_id)
}
