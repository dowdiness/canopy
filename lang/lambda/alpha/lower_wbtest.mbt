///|
test "lower: lambda references resolve to bound binder ids" {
  let (proj, graph) = alpha_parse_fixture("(x) => x")
  guard find_var_node(proj, "x") is Some(var_node) else {
    fail("missing x ref")
  }
  guard @scope.declaration(graph, var_node) is Some(_) else {
    fail("scope graph did not resolve x")
  }
  guard lower_root(proj, graph) is Lam(binder, Var(Bound(ref_id))) else {
    fail("expected lambda with bound body")
  }
  inspect(ref_id == binder.id, content="true")
}

///|
test "lower: unresolved source var remains free" {
  let (proj, graph) = alpha_parse_fixture("y")
  guard find_var_node(proj, "y") is Some(var_node) else {
    fail("missing y ref")
  }
  inspect(@scope.declaration(graph, var_node) is None, content="true")
  guard lower_root(proj, graph) is Var(Free(free)) else {
    fail("expected free var")
  }
  inspect(free.name, content="y")
  inspect(free.origin == SourceVar, content="true")
}

///|
test "lower: source Unbound origin is preserved" {
  let root = @core.ProjNode(@ast.Term::Unbound("missing"), 0, 7, 0, [])
  let graph = graph_for_root(root)
  guard lower_root(root, graph) is Var(Free(free)) else {
    fail("expected free unbound")
  }
  inspect(free.name, content="missing")
  inspect(free.origin == SourceUnbound, content="true")
}

///|
test "lower: source Unbound remains free even when a binder has the same name" {
  let child = @core.ProjNode(@ast.Term::Unbound("x"), 0, 1, 1, [])
  let root = @core.ProjNode(
    @ast.Term::Lam("x", @ast.Term::Unbound("x")),
    0,
    8,
    0,
    [child],
  )
  let graph = graph_for_root(root)
  guard lower_root(root, graph) is Lam(_, Var(Free(free))) else {
    fail("expected lambda body to stay SourceUnbound")
  }
  inspect(free.name, content="x")
  inspect(free.origin == SourceUnbound, content="true")
}

///|
test "lower: Error and Hole survive" {
  let error_root = @core.ProjNode(@ast.Term::Error("bad"), 0, 3, 0, [])
  let hole_root = @core.ProjNode(@ast.Term::Hole(2), 0, 1, 0, [])
  inspect(
    lower_root(error_root, graph_for_root(error_root)) is Error("bad"),
    content="true",
  )
  inspect(
    lower_root(hole_root, graph_for_root(hole_root)) is Hole(2),
    content="true",
  )
}

///|
test "lower: sequential module scope follows ScopeGraph" {
  let (proj, graph) = alpha_parse_fixture("let x = 1\nlet x = x\nx")
  guard lower_root(proj, graph) is Module(defs, Var(Bound(body_id))) else {
    fail("expected lowered module")
  }
  guard defs.length() == 2 else { fail("expected two definitions") }
  let (first_binder, _) = defs[0]
  let (second_binder, second_init) = defs[1]
  guard second_init is Var(Bound(init_id)) else {
    fail("expected second init to reference first x")
  }
  inspect(init_id == first_binder.id, content="true")
  inspect(body_id == second_binder.id, content="true")
}

///|
test "lower: generated fallback binder ids use node identity" {
  let binders : Map[@core.NodeId, Binder] = {}
  let first = @core.ProjNode(@ast.Term::Lam("x", @ast.Term::Unit), 0, 0, 7, [])
  let second = @core.ProjNode(@ast.Term::Lam("x", @ast.Term::Unit), 0, 0, 8, [])
  let first_binder = binder_for_node(binders, first, "x")
  let second_binder = binder_for_node(binders, second, "x")
  inspect(first_binder.id == second_binder.id, content="false")
}
