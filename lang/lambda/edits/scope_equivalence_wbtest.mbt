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
/// flat projection, and the graph. (The FlatProj is the structural source of
/// truth for module binder identities — it is built independently of the
/// `declaration` query under test.)
fn graph_of(
  text : String,
) -> (@core.ProjNode[@ast.Term], FlatProj, @scope.ScopeGraph) raise {
  let (proj, _errs) = parse_to_proj_node(text)
  let fp = FlatProj::from_proj_node(proj)
  let sm = SourceMap::from_ast(proj)
  let registry = scope_test_registry(proj)
  let g = @scope.build(fp, registry, sm)
  (proj, fp, g)
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
// `proj.children[..]`), independent of the FlatProj — a genuine non-circular
// check (case 6 distinguishes inner vs outer). For MODULE cases identity is
// carried by `def_index` alone: these fixtures build the FlatProj via
// `from_proj_node`, where `decl.node_id == fp.defs[def_index].3` holds by
// construction, so re-asserting it would be tautological. The PRODUCTION-path
// meaning of a module binder id is pinned separately by the `to_flat_proj`
// contract test at the bottom of this file.

///|
test "declaration() resolves a Var to its enclosing Lam param" {
  // λx. x — the body Var binds to the lambda parameter (the Lam node itself).
  let (proj, _fp, g) = graph_of("λx. x")
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
  // λx. λx. x — the innermost Var binds to the INNER lambda param.
  let (proj, _fp, g) = graph_of("λx. λx. x")
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
  // let x = 0\nλx. x — the Var inside the lambda binds to the lambda param,
  // NOT the module def.
  let (proj, _fp, g) = graph_of("let x = 0\nλx. x")
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
/// Build a scope graph through the PRODUCTION FlatProj pipeline — `to_flat_proj`
/// (the live editor's path) rather than `from_proj_node` (used by `graph_of`
/// above). The two paths assign module binder ids differently: `from_proj_node`
/// reuses the init node's id, whereas `to_flat_proj` allocates a synthetic
/// binder id (`defs[i].3`) that is threaded into NO node of the reconstructed
/// tree. This fixture exists solely to exercise that production path.
fn production_graph_of(
  text : String,
) -> (
  @core.ProjNode[@ast.Term],
  Map[NodeId, ProjNode[@ast.Term]],
  @scope.ScopeGraph,
) raise {
  let (cst, _diags) = @parser.parse_cst(text)
  let syntax = @seam.SyntaxNode::from_cst(cst)
  let counter = Ref(0)
  // Production FlatProj: module binder ids (defs[i].3) are freshly allocated,
  // distinct from any init node id.
  let fp = @lambda_proj.to_flat_proj(syntax, counter)
  // Reconstruct the Module ProjNode exactly as the live `cached_proj_node` memo
  // does; the synthetic binder ids are not placed into this tree.
  let proj = fp.to_proj_node(counter)
  let sm = SourceMap::from_ast(proj)
  let registry = scope_test_registry(proj)
  let g = @scope.build(fp, registry, sm)
  (proj, registry, g)
}

///|
/// KNOWN-GAP record — NOT a desired contract. Through the production
/// `to_flat_proj` pipeline, a module def's `Decl.node_id` is a synthetic
/// FlatProj binder id that occupies no registry node — so it does NOT satisfy
/// the "occupies a projection node" property that the lambda-param case does.
/// The `Decl` doc in `lang/lambda/scope/graph.mbt` records this as a known
/// divergence to reconcile; this test pins it so it is not silently
/// load-bearing. When a consumer first needs a module binder to land on a real
/// tree node (e.g. go-to-definition) and the fix makes binder ids real nodes,
/// this `is None` assertion will flip to `is Some(_)` — and that failure is the
/// INTENDED signal that the invariant was restored, not a regression. See also
/// the deferred cross-pipeline PBT (docs/TODO.md §20).
test "module Decl.node_id is a synthetic non-registry id on the production path (known gap vs graph.mbt invariant)" {
  let (proj, registry, g) = production_graph_of("let x = 0\nx")
  let ref_id = find_var(proj, "x") // body Var x
  guard @scope.declaration(g, ref_id) is Some(d) else {
    fail("expected resolved declaration")
  }
  let (tag, binder, def_index) = norm_decl(d)
  inspect(tag, content="module")
  inspect(def_index, content="0")
  // The divergence: the resolved module binder id is NOT a node in the registry.
  inspect(registry.get(binder) is None, content="true")
}
