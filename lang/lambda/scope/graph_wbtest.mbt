///|
/// Build (proj, flat_proj, registry, source_map) from source.
fn build_fixture(
  text : String,
) -> (
  @core.ProjNode[@ast.Term],
  @lambda_proj.FlatProj,
  Map[@core.NodeId, @core.ProjNode[@ast.Term]],
  @core.SourceMap,
) raise {
  let (proj, _errs) = @lambda_proj.parse_to_proj_node(text)
  let flat_proj = @lambda_proj.FlatProj::from_proj_node(proj)
  let source_map = @core.SourceMap::from_ast(proj)
  let registry : Map[@core.NodeId, @core.ProjNode[@ast.Term]] = {}
  @core.collect_registry(proj, registry)
  (proj, flat_proj, registry, source_map)
}

///|
/// Find the first Var node with the given name anywhere in the tree.
fn find_var_node(
  root : @core.ProjNode[@ast.Term],
  name : String,
) -> @core.NodeId {
  let mut found : @core.NodeId? = None
  fn walk(n : @core.ProjNode[@ast.Term]) -> Unit {
    if found is Some(_) {
      return
    }
    if n.kind is @ast.Term::Var(x) && x == name {
      found = Some(n.id())
      return
    }
    for c in n.children {
      walk(c)
    }
  }

  walk(root)
  found.unwrap()
}

///|
test "build: module defs become ModuleDef decls in root scope" {
  let (_proj, flat_proj, registry, source_map) = build_fixture(
    "let a = 1\nlet b = 2\nb",
  )
  let g = build(flat_proj, registry, source_map)
  inspect(g.decls.length(), content="2")
  guard g.decls[0].kind is ModuleDef(def_index=d0)
  inspect(d0, content="0")
  guard g.decls[1].kind is ModuleDef(def_index=d1)
  inspect(d1, content="1")
  let ScopeId(s0) = g.decls[0].scope
  inspect(s0, content="0")
}

///|
test "build_parent_map: child maps to parent" {
  // Hand-built tree: root(id=0) Lam with one child Var(id=1).
  let child = @core.ProjNode::new(@ast.Term::Var("x"), 0, 1, 1, [])
  let root = @core.ProjNode::new(
    @ast.Term::Lam("x", @ast.Term::Var("x")),
    0,
    5,
    0,
    [child],
  )
  let registry : Map[@core.NodeId, @core.ProjNode[@ast.Term]] = {}
  @core.collect_registry(root, registry)
  let parents = build_parent_map(registry)
  inspect(parents.get(@core.NodeId::from_int(1)) is Some(_), content="true")
  guard parents.get(@core.NodeId::from_int(1)) is Some(p)
  inspect(p == @core.NodeId::from_int(0), content="true")
  inspect(parents.get(@core.NodeId::from_int(0)) is None, content="true")
}

///|
/// Find the Var with `name` in the module body (the final/last child).
fn find_var_in_body(
  root : @core.ProjNode[@ast.Term],
  name : String,
) -> @core.NodeId {
  match root.kind {
    @ast.Term::Module(_, _) =>
      find_var_node(root.children[root.children.length() - 1], name)
    _ => find_var_node(root, name)
  }
}

///|
/// Find the Var with `name` inside the init expression of flat def `idx`.
/// def inits are the Module's leading children (before the body).
fn find_var_in_def_init(
  root : @core.ProjNode[@ast.Term],
  idx : Int,
  name : String,
) -> @core.NodeId {
  match root.kind {
    @ast.Term::Module(_, _) => find_var_node(root.children[idx], name)
    _ => find_var_node(root, name)
  }
}

///|
test "resolve: lambda param" {
  let (proj, flat_proj, registry, source_map) = build_fixture("λx. x")
  let g = build(flat_proj, registry, source_map)
  let var_node = find_var_node(proj, "x")
  guard declaration(g, var_node) is Some(decl)
  inspect(decl.kind is LamParam(_), content="true")
}

///|
test "resolve: self-reference is unbound" {
  let (proj, flat_proj, registry, source_map) = build_fixture("let x = x\nx")
  let g = build(flat_proj, registry, source_map)
  let init_var = find_var_in_def_init(proj, 0, "x")
  inspect(declaration(g, init_var) is None, content="true")
}

///|
test "resolve: second def init binds to first def" {
  let (proj, flat_proj, registry, source_map) = build_fixture(
    "let x = 1\nlet x = x\nx",
  )
  let g = build(flat_proj, registry, source_map)
  let init_var = find_var_in_def_init(proj, 1, "x")
  guard declaration(g, init_var) is Some(decl)
  guard decl.kind is ModuleDef(def_index~)
  inspect(def_index, content="0")
}

///|
test "resolve: innermost lambda shadowing" {
  let (proj, flat_proj, registry, source_map) = build_fixture("λx. λx. x")
  let g = build(flat_proj, registry, source_map)
  let var_node = find_var_node(proj, "x")
  guard declaration(g, var_node) is Some(decl)
  inspect(decl.kind is LamParam(_), content="true")
}

///|
test "resolve: body binds to latest def" {
  let (proj, flat_proj, registry, source_map) = build_fixture(
    "let x = 1\nlet x = 2\nx",
  )
  let g = build(flat_proj, registry, source_map)
  let body_var = find_var_in_body(proj, "x")
  guard declaration(g, body_var) is Some(decl)
  guard decl.kind is ModuleDef(def_index~)
  inspect(def_index, content="1")
}

///|
test "resolve: earlier def cannot see later def" {
  let (proj, flat_proj, registry, source_map) = build_fixture(
    "let a = b\nlet b = 1\na",
  )
  let g = build(flat_proj, registry, source_map)
  let init_var = find_var_in_def_init(proj, 0, "b")
  inspect(declaration(g, init_var) is None, content="true")
}

///|
test "references: identity-based, shadowing-aware" {
  let (_proj, flat_proj, registry, source_map) = build_fixture(
    "let x = 1\nlet x = 2\nx",
  )
  let g = build(flat_proj, registry, source_map)
  let def1 = g.decls[1].id
  let def0 = g.decls[0].id
  inspect(references(g, def1).length() >= 1, content="true")
  inspect(references(g, def0).length(), content="0")
}

///|
test "enclosing_env: lambda params in scope" {
  let (proj, flat_proj, registry, source_map) = build_fixture("λx. λy. x")
  let g = build(flat_proj, registry, source_map)
  let var_node = find_var_node(proj, "x")
  let env = enclosing_env(g, var_node)
  inspect(env.contains("x"), content="true")
  inspect(env.contains("y"), content="true")
}
