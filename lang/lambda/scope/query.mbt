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
/// All reference NodeIds whose resolution points at the declaration `decl`.
/// Identity-based (keyed on `DeclId`, NOT a name match), so shadowing is
/// respected. Keying on `DeclId` rather than `Decl.node_id` is deliberate:
/// a module def's `node_id` is a synthetic, non-tree handle (see `Decl`), so a
/// `NodeId`-keyed lookup silently preserved that broken contract. `DeclId` is
/// the stable graph-local identity (`declaration(..).id` yields it).
pub fn references(g : ScopeGraph, decl : DeclId) -> Array[@core.NodeId] {
  [
    for r in g.refs if r.resolution.decl is Some(rid) && rid == decl => {
      r.node_id
    }
  ]
}

///|
/// The source span of a declaration's binder name, or None when the token span
/// was not recorded (e.g. a `SourceMap` built via `from_ast` without
/// `populate_token_spans`). This is the uniform "where is this binder?" primitive
/// for go-to-definition, binder highlighting, and rename:
/// - lambda param: the `"param"` token span on the `Lam` node;
/// - module def: the `"name:<def_index>"` token span on `module_node_id`.
/// Failure is always `None`, never a wrong location.
pub fn binder_span(
  g : ScopeGraph,
  decl : Decl,
  source_map : @core.SourceMap,
) -> @loomcore.Range? {
  match decl.kind {
    LamParam(lam_id~) =>
      source_map.get_token_span(lam_id, @lambda_proj.PARAM_ROLE)
    ModuleDef(def_index~) =>
      source_map.get_token_span(
        g.module_node_id,
        @lambda_proj.module_name_role(def_index),
      )
  }
}

///|
/// Go-to-definition: given a cursor `position`, return the source span of the
/// binder that the reference under the cursor resolves to, or None.
///
/// Resolution is by projection-node range: `position` maps to the innermost
/// node whose source range contains it (half-open), and a jump happens when
/// that node is a resolved reference. The range used is the reference's *node*
/// span, not its identifier *token* span — and `ParenExpr` deliberately widens
/// a wrapped expression's span to cover the parentheses (see `proj_node.mbt`,
/// "keep the outer ParenExpr span so positions on ( and ) are covered"). So a
/// caret on the `(` / `)` of `(x)` resolves to `x` and jumps to its binder.
/// That is intentional and consistent with the editor's position→node mapping;
/// the resolved target is always the correct binder. A stricter
/// identifier-token-only restriction would require recording Var token spans
/// and is intentionally not done.
///
/// Returns None for a free variable, a position in no reference node (between
/// tokens / on surrounding whitespace), or a `SourceMap` without populated
/// token spans.
pub fn go_to_definition(
  g : ScopeGraph,
  source_map : @core.SourceMap,
  position : Int,
) -> @loomcore.Range? {
  guard source_map.innermost_node_at(position) is Some(ref_id) else {
    return None
  }
  guard declaration(g, ref_id) is Some(decl) else { return None }
  binder_span(g, decl, source_map)
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
