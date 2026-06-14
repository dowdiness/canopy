///|
/// Resolve a `DeclId` (graph-local identity) to its `Decl` record. The single
/// place that unwraps the `DeclId` index, so the `g.decls[di]` lookup is not
/// re-spelled at every resolution site.
fn ScopeGraph::decl_of(self : ScopeGraph, did : DeclId) -> Decl {
  let DeclId(di) = did
  self.decls[di]
}

///|
/// The declaration a reference resolves to, or None if unresolved (free).
pub fn declaration(g : ScopeGraph, ref_node : @core.NodeId) -> Decl? {
  g.refs
  .iter()
  .find_first(fn(r) { r.node_id == ref_node })
  .bind(fn(r) { r.resolution.decl })
  .map(fn(did) { g.decl_of(did) })
}

///|
/// All reference NodeIds whose resolution points at the declaration `decl`.
/// Identity-based (keyed on `DeclId`, NOT a name match), so shadowing is
/// respected. Keying on `DeclId` rather than `Decl.node_id` is deliberate:
/// references resolve to declarations, not to whichever structural node id a
/// declaration currently uses. `DeclId` is the stable graph-local identity
/// (`declaration(..).id` yields it).
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
/// - module def: the `"name"` token span on the `LetDef` node, with the
///   module-level `"name:<def_index>"` span as a migration fallback.
/// Failure is always `None`, never a wrong location. The `module_name_role`
/// fallback spans live only on the ROOT module node (`g.module_node_id`), so it
/// is consulted ONLY for a root-scope decl; a nested-block decl with no `LetDef`
/// span returns `None` rather than a root-relative (wrong) location — preserving
/// the "never a wrong location" guarantee for block-local binders.
pub fn binder_span(
  g : ScopeGraph,
  decl : Decl,
  source_map : @core.SourceMap,
) -> @loomcore.Range? {
  match decl.kind {
    LamParam(lam_id~) =>
      source_map.get_token_span(lam_id, @lambda_proj.PARAM_ROLE)
    ModuleDef(def_index~) =>
      match
        source_map.get_token_span(decl.node_id, @lambda_proj.LET_DEF_NAME_ROLE) {
        Some(range) => Some(range)
        None => {
          let ScopeId(si) = decl.scope
          if g.scopes[si].parent is None {
            source_map.get_token_span(
              g.module_node_id,
              @lambda_proj.module_name_role(def_index),
            )
          } else {
            None
          }
        }
      }
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
/// Hypothetical-position resolution: the declaration that `name` would resolve
/// to if referenced AT `node_id`'s position — i.e. from `node_id`'s scope, with
/// `node_id`'s per-(node,scope) cutoffs. This is the exact resolver pass 3 uses
/// for real references, so it correctly respects nested-block sequential cutoffs
/// (unlike a single root-relative cutoff). `None` when `node_id` was not walked
/// (absent from `node_scope`) or `name` is unbound there.
///
/// Callers must pass the actual site where a moved/inlined expression would land
/// (e.g. the replacement use site for inline), not an enclosing binding node.
pub fn resolve_name_at(
  g : ScopeGraph,
  node_id : @core.NodeId,
  name : String,
) -> Decl? {
  guard g.node_scope.get(node_id) is Some(start) else { return None }
  let cutoffs = g.node_cutoffs.get(node_id).unwrap()
  resolve_in(g.scopes, g.decls, name, start, cutoffs).decl.map(fn(did) {
    g.decl_of(did)
  })
}

///|
/// The declaration `name` resolves to at the END of the root module — after all
/// root-level definitions, where a newly inserted top-level `let` (extract) would
/// sit. Resolves in the root scope with cutoff = the count of root `ModuleDef`
/// decls, so every root def is visible. Unlike deriving a body node from
/// `module_projection.final_expr` (a synthetic `Unit` body has no real node),
/// this is total: it never silently skips the capture check.
pub fn resolve_at_module_root_end(g : ScopeGraph, name : String) -> Decl? {
  guard g.scopes.iter().find_first(fn(s) { s.parent is None }) is Some(root) else {
    return None
  }
  let cutoff = root.decl_ids
    .iter()
    .filter(fn(did) { g.decl_of(did).kind is ModuleDef(_) })
    .count()
  let cutoffs : Map[ScopeId, Int] = {}
  cutoffs[root.id] = cutoff
  resolve_in(g.scopes, g.decls, name, root.id, cutoffs).decl.map(fn(did) {
    g.decl_of(did)
  })
}

///|
/// The set of names bound in scopes enclosing `node` — the FULL lexical
/// environment (lambda params AND module defs). This is a SUPERSET of the
/// retired edits-package `collect_lam_env` (which returned only lambda params);
/// it is NOT a drop-in replacement. Set semantics (membership, not order).
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
      env = env.add(g.decl_of(did).name)
    }
    cur = scope.parent
  }
  env
}
