///|
/// Normalize a scope-graph Decl to (tag, node_id, def_index); def_index = -1
/// for lambda params.
fn norm_decl(decl : @scope.Decl) -> (String, NodeId, Int) {
  match decl.kind {
    DeclKind::LamParam(lam_id~) => ("lam", lam_id, -1)
    DeclKind::ModuleDef(def_index~) => ("module", decl.node_id, def_index)
  }
}

///|
/// Find first Var named `name` (helper for locators).
fn find_var(root : @core.ProjNode[@ast.Term], name : String) -> NodeId {
  let mut found : NodeId? = None
  fn walk(n : @core.ProjNode[@ast.Term]) -> Unit {
    if found is Some(_) {
      return
    }
    if n.kind is @ast.Term::Var(x) && x == name {
      found = Some(n.id())
    }
    for c in n.children {
      walk(c)
    }
  }

  walk(root)
  found.unwrap()
}

///|
/// Build a scope graph for a source string and return the parsed root, its
/// flat projection, and the graph. (The ModuleProjection is the structural source of
/// truth for module binder identities — it is built independently of the
/// `declaration` query under test.)
fn graph_of(
  text : String,
) -> (
  @core.ProjNode[@ast.Term],
  @lambda_proj.ModuleProjection,
  @scope.ScopeGraph,
) raise {
  let (proj, fp, g, _sm) = graph_and_sm_of(text)
  (proj, fp, g)
}

///|
/// Like `graph_of`, but also populates token spans and returns the `SourceMap`,
/// so callers can exercise `@scope.binder_span` (the Option-D binder-location
/// accessor). Builds the proj from the SyntaxNode so `populate_token_spans` has
/// a syntax tree to walk.
fn graph_and_sm_of(
  text : String,
) -> (
  @core.ProjNode[@ast.Term],
  @lambda_proj.ModuleProjection,
  @scope.ScopeGraph,
  SourceMap,
) raise {
  let (cst, _errs) = @parser.parse_cst(text)
  let syntax = @seam.SyntaxNode::from_cst(cst)
  let proj = to_proj_node(syntax, Ref(0))
  let fp = @lambda_proj.ModuleProjection::from_proj_node(proj)
  let sm = SourceMap::from_ast(proj)
  populate_token_spans(sm, syntax, proj)
  let registry = scope_test_registry(proj)
  let g = @scope.build(registry, sm)
  (proj, fp, g, sm)
}

// The following tests certify that `@scope.declaration` resolves each lambda
// binding rule to the FROZEN, hand-derived expected declaration. Each expected
// value is reasoned out from the source string and the binding rules
// (sequential module scope with later-wins shadowing; lambda params shadow
// module defs; a def's own init cannot see itself), never by a second
// `declaration` call. `inspect` targets scalars only (tag String, def_index
// Int, identity Bool), since the repo derives Debug/Eq, not Show.
//
// Binder-identity asymmetry: for LAMBDA cases the resolved `decl.node_id` is
// checked against the Lam node located STRUCTURALLY in the tree (`proj.id()` /
// `proj.children[..]`), independent of the ModuleProjection — a genuine non-circular
// check (case 6 distinguishes inner vs outer). For MODULE cases identity is
// carried by `def_index` alone: these fixtures build the ModuleProjection via
// `from_proj_node`, where `decl.node_id == fp.defs[def_index].3` holds by
// construction, so re-asserting it would be tautological. The PRODUCTION-path
// meaning of a module binder id is pinned separately by the `to_module_projection`
// contract test at the bottom of this file.

///|
test "declaration() resolves a Var to its enclosing Lam param" {
  // (x) => x — the body Var binds to the lambda parameter (the Lam node itself).
  let (proj, _fp, g) = graph_of("(x) => x")
  let ref_id = proj.children[0].id() // body Var x
  guard @scope.declaration(g, ref_id) is Some(d) else {
    fail("expected resolved declaration")
  }
  let (tag, binder, def_index) = norm_decl(d)
  inspect(tag, content="lam")
  inspect(def_index, content="-1")
  inspect(binder == proj.id(), content="true") // binder is the Lam node
}

///|
test "declaration() resolves a body Var to its module def" {
  // let x = 0\nx — the body Var binds to def 0.
  let (proj, _fp, g) = graph_of("let x = 0\nx")
  let ref_id = find_var(proj, "x") // body Var (init is Int 0, no Var)
  guard @scope.declaration(g, ref_id) is Some(d) else {
    fail("expected resolved declaration")
  }
  let (tag, _binder, def_index) = norm_decl(d)
  inspect(tag, content="module")
  inspect(def_index, content="0") // module identity = def_index (see header note)
}

///|
test "declaration() leaves a self-referential def init unbound" {
  // let x = x\nx — the first Var (the init `x`) cannot see def 0 from inside
  // def 0 (cutoff = 0), so it is free.
  let (proj, _fp, g) = graph_of("let x = x\nx")
  let ref_id = find_var(proj, "x") // first Var = def 0's init
  inspect(@scope.declaration(g, ref_id) is None, content="true")
}

///|
test "declaration() picks the latest shadowing module def" {
  // let x = 1\nlet x = 2\nx — the body Var binds to the LATER def (index 1).
  let (proj, _fp, g) = graph_of("let x = 1\nlet x = 2\nx")
  let ref_id = find_var(proj, "x") // body Var (both inits are Ints)
  guard @scope.declaration(g, ref_id) is Some(d) else {
    fail("expected resolved declaration")
  }
  let (tag, _binder, def_index) = norm_decl(d)
  inspect(tag, content="module")
  inspect(def_index, content="1") // latest of two same-name defs
}

///|
test "declaration() does not let an earlier def see a later one" {
  // let a = b\nlet b = 1\na — `b` in def 0's init cannot see def 1 (cutoff = 0),
  // so it is free.
  let (proj, _fp, g) = graph_of("let a = b\nlet b = 1\na")
  let ref_id = find_var(proj, "b") // the `b` in `a = b`
  inspect(@scope.declaration(g, ref_id) is None, content="true")
}

///|
test "declaration() resolves to the nearest enclosing Lam under shadowing" {
  // (x) => (x) => x — the innermost Var binds to the INNER lambda param.
  let (proj, _fp, g) = graph_of("(x) => (x) => x")
  let ref_id = find_var(proj, "x") // the single (innermost) Var
  guard @scope.declaration(g, ref_id) is Some(d) else {
    fail("expected resolved declaration")
  }
  let (tag, binder, def_index) = norm_decl(d)
  inspect(tag, content="lam")
  inspect(def_index, content="-1")
  inspect(binder == proj.children[0].id(), content="true") // inner Lam node
}

///|
test "declaration() lets a Lam param shadow a same-name module def" {
  // let x = 0\n(x) => x — the Var inside the lambda binds to the lambda param,
  // NOT the module def.
  let (proj, _fp, g) = graph_of("let x = 0\n(x) => x")
  let ref_id = find_var(proj, "x") // Var inside the body Lam
  guard @scope.declaration(g, ref_id) is Some(d) else {
    fail("expected resolved declaration")
  }
  let (tag, binder, def_index) = norm_decl(d)
  inspect(tag, content="lam")
  inspect(def_index, content="-1")
  let body_lam_id = proj.children[proj.children.length() - 1].id() // Module body
  inspect(binder == body_lam_id, content="true")
}

///|
test "declaration() resolves a later def's init to an earlier same-name def" {
  // let x = 1\nlet x = x\nx — the init Var of def 1 binds to def 0 (cutoff = 1
  // excludes def 1 itself), not to itself.
  let (proj, _fp, g) = graph_of("let x = 1\nlet x = x\nx")
  let ref_id = find_var(proj, "x") // first Var = def 1's init `x`
  guard @scope.declaration(g, ref_id) is Some(d) else {
    fail("expected resolved declaration")
  }
  let (tag, _binder, def_index) = norm_decl(d)
  inspect(tag, content="module")
  inspect(def_index, content="0") // def 1's init resolves to earlier def 0
}

///|
/// Build a scope graph through the PRODUCTION ModuleProjection pipeline — `to_module_projection`
/// (the live editor's path) rather than `from_proj_node` (used by `graph_of`
/// above). Both paths now assign module binder ids to real LetDef nodes; this
/// fixture exercises the production path that starts from flat entries and then
/// reconstructs those LetDef nodes.
fn production_graph_of(
  text : String,
) -> (
  @core.ProjNode[@ast.Term],
  Map[NodeId, ProjNode[@ast.Term]],
  @scope.ScopeGraph,
  SourceMap,
) raise {
  let (cst, _diags) = @parser.parse_cst(text)
  let syntax = @seam.SyntaxNode::from_cst(cst)
  let counter = Ref(0)
  // Production ModuleProjection: module binder ids (defs[i].3) are real LetDef node ids,
  // distinct from their init expression ids.
  let fp = @lambda_proj.to_module_projection(syntax, counter)
  // Reconstruct the Module ProjNode exactly as the live `cached_proj_node` memo
  // does; binding ids become first-class LetDef nodes in this tree.
  let proj = fp.to_proj_node(counter)
  let sm = SourceMap::from_ast(proj)
  // Token spans are stored on the reconstructed LetDef/Module/Lam nodes, so
  // `binder_span` works on the production path too — its locator is the binder
  // token span, not the full LetDef node range.
  populate_token_spans(sm, syntax, proj)
  let registry = scope_test_registry(proj)
  let g = @scope.build(registry, sm)
  (proj, registry, g, sm)
}

///|
/// Option-D binder-location contract on the PRODUCTION path (docs/TODO.md §20,
/// resolved). Through `to_module_projection` a module def's `Decl.node_id` is now the
/// real LetDef node id, but locating the binder still goes through
/// `@scope.binder_span`: it resolves the LetDef node's `"name"` token span
/// (with the module `"name:<def_index>"` fallback during migration), not the
/// full node range. The companion assertion that this location is
/// pipeline-independent lives in the cross-pipeline PBT.
test "production path: module binder located via binder_span (Option D, supersedes §20 gap)" {
  let (proj, registry, g, sm) = production_graph_of("let x = 0\nx")
  let ref_id = find_var(proj, "x") // body Var x
  guard @scope.declaration(g, ref_id) is Some(d) else {
    fail("expected resolved declaration")
  }
  let (tag, binder, def_index) = norm_decl(d)
  inspect(tag, content="module")
  inspect(def_index, content="0")
  // `node_id` is structural identity and now points at the LetDef row.
  inspect(registry.get(binder) is Some(_), content="true")
  // The locator remains the binder token: "let x = 0" → name token "x" at 4..5.
  guard @scope.binder_span(g, d, sm) is Some(r)
  inspect(r.start, content="4")
  inspect(r.end, content="5")
}
