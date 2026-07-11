///|
fn graph_for_root(root : @core.ProjNode[@ast.Term]) -> @scope.ScopeGraph {
  let source_map = @core.SourceMap::from_ast(root)
  let registry : Map[@core.NodeId, @core.ProjNode[@ast.Term]] = {}
  @core.collect_registry(root, registry)
  @scope.build(registry, source_map)
}

///|
fn parse_fixture(
  text : String,
) -> (@core.ProjNode[@ast.Term], @scope.ScopeGraph) raise {
  let (proj, errors) = @lambda_proj.parse_to_proj_node(text)
  if errors.length() > 0 {
    fail("parse diagnostics in alpha-egraph fixture")
  }
  (proj, graph_for_root(proj))
}

///|
fn generated_binder(id : Int, hint : String) -> @alpha.Binder {
  { id: @alpha.BinderId(id), hint, origin: @alpha.BinderOrigin::Generated(id) }
}

///|
fn source_free(name : String) -> @alpha.AlphaTerm {
  @alpha.AlphaTerm::Var(Free({ name, origin: @alpha.FreeOrigin::SourceVar }))
}

///|
test "alpha egraph: canonical capture fixture stays capture-free" {
  let (proj, graph) = parse_fixture("((x) => (y) => x) y")
  let optimized = optimize_alpha(@alpha.lower_root(proj, graph))
  let expected = @alpha.AlphaTerm::Lam(
    generated_binder(99, "y1"),
    source_free("y"),
  )
  assert_true(@alpha.alpha_key(optimized) == @alpha.alpha_key(expected))
  guard @alpha.reify(optimized, Source)
    is @ast.Term::Lam(param, @ast.Term::Var(body)) else {
    fail("expected reified lambda")
  }
  inspect(param, content="y1")
  inspect(body, content="y")
}

///|
test "alpha egraph: projected boundary lowers through scope and reifies" {
  let (proj, graph) = parse_fixture("((x) => (y) => x) y")
  guard optimize_projected(proj, graph)
    is @ast.Term::Lam(param, @ast.Term::Var(body)) else {
    fail("expected projected optimizer to reify lambda")
  }
  inspect(param, content="y1")
  inspect(body, content="y")
}

///|
test "alpha egraph: arithmetic rules and folding reuse egraph extraction" {
  let (proj, graph) = parse_fixture("((n) => n + 0) (1 + 2)")
  let optimized = optimize_alpha(@alpha.lower_root(proj, graph))
  inspect(@alpha.reify(optimized, Source), content="Int(3)")
}

///|
test "alpha egraph: duplicated beta argument extracts without residual subst" {
  let (proj, graph) = parse_fixture("((n) => n + n) (1 + 2)")
  let optimized = optimize_alpha(@alpha.lower_root(proj, graph))
  inspect(@alpha.reify(optimized, Source), content="Int(6)")
}

///|
test "alpha egraph: untyped arithmetic identity does not erase lambda" {
  let (proj, graph) = parse_fixture("((x) => x) + 0")
  guard optimize_projected(proj, graph)
    is @ast.Term::Bop(Plus, @ast.Term::Lam(_, _), @ast.Term::Int(0)) else {
    fail("expected non-numeric arithmetic operand to remain stuck")
  }
}

///|
test "alpha egraph: beta does not erase hole arguments" {
  let (proj, graph) = parse_fixture("((x) => 1) _")
  guard optimize_projected(proj, graph)
    is @ast.Term::App(@ast.Term::Lam(_, @ast.Term::Int(1)), @ast.Term::Hole(_)) else {
    fail("expected beta to preserve incomplete argument")
  }
}

///|
test "alpha egraph: beta does not erase error arguments" {
  let term = @alpha.AlphaTerm::App(
    @alpha.AlphaTerm::Lam(generated_binder(1, "x"), @alpha.AlphaTerm::Int(1)),
    @alpha.AlphaTerm::Error("bad argument"),
  )
  guard optimize_alpha(term)
    is @alpha.AlphaTerm::App(_, @alpha.AlphaTerm::Error(_)) else {
    fail("expected beta to preserve error argument")
  }
}
