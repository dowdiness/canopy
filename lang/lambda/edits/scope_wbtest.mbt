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
fn module_def_references_for_test(
  g : @scope.ScopeGraph,
  def_index : Int,
) -> Result[Array[NodeId], String] {
  for decl in g.decls {
    match decl.kind {
      @scope.DeclKind::ModuleDef(def_index=i) if i == def_index =>
        return Ok(@scope.references(g, decl.id))
      _ => ()
    }
  }
  Err("No scope declaration for module def index " + def_index.to_string())
}

///|
fn def_cutoff_at_node_for_test(
  definition_index : DefinitionIndex,
  source_map : SourceMap,
  node_id : NodeId,
) -> Int {
  definition_index.cutoff_at_node(source_map, node_id)
}

///|
test "module_def_references: finds Var references in Module body" {
  let text = "let x = 0\nx + x"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = scope_test_registry(proj)
  let g = @scope.build(registry, source_map)
  match module_def_references_for_test(g, 0) {
    Ok(refs) => inspect(refs.length(), content="2")
    Err(e) => fail(e)
  }
}

///|
test "module_def_references: respects shadowing by inner Lam" {
  let text = "let x = 0\n(x) => x"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = scope_test_registry(proj)
  let g = @scope.build(registry, source_map)
  match module_def_references_for_test(g, 0) {
    Ok(refs) => inspect(refs.length(), content="0")
    Err(e) => fail(e)
  }
}

///|
test "module_def_references: later duplicate shadows body only" {
  let text = "let x = 0\nlet x = x\nx"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = scope_test_registry(proj)
  let g = @scope.build(registry, source_map)
  match
    (module_def_references_for_test(g, 0), module_def_references_for_test(g, 1)) {
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
  let fp = @lambda_proj.ModuleProjection::from_proj_node(proj)
  // First def's init is the LetDef node's child.
  let init_id = proj.children[0].children[0].id()
  let index = fp.definition_index()
  match find_binding_for_init(init_id, index) {
    Some((binding_id, def_index)) => {
      inspect(binding_id == fp.defs[0].3, content="true")
      inspect(def_index, content="0")
    }
    None => fail("expected Some")
  }
  match find_binding_for_init(proj.children[0].id(), index) {
    Some((binding_id, def_index)) => {
      inspect(binding_id == fp.defs[0].3, content="true")
      inspect(def_index, content="0")
    }
    None => fail("expected Some for LetDef id")
  }
}

///|
test "find_binding_for_init: returns None for non-init node" {
  let text = "let x = 0\nx"
  let (proj, _) = parse_to_proj_node(text)
  let fp = @lambda_proj.ModuleProjection::from_proj_node(proj)
  // Body node is not an init expression
  let body = proj.children.last().unwrap()
  inspect(
    find_binding_for_init(body.id(), fp.definition_index()) is None,
    content="true",
  )
}

///|
test "find_binding_for_init: duplicate defs return matching binding order" {
  let text = "let x = 0\nlet x = x\nx"
  let (proj, _) = parse_to_proj_node(text)
  let fp = @lambda_proj.ModuleProjection::from_proj_node(proj)
  let index = fp.definition_index()
  match find_binding_for_init(fp.defs[0].1.id(), index) {
    Some((binding_id, def_index)) => {
      inspect(binding_id == fp.defs[0].3, content="true")
      inspect(def_index, content="0")
    }
    None => fail("expected first duplicate binding")
  }
  match find_binding_for_init(fp.defs[1].1.id(), index) {
    Some((binding_id, def_index)) => {
      inspect(binding_id == fp.defs[1].3, content="true")
      inspect(def_index, content="1")
    }
    None => fail("expected second duplicate binding")
  }
}

///|
test "def_cutoff_at_node: duplicate defs use init-range cutoff" {
  let text = "let x = 0\nlet x = x\nx"
  let (proj, _) = parse_to_proj_node(text)
  let fp = @lambda_proj.ModuleProjection::from_proj_node(proj)
  let source_map = SourceMap::from_ast(proj)
  let body = proj.children.last().unwrap()
  let index = fp.definition_index()
  inspect(
    def_cutoff_at_node_for_test(index, source_map, fp.defs[0].1.id()),
    content="0",
  )
  inspect(
    def_cutoff_at_node_for_test(index, source_map, fp.defs[1].1.id()),
    content="1",
  )
  inspect(
    def_cutoff_at_node_for_test(index, source_map, body.id()),
    content="2",
  )
  inspect(
    def_cutoff_at_node_for_test(index, source_map, NodeId::from_int(999_999)),
    content="2",
  )
}
