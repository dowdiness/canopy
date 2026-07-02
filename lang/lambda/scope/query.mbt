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
/// Resolve `name` as it would be seen from `node`, using the same per-module
/// sequential cutoffs captured when the scope graph was built.
pub fn declaration_for_name_at(
  g : ScopeGraph,
  node : @core.NodeId,
  name : String,
) -> Decl? {
  guard scope_for_node(g, node) is Some(start_scope) else { return None }
  guard g.node_cutoffs.get(node) is Some(cutoffs) else { return None }
  let mut cur : ScopeId? = Some(start_scope)
  while cur is Some(sid) {
    let ScopeId(si) = sid
    let scope = g.scopes[si]
    let hit = scope.decl_ids
      .rev_iter()
      .find_first(fn(did) {
        let DeclId(di) = did
        let decl = g.decls[di]
        decl.name == name &&
        (match decl.kind {
          ModuleDef(def_index~) =>
            cutoffs.get(sid) is Some(cutoff) && def_index < cutoff
          LamParam(_) => true
        })
      })
    if hit is Some(did) {
      let DeclId(di) = did
      return Some(g.decls[di])
    }
    cur = scope.parent
  }
  None
}

///|
/// The scope that the structural `node_id` belongs to. For a reference node,
/// this is the scope where resolution starts. For a module-definition binder
/// node, this is its declaring module scope. Lambda parameter declarations are
/// represented by the owning `Lam` node, which is also an expression node; for
/// that node this query returns the lambda expression's enclosing scope, while
/// the parameter's declaring scope is recorded on the corresponding `Decl`.
/// Returns `None` when the `node_id` was not recorded during scope-graph
/// construction.
pub fn scope_for_node(g : ScopeGraph, node_id : @core.NodeId) -> ScopeId? {
  g.node_scope.get(node_id)
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
/// The set of names bound in scopes enclosing `node` — the FULL lexical
/// environment (lambda params AND module defs). This is a SUPERSET of the
/// retired edits-package `collect_lam_env` (which returned only lambda params);
/// it is NOT a drop-in replacement. Set semantics (membership, not order).
pub fn enclosing_env(
  g : ScopeGraph,
  node : @core.NodeId,
) -> @immut/hashset.HashSet[String] {
  let start = scope_for_node(g, node)
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

///|
/// All Refs in the subtree whose resolution target lies OUTSIDE the subtree
/// (or is unresolved). This is the graph-backed equivalent of `free_vars`:
/// a Ref is "free relative to the subtree" when its `resolution.decl` is None
/// (unresolved) or when the resolved declaration's `node_id` is not in
/// `subtree_node_ids`.
///
/// Complexity is O(N_sub + R_relevant), where N_sub is the subtree size and
/// R_relevant is the total ref count across scopes containing subtree nodes
/// — much cheaper than a full O(R) scan when the subtree is small relative
/// to the graph.
///
/// Callers can filter by `ref.name` for per-variable rebind checks, compare
/// `ref.resolution.decl` against a target-site resolution, or group by name
/// for the free-name set.
///
/// Note: this includes Unbound refs (scope records them as unresolved
/// `resolution.decl = None`), while the deleted edit-layer `free_vars`
/// ignored Unbound entirely. Guards are therefore slightly more conservative
/// on alpha-reified trees — operations the old code allowed are now rejected.
/// Parsed Lambda trees never contain Unbound nodes, so production edit
/// behavior is unchanged. See `scope_resolution_differential_wbtest.mbt`
/// for the recorded divergence.
pub fn references_outside_subtree(
  g : ScopeGraph,
  subtree_node_ids : @immut/hashset.HashSet[@core.NodeId],
) -> Array[Ref] {
  // Collect distinct scopes containing subtree nodes.
  let mut seen : @immut/hashset.HashSet[ScopeId] = @immut/hashset.new()
  for nid in subtree_node_ids.iter() {
    match g.node_scope.get(nid) {
      Some(sid) => seen = seen.add(sid)
      None => continue
    }
  }
  let result : Array[Ref] = []
  for sid in seen.iter() {
    let ScopeId(si) = sid
    for rid in g.scopes[si].ref_ids {
      let RefId(ri) = rid
      let r = g.refs[ri]
      if subtree_node_ids.contains(r.node_id) {
        let is_outside = match r.resolution.decl {
          None => true
          Some(did) => {
            let DeclId(di) = did
            !subtree_node_ids.contains(g.decls[di].node_id)
          }
        }
        if is_outside {
          result.push(r)
        }
      }
    }
  }
  result
}

///|
/// Resolve `name` as it would be visible at the end of the module whose
/// ProjNode is `module_proj_node_id`. The builder records the full definition
/// count as the cutoff on the module node itself, so this delegates to
/// `declaration_for_name_at` — no separate recomputation from
/// `DefinitionIndex.length()`. Returns None when the name is not bound
/// (free or block-local). Caller must pass a Module ProjNode id; any other
/// node id silently performs at-position resolution via
/// `declaration_for_name_at`.
pub fn declaration_for_name_at_module_end(
  g : ScopeGraph,
  module_proj_node_id : @core.NodeId,
  name : String,
) -> Decl? {
  declaration_for_name_at(g, module_proj_node_id, name)
}
