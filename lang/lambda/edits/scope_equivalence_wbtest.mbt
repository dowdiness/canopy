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
/// Build the generic ProjNode/registry/SourceMap scope path for a source
/// string and return the parsed root plus graph. Module binder identity comes
/// from the LetDef nodes in the ProjNode tree.
fn graph_of(
  text : String,
) -> (@core.ProjNode[@ast.Term], @scope.ScopeGraph) raise {
  let (proj, g, _sm) = graph_and_sm_of(text)
  (proj, g)
}

///|
/// Like `graph_of`, but also populates token spans and returns the `SourceMap`,
/// so callers can exercise `@scope.binder_span` (the Option-D binder-location
/// accessor). Builds the proj from the SyntaxNode so `populate_token_spans` has
/// a syntax tree to walk.
fn graph_and_sm_of(
  text : String,
) -> (@core.ProjNode[@ast.Term], @scope.ScopeGraph, SourceMap) raise {
  let (cst, _errs) = @parser.parse_cst(text)
  let syntax = @seam.SyntaxNode::from_cst(cst)
  let proj = to_proj_node(syntax, Ref(0))
  let sm = SourceMap::from_ast(proj)
  populate_token_spans(sm, syntax, proj)
  let registry = scope_test_registry(proj)
  let g = @scope.build(registry, sm)
  (proj, g, sm)
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
// `proj.children[..]`) — a genuine non-circular check (case 6 distinguishes
// inner vs outer). For MODULE cases identity is carried by `def_index` alone;
// re-asserting the LetDef node id would merely restate how this generic
// ProjNode fixture builds the tree.

///|
test "declaration() resolves a Var to its enclosing Lam param" {
  // (x) => x — the body Var binds to the lambda parameter (the Lam node itself).
  let (proj, g) = graph_of("(x) => x")
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
  let (proj, g) = graph_of("let x = 0\nx")
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
  let (proj, g) = graph_of("let x = x\nx")
  let ref_id = find_var(proj, "x") // first Var = def 0's init
  inspect(@scope.declaration(g, ref_id) is None, content="true")
}

///|
test "declaration() picks the latest shadowing module def" {
  // let x = 1\nlet x = 2\nx — the body Var binds to the LATER def (index 1).
  let (proj, g) = graph_of("let x = 1\nlet x = 2\nx")
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
  let (proj, g) = graph_of("let a = b\nlet b = 1\na")
  let ref_id = find_var(proj, "b") // the `b` in `a = b`
  inspect(@scope.declaration(g, ref_id) is None, content="true")
}

///|
test "declaration() resolves to the nearest enclosing Lam under shadowing" {
  // (x) => (x) => x — the innermost Var binds to the INNER lambda param.
  let (proj, g) = graph_of("(x) => (x) => x")
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
  let (proj, g) = graph_of("let x = 0\n(x) => x")
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
  let (proj, g) = graph_of("let x = 1\nlet x = x\nx")
  let ref_id = find_var(proj, "x") // first Var = def 1's init `x`
  guard @scope.declaration(g, ref_id) is Some(d) else {
    fail("expected resolved declaration")
  }
  let (tag, _binder, def_index) = norm_decl(d)
  inspect(tag, content="module")
  inspect(def_index, content="0") // def 1's init resolves to earlier def 0
}
