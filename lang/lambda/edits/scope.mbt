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
/// Look up the FlatProj binding NodeId for a given init expression NodeId.
/// The UI selects init expression ProjNodes (children of Module); this function
/// maps that to the corresponding binding NodeId needed by binding-level operations.
pub fn find_binding_for_init(
  init_node_id : NodeId,
  flat_proj : FlatProj,
) -> (NodeId, Int)? {
  for i, def in flat_proj.defs {
    if def.1.id() == init_node_id {
      return Some((def.3, i))
    }
  }
  None
}

///|
/// Collect Lam parameter names in scope at a node position (walking up the tree).
pub fn collect_lam_env(
  node_id : NodeId,
  registry : Map[NodeId, ProjNode[@ast.Term]],
) -> @immut/hashset.HashSet[String] {
  let mut env : @immut/hashset.HashSet[String] = @immut/hashset.new()
  fn walk_up(nid : NodeId) {
    for pid, pnode in registry {
      for child in pnode.children {
        if child.id() == nid {
          if pnode.kind is @ast.Term::Lam(param, _) {
            env = env.add(param)
          }
          walk_up(pid)
          return
        }
      }
    }
  }
  walk_up(node_id)
  env
}
