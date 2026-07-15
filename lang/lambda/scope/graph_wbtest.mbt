///|
/// Build (proj, registry, source_map) from source.
fn build_fixture(
  text : String,
) -> (
  @core.ProjNode[@ast.Term],
  Map[@core.NodeId, @core.ProjNode[@ast.Term]],
  @core.SourceMap,
) raise {
  let (proj, _errs) = @lambda_proj.parse_to_proj_node(text)
  let source_map = @core.SourceMap::from_ast(proj)
  let registry : Map[@core.NodeId, @core.ProjNode[@ast.Term]] = Map([])
  @core.collect_registry(proj, registry)
  (proj, registry, source_map)
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
  let (_proj, registry, source_map) = build_fixture("let a = 1\nlet b = 2\nb")
  let g = build(registry, source_map)
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
  let child = @core.ProjNode(@ast.Term::Var("x"), 0, 1, 1, [])
  let root = @core.ProjNode(@ast.Term::Lam("x", @ast.Term::Var("x")), 0, 5, 0, [
    child,
  ])
  let registry : Map[@core.NodeId, @core.ProjNode[@ast.Term]] = Map([])
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
test "build: duplicate module defs use structural binder ids and cutoffs" {
  let (proj, registry, source_map) = build_fixture("let x = 1\nlet x = x\nx")
  let g = build(registry, source_map)
  guard proj.kind is @ast.Term::Module(_, _) else { fail("expected module") }
  inspect(g.decls[0].node_id == proj.children[0].id(), content="true")
  inspect(g.decls[1].node_id == proj.children[1].id(), content="true")
  let init_var = find_var_in_def_init(proj, 1, "x")
  guard declaration(g, init_var) is Some(init_decl)
  guard init_decl.kind is ModuleDef(def_index=init_index)
  inspect(init_index, content="0")
  let body_var = find_var_in_body(proj, "x")
  guard declaration(g, body_var) is Some(body_decl)
  guard body_decl.kind is ModuleDef(def_index=body_index)
  inspect(body_index, content="1")
}

///|
test "declaration_for_name_at: module nodes use full local cutoff" {
  let (proj, registry, source_map) = build_fixture("let x = 1\nlet x = 2\nx")
  let g = build(registry, source_map)
  guard declaration_for_name_at(g, proj.id(), "x") is Some(root_decl)
  guard root_decl.kind is ModuleDef(def_index=root_index)
  inspect(root_index, content="1")

  let (nested, nested_registry, nested_source_map) = build_fixture(
    "let z = { let x = 1\nx }\nz",
  )
  let nested_graph = build(nested_registry, nested_source_map)
  let block = nested.children[0].children[0]
  guard declaration_for_name_at(nested_graph, block.id(), "x")
    is Some(block_decl)
  guard block_decl.kind is ModuleDef(def_index=block_index)
  inspect(block_index, content="0")
}

///|
test "resolve: lambda param" {
  let (proj, registry, source_map) = build_fixture("(x) => x")
  let g = build(registry, source_map)
  let var_node = find_var_node(proj, "x")
  guard declaration(g, var_node) is Some(decl)
  inspect(decl.kind is LamParam(_), content="true")
}

///|
test "resolve: self-reference is unbound" {
  let (proj, registry, source_map) = build_fixture("let x = x\nx")
  let g = build(registry, source_map)
  let init_var = find_var_in_def_init(proj, 0, "x")
  inspect(declaration(g, init_var) is None, content="true")
}

///|
test "resolve: second def init binds to first def" {
  let (proj, registry, source_map) = build_fixture("let x = 1\nlet x = x\nx")
  let g = build(registry, source_map)
  let init_var = find_var_in_def_init(proj, 1, "x")
  guard declaration(g, init_var) is Some(decl)
  guard decl.kind is ModuleDef(def_index~)
  inspect(def_index, content="0")
}

///|
test "resolve: innermost lambda shadowing" {
  let (proj, registry, source_map) = build_fixture("(x) => (x) => x")
  let g = build(registry, source_map)
  let var_node = find_var_node(proj, "x")
  guard declaration(g, var_node) is Some(decl)
  inspect(decl.kind is LamParam(_), content="true")
}

///|
test "resolve: body binds to latest def" {
  let (proj, registry, source_map) = build_fixture("let x = 1\nlet x = 2\nx")
  let g = build(registry, source_map)
  let body_var = find_var_in_body(proj, "x")
  guard declaration(g, body_var) is Some(decl)
  guard decl.kind is ModuleDef(def_index~)
  inspect(def_index, content="1")
}

///|
test "resolve: earlier def cannot see later def" {
  let (proj, registry, source_map) = build_fixture("let a = b\nlet b = 1\na")
  let g = build(registry, source_map)
  let init_var = find_var_in_def_init(proj, 0, "b")
  inspect(declaration(g, init_var) is None, content="true")
}

///|
test "references: identity-based, shadowing-aware" {
  let (_proj, registry, source_map) = build_fixture("let x = 1\nlet x = 2\nx")
  let g = build(registry, source_map)
  let def1 = g.decls[1].id
  let def0 = g.decls[0].id
  inspect(references(g, def1).length() >= 1, content="true")
  inspect(references(g, def0).length(), content="0")
}

///|
test "enclosing_env: lambda params in scope" {
  let (proj, registry, source_map) = build_fixture("(x, y) => x")
  let g = build(registry, source_map)
  let var_node = find_var_node(proj, "x")
  let env = enclosing_env(g, var_node)
  inspect(env.contains("x"), content="true")
  inspect(env.contains("y"), content="true")
}

///|
test "scope_for_node: ref node uses resolution start scope" {
  let (proj, registry, source_map) = build_fixture("let x = 1\nx")
  let g = build(registry, source_map)
  let body_var = find_var_in_body(proj, "x")
  guard g.scopes.iter().find_first(fn(s) { s.parent is None }) is Some(root)
  inspect(scope_for_node(g, body_var) == Some(root.id), content="true")
}

///|
test "scope_for_node: module declaration node uses declaring scope" {
  let (proj, registry, source_map) = build_fixture("let x = 1\nx")
  let g = build(registry, source_map)
  guard g.scopes.iter().find_first(fn(s) { s.parent is None }) is Some(root)
  inspect(
    scope_for_node(g, proj.children[0].id()) == Some(root.id),
    content="true",
  )
}

///|
test "scope_for_node: lambda binder node uses expression scope" {
  let (proj, registry, source_map) = build_fixture("(x) => x")
  let g = build(registry, source_map)
  guard g.decls.iter().find_first(fn(d) { d.kind is LamParam(_) }) is Some(decl)
  inspect(decl.node_id == proj.id(), content="true")
  inspect(scope_for_node(g, proj.id()) != Some(decl.scope), content="true")
  guard scope_for_node(g, proj.id()) is Some(expr_scope)
  let ScopeId(expr_i) = expr_scope
  inspect(g.scopes[expr_i].parent is None, content="true")
  let ScopeId(decl_i) = decl.scope
  inspect(g.scopes[decl_i].parent == Some(expr_scope), content="true")
}

///|
test "scope_for_node: unknown node returns none" {
  let (_proj, registry, source_map) = build_fixture("let x = 1\nx")
  let g = build(registry, source_map)
  inspect(
    scope_for_node(g, @core.NodeId::from_int(999_999)) is None,
    content="true",
  )
}

///|
test "scope_for_node: block-local ref uses block scope" {
  let (proj, registry, source_map) = build_fixture(
    "let z = { let x = 1\nx }\nz",
  )
  let g = build(registry, source_map)
  guard proj.kind is @ast.Term::Module(_, _) else { fail("expected module") }
  let block = proj.children[0].children[0]
  let block_var = find_var_node(block, "x")
  guard scope_for_node(g, block_var) is Some(sid) else {
    fail("expected scope for block variable")
  }
  let ScopeId(si) = sid
  inspect(g.scopes[si].parent is Some(_), content="true")
}
