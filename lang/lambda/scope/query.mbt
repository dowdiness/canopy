///|
/// The declaration a reference resolves to, or None if unresolved (free).
pub fn declaration(g : ScopeGraph, ref_node : @core.NodeId) -> Decl? {
  g.refs
  .iter()
  .find_first(fn(r) { r.node_id == ref_node })
  .bind(fn(r) { r.resolution.decl })
  .map(fn(did) {
    let DeclId(di) = did
    g.decls[di]
  })
}

///|
/// All reference NodeIds whose resolution points at the decl at `decl_node`.
/// Identity-based (NOT a name match), so shadowing is respected.
/// Reserved API surface; consumer migration deferred (see design spec).
pub fn references(
  g : ScopeGraph,
  decl_node : @core.NodeId,
) -> Array[@core.NodeId] {
  guard g.decls.iter().find_first(fn(d) { d.node_id == decl_node })
    is Some(target) else {
    return []
  }
  let tid = target.id
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
  let start = match g.refs.iter().find_first(fn(r) { r.node_id == node }) {
    Some(r) => Some(r.scope)
    None =>
      g.decls
      .iter()
      .find_first(fn(d) { d.node_id == node })
      .map(fn(d) { d.scope })
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
