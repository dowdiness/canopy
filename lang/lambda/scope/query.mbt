///|
/// The declaration a reference resolves to, or None if unresolved (free).
pub fn declaration(g : ScopeGraph, ref_node : @core.NodeId) -> Decl? {
  for r in g.refs {
    if r.node_id == ref_node {
      return match r.resolution.decl {
        Some(did) => {
          let DeclId(di) = did
          Some(g.decls[di])
        }
        None => None
      }
    }
  }
  None
}

///|
/// All reference NodeIds whose resolution points at the decl at `decl_node`.
/// Identity-based (NOT a name match), so shadowing is respected.
/// Reserved API surface; consumer migration deferred (see design spec).
pub fn references(
  g : ScopeGraph,
  decl_node : @core.NodeId,
) -> Array[@core.NodeId] {
  let mut target : DeclId? = None
  for d in g.decls {
    if d.node_id == decl_node {
      target = Some(d.id)
      break
    }
  }
  guard target is Some(tid) else { return [] }
  [
    for r in g.refs if r.resolution.decl is Some(rid) && rid == tid => r.node_id
  ]
}

///|
/// The set of names bound in scopes enclosing `node` — the FULL lexical
/// environment (lambda params AND module defs). This is a SUPERSET of the
/// existing `collect_lam_env` (which returns only lambda params); it is NOT a
/// drop-in replacement. Set semantics (membership, not order).
/// Reserved API surface; consumer migration deferred (see design spec).
pub fn enclosing_env(
  g : ScopeGraph,
  node : @core.NodeId,
) -> @immut/hashset.HashSet[String] {
  let mut start : ScopeId? = None
  for r in g.refs {
    if r.node_id == node {
      start = Some(r.scope)
      break
    }
  }
  if start is None {
    for d in g.decls {
      if d.node_id == node {
        start = Some(d.scope)
        break
      }
    }
  }
  let mut env : @immut/hashset.HashSet[String] = @immut/hashset.new()
  let mut cur = start
  while cur is Some(sid) {
    let ScopeId(si) = sid
    let scope = g.scopes[si]
    for did in scope.decl_ids {
      let DeclId(di) = did
      env = env.add(g.decls[di].name)
    }
    cur = scope.parent
  }
  env
}
