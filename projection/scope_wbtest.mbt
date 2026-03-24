///|
fn scope_test_registry(
  root : ProjNode[@ast.Term],
) -> Map[NodeId, ProjNode[@ast.Term]] {
  let registry : Map[NodeId, ProjNode[@ast.Term]] = {}
  fn register(node : ProjNode[@ast.Term]) {
    registry[node.id()] = node
    for child in node.children {
      register(child)
    }
  }
  register(root)
  registry
}

///|
test "resolve_binder: Var bound by Lam" {
  let text = "λx. x"
  let (proj, _) = parse_to_proj_node(text)
  let fp = FlatProj::from_proj_node(proj)
  let source_map = SourceMap::from_ast(proj)
  let registry = scope_test_registry(proj)
  // The Lam's body is Var("x") — it's child[0] of the Lam
  let var_node = proj.children[0]
  match resolve_binder(var_node.id(), "x", fp, registry, source_map) {
    Some(LamBinder(lam_id~)) => inspect(lam_id == proj.id(), content="true")
    _ => fail("expected LamBinder")
  }
}

///|
test "resolve_binder: Var bound by Module let-def" {
  let text = "let x = 0\nx"
  let (proj, _) = parse_to_proj_node(text)
  let fp = FlatProj::from_proj_node(proj)
  let source_map = SourceMap::from_ast(proj)
  let registry = scope_test_registry(proj)
  // Body is last child of Module
  let body = proj.children[proj.children.length() - 1]
  match resolve_binder(body.id(), "x", fp, registry, source_map) {
    Some(ModuleBinder(def_index~, ..)) => inspect(def_index, content="0")
    _ => fail("expected ModuleBinder")
  }
}

///|
test "find_usages: finds Var references in Module body" {
  let text = "let x = 0\nx + x"
  let (proj, _) = parse_to_proj_node(text)
  let fp = FlatProj::from_proj_node(proj)
  let registry = scope_test_registry(proj)
  let usages = find_usages("x", 0, fp, registry)
  inspect(usages.length(), content="2")
}

///|
test "find_usages: respects shadowing by inner Lam" {
  let text = "let x = 0\nλx. x"
  let (proj, _) = parse_to_proj_node(text)
  let fp = FlatProj::from_proj_node(proj)
  let registry = scope_test_registry(proj)
  let usages = find_usages("x", 0, fp, registry)
  inspect(usages.length(), content="0")
}

///|
test "find_usages: shadowed by later def suppresses body" {
  let text = "let x = 0\nlet x = 1\nx"
  let (proj, _) = parse_to_proj_node(text)
  let fp = FlatProj::from_proj_node(proj)
  let registry = scope_test_registry(proj)
  // Starting from def 0, def 1 shadows "x" — body should not be searched for def 0's usages
  let usages = find_usages("x", 0, fp, registry)
  inspect(usages.length(), content="0")
}

///|
test "find_binding_for_init: maps init ProjNode to binding NodeId" {
  let text = "let x = 0\nlet y = 1\nx + y"
  let (proj, _) = parse_to_proj_node(text)
  let fp = FlatProj::from_proj_node(proj)
  // First def's init is proj.children[0]
  let init_id = proj.children[0].id()
  match find_binding_for_init(init_id, fp) {
    Some((binding_id, def_index)) => {
      inspect(binding_id == fp.defs[0].3, content="true")
      inspect(def_index, content="0")
    }
    None => fail("expected Some")
  }
}

///|
test "find_binding_for_init: returns None for non-init node" {
  let text = "let x = 0\nx"
  let (proj, _) = parse_to_proj_node(text)
  let fp = FlatProj::from_proj_node(proj)
  // Body node is not an init expression
  let body = proj.children[proj.children.length() - 1]
  inspect(find_binding_for_init(body.id(), fp), content="None")
}
