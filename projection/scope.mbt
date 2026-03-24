///|
/// The kind of binding site a variable resolves to.
pub(all) enum BindingSite {
  LamBinder(lam_id~ : NodeId)
  ModuleBinder(binding_node_id~ : NodeId, def_index~ : Int)
} derive(Show, Eq)

///|
/// Resolve which binding site a Var node refers to.
/// Checks enclosing Lam params first, then Module defs in sequential scope order.
pub fn resolve_binder(
  var_node_id : NodeId,
  var_name : String,
  flat_proj : FlatProj,
  registry : Map[NodeId, ProjNode[@ast.Term]],
  source_map : SourceMap,
) -> BindingSite? {
  // Check if it's inside a Lam that binds this name (walk up)
  let lam_binder = find_enclosing_lam_binder(var_node_id, var_name, registry)
  if lam_binder is Some(_) {
    return lam_binder
  }
  // Check Module defs — find which def/body contains this var
  let var_pos = match source_map.get_range(var_node_id) {
    Some(r) => r.start
    None => return None
  }
  // Find which def index (or body) this var is in
  let mut containing_def_index = flat_proj.defs.length() // body sentinel
  for i, def in flat_proj.defs {
    match source_map.get_range(def.1.id()) {
      Some(r) =>
        if var_pos >= r.start && var_pos < r.end {
          containing_def_index = i
          break
        }
      None => ()
    }
  }
  // Walk backwards from containing_def_index to find matching def
  // (sequential scope: def i is in scope for defs i+1..n and body)
  let search_end = if containing_def_index < flat_proj.defs.length() {
    containing_def_index
  } else {
    flat_proj.defs.length()
  }
  for i = search_end - 1; i >= 0; i = i - 1 {
    if flat_proj.defs[i].0 == var_name {
      return Some(
        ModuleBinder(binding_node_id=flat_proj.defs[i].3, def_index=i),
      )
    }
  }
  None
}

///|
/// Walk up the tree to find an enclosing Lam that binds the given name.
fn find_enclosing_lam_binder(
  node_id : NodeId,
  name : String,
  registry : Map[NodeId, ProjNode[@ast.Term]],
) -> BindingSite? {
  for pid, pnode in registry {
    for child in pnode.children {
      if NodeId(child.node_id) == node_id {
        match pnode.kind {
          @ast.Term::Lam(param, _) =>
            if param == name {
              return Some(LamBinder(lam_id=pid))
            } else {
              return find_enclosing_lam_binder(pid, name, registry)
            }
          _ => return find_enclosing_lam_binder(pid, name, registry)
        }
      }
    }
  }
  None
}

///|
/// Find all Var nodes referencing the given name from scope_start_index onward
/// in the Module defs + body, respecting shadowing.
pub fn find_usages(
  var_name : String,
  scope_start_index : Int,
  flat_proj : FlatProj,
  registry : Map[NodeId, ProjNode[@ast.Term]],
) -> Array[NodeId] {
  let results : Array[NodeId] = []
  let mut shadowed = false
  for i = scope_start_index; i < flat_proj.defs.length(); i = i + 1 {
    let def = flat_proj.defs[i]
    // If this def shadows the name, stop
    if def.0 == var_name && i > scope_start_index {
      shadowed = true
      break
    }
    collect_var_usages(def.1, var_name, results)
  }
  // Check body only if not shadowed
  if not(shadowed) {
    match flat_proj.final_expr {
      Some(body) => collect_var_usages(body, var_name, results)
      None => ()
    }
  }
  results
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
        if NodeId(child.node_id) == nid {
          match pnode.kind {
            @ast.Term::Lam(param, _) => env = env.add(param)
            _ => ()
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
