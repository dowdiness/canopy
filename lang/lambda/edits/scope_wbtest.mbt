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
test "module_def_references: finds Var references in Module body" {
  let text = "let x = 0\nx + x"
  let (proj, _) = parse_to_proj_node(text)
  let fp = FlatProj::from_proj_node(proj)
  let source_map = SourceMap::from_ast(proj)
  let registry = scope_test_registry(proj)
  let g = @scope.build(fp, registry, source_map)
  match module_def_references(g, 0) {
    Ok(refs) => inspect(refs.length(), content="2")
    Err(e) => fail(e)
  }
}

///|
test "module_def_references: respects shadowing by inner Lam" {
  let text = "let x = 0\nλx. x"
  let (proj, _) = parse_to_proj_node(text)
  let fp = FlatProj::from_proj_node(proj)
  let source_map = SourceMap::from_ast(proj)
  let registry = scope_test_registry(proj)
  let g = @scope.build(fp, registry, source_map)
  match module_def_references(g, 0) {
    Ok(refs) => inspect(refs.length(), content="0")
    Err(e) => fail(e)
  }
}

///|
test "module_def_references: later duplicate shadows body only" {
  let text = "let x = 0\nlet x = x\nx"
  let (proj, _) = parse_to_proj_node(text)
  let fp = FlatProj::from_proj_node(proj)
  let source_map = SourceMap::from_ast(proj)
  let registry = scope_test_registry(proj)
  let g = @scope.build(fp, registry, source_map)
  match (module_def_references(g, 0), module_def_references(g, 1)) {
    (Ok(first_refs), Ok(second_refs)) => {
      // The first def is referenced by the second def's init; the body resolves
      // to the second def. This is the identity-based case the old name scan
      // could not distinguish when callers started at def_index + 1.
      inspect(first_refs.length(), content="1")
      inspect(second_refs.length(), content="1")
    }
    (Err(e), _) | (_, Err(e)) => fail(e)
  }
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
  inspect(find_binding_for_init(body.id(), fp) is None, content="true")
}
