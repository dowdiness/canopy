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
